#import "NCIPCClient.h"
#import "../../Shared/NCRuntimePaths.h"
#import <os/lock.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

static const NSUInteger kNCMaxQueuedEstimate = 5 * 1024 * 1024;
static const NSUInteger kNCFrameOverheadEstimate = 64 * 1024;

@interface NCOutgoingRequest : NSObject
@property NCMessageType type;
@property(nonatomic, copy) NSDictionary *metadata;
@property(nonatomic, strong, nullable) NSData *payload;
@property NSUInteger estimate;
@end
@implementation NCOutgoingRequest @end

@interface NCPendingWireFrame : NSObject
@property(nonatomic, strong) NSData *data;
@property NSUInteger offset;
@property NSUInteger estimate;
@end
@implementation NCPendingWireFrame @end

@interface NCIPCClient () {
    dispatch_queue_t _q;
    dispatch_source_t _writeSource;
    int _fd;
    uint64_t _seq;
    NSString *_session;
    NSMutableArray<NCPendingWireFrame *> *_frames;
    os_unfair_lock _budgetLock;
    NSUInteger _queuedEstimate;
}
@end

@implementation NCIPCClient
+ (instancetype)shared { static id x; static dispatch_once_t once; dispatch_once(&once, ^{ x=[self new]; }); return x; }
- (instancetype)init {
    if ((self=[super init])) {
        _q=dispatch_queue_create("com.netcapture.ipc", DISPATCH_QUEUE_SERIAL);
        _fd=-1; _session=[NSUUID UUID].UUIDString; _frames=[NSMutableArray array];
        _budgetLock=OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (void)releaseEstimate:(NSUInteger)n {
    os_unfair_lock_lock(&_budgetLock);
    _queuedEstimate = (_queuedEstimate >= n) ? (_queuedEstimate - n) : 0;
    os_unfair_lock_unlock(&_budgetLock);
}

- (void)disconnectLocked {
    if (_writeSource) { dispatch_source_cancel(_writeSource); _writeSource=nil; }
    if (_fd>=0) { close(_fd); _fd=-1; }
    for (NCPendingWireFrame *f in _frames) [self releaseEstimate:f.estimate];
    [_frames removeAllObjects];
}

static BOOL NCSetNonBlocking(int fd) {
    int fl=fcntl(fd,F_GETFL,0);
    return fl>=0 && fcntl(fd,F_SETFL,fl|O_NONBLOCK)==0;
}

static BOOL NCSendAllBlocking(int fd, NSData *d) {
    const uint8_t *b=d.bytes; NSUInteger off=0;
    while (off<d.length) {
        ssize_t n=send(fd,b+off,d.length-off,0);
        if (n>0) { off+=(NSUInteger)n; continue; }
        if (n<0 && errno==EINTR) continue;
        return NO;
    }
    return YES;
}

- (BOOL)connectLocked {
    if (_fd>=0) return YES;
    NSString *path=[NCRuntimePaths socketPath];
    if (strlen(path.fileSystemRepresentation)>=sizeof(((struct sockaddr_un *)0)->sun_path)) return NO;
    int fd=socket(AF_UNIX,SOCK_STREAM,0);
    if (fd<0) return NO;
    int fdFlags=fcntl(fd,F_GETFD,0); if(fdFlags>=0) (void)fcntl(fd,F_SETFD,fdFlags|FD_CLOEXEC);
#ifdef SO_NOSIGPIPE
    int one=1; (void)setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
#endif
    struct sockaddr_un a={}; a.sun_family=AF_UNIX;
    strlcpy(a.sun_path,path.fileSystemRepresentation,sizeof(a.sun_path));
    if (connect(fd,(struct sockaddr *)&a,sizeof(a))!=0) { close(fd); return NO; }

    NSDictionary *hello=@{@"session":_session,@"pid":@(getpid()),@"process":[NSProcessInfo processInfo].processName?:@"",
                          @"bundle":[NSBundle mainBundle].bundleIdentifier?:@"",@"protocol":@2,@"role":@"capture"};
    NSData *frame=NCBuildFrameV2(NCMessageHello,++_seq,hello,nil,nil);
    if (!frame || !NCSendAllBlocking(fd,frame) || !NCSetNonBlocking(fd)) { close(fd); return NO; }
    _fd=fd;
    return YES;
}

- (void)ensureWriteSourceLocked {
    if (_writeSource || _fd<0) return;
    _writeSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE,_fd,0,_q);
    __weak typeof(self) w=self;
    dispatch_source_set_event_handler(_writeSource, ^{ [w drainLocked]; });
    dispatch_resume(_writeSource);
}

- (void)drainLocked {
    if (_fd<0) return;
    while (_frames.count) {
        NCPendingWireFrame *f=_frames.firstObject;
        const uint8_t *b=f.data.bytes;
        while (f.offset<f.data.length) {
            ssize_t n=send(_fd,b+f.offset,f.data.length-f.offset,MSG_DONTWAIT);
            if (n>0) { f.offset+=(NSUInteger)n; continue; }
            if (n<0 && errno==EINTR) continue;
            if (n<0 && (errno==EAGAIN || errno==EWOULDBLOCK)) { [self ensureWriteSourceLocked]; return; }
            [self disconnectLocked]; return;
        }
        [_frames removeObjectAtIndex:0];
        [self releaseEstimate:f.estimate];
    }
    if (_writeSource) { dispatch_source_cancel(_writeSource); _writeSource=nil; }
}

- (BOOL)sendType:(NCMessageType)type metadata:(NSDictionary *)m payload:(NSData *)p {
    if (p.length>NC_MAX_PAYLOAD_SIZE || !m || ![NSJSONSerialization isValidJSONObject:m]) return NO;
    NSUInteger estimate=p.length+kNCFrameOverheadEstimate;
    if (estimate>kNCMaxQueuedEstimate) return NO;
    os_unfair_lock_lock(&_budgetLock);
    if (_queuedEstimate>kNCMaxQueuedEstimate-estimate) { os_unfair_lock_unlock(&_budgetLock); return NO; }
    _queuedEstimate+=estimate;
    os_unfair_lock_unlock(&_budgetLock);

    NCOutgoingRequest *req=[NCOutgoingRequest new]; req.type=type; req.metadata=[m copy]; req.payload=p; req.estimate=estimate;
    dispatch_async(_q, ^{
        if (![self connectLocked]) { [self releaseEstimate:req.estimate]; return; }
        NSData *frame=NCBuildFrameV2(req.type,++self->_seq,req.metadata,req.payload,nil);
        if (!frame) { [self releaseEstimate:req.estimate]; return; }
        NCPendingWireFrame *wire=[NCPendingWireFrame new]; wire.data=frame; wire.estimate=req.estimate;
        [self->_frames addObject:wire];
        [self drainLocked];
    });
    return YES;
}
@end
