#import "NCIPCServer.h"
#import "NCClientConnection.h"
#import "../Shared/NCRuntimePaths.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
@interface NCIPCServer(){int _fd;dispatch_queue_t _queue;dispatch_source_t _src;NSMutableDictionary*_clients;BOOL _running;}@end
@implementation NCIPCServer
- (instancetype)init{if((self=[super init])){_fd=-1;_queue=dispatch_queue_create("com.netcapture.server",DISPATCH_QUEUE_SERIAL);_clients=[NSMutableDictionary dictionary];}return self;}
static BOOL flags(int fd) {
    int f = fcntl(fd, F_GETFL, 0);
    if (f < 0 || fcntl(fd, F_SETFL, f | O_NONBLOCK) != 0) return NO;
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
#ifdef SO_NOSIGPIPE
    int one = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    return YES;
}
- (BOOL)start{__block BOOL ok=NO;dispatch_sync(_queue,^{if(self->_running){ok=YES;return;}NSString*p=[NCRuntimePaths socketPath];if(strlen(p.fileSystemRepresentation)>=sizeof(((struct sockaddr_un*)0)->sun_path))return;int fd=socket(AF_UNIX,SOCK_STREAM,0);if(fd<0||!flags(fd)){if(fd>=0)close(fd);return;}unlink(p.fileSystemRepresentation);struct sockaddr_un a={};a.sun_family=AF_UNIX;strlcpy(a.sun_path,p.fileSystemRepresentation,sizeof(a.sun_path));if(bind(fd,(struct sockaddr*)&a,sizeof(a))||listen(fd,32)){close(fd);return;}chmod(p.fileSystemRepresentation,0660);self->_fd=fd;self->_src=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,fd,0,self->_queue);__weak typeof(self)w=self;dispatch_source_set_event_handler(self->_src,^{[w acceptLoop];});dispatch_resume(self->_src);self->_running=YES;ok=YES;});return ok;}
- (void)acceptLoop{for(;;){int c=accept(_fd,NULL,NULL);if(c>=0){if(_clients.count>=128||!flags(c)){close(c);continue;}uid_t u=(uid_t)-1;gid_t g=(gid_t)-1;if(getpeereid(c,&u,&g)){close(c);continue;}NCClientConnection*x=[[NCClientConnection alloc]initWithFD:c];x.peerUID=u;x.peerGID=g;__weak typeof(self)w=self;x.closeHandler=^(NCClientConnection*closed){dispatch_async(w->_queue,^{[w->_clients removeObjectForKey:closed.identifier];});};_clients[x.identifier]=x;[x start];continue;}if(errno==EINTR)continue;if(errno==EAGAIN||errno==EWOULDBLOCK)break;break;}}
- (void)stop{dispatch_async(_queue,^{if(!self->_running)return;self->_running=NO;if(self->_src){dispatch_source_cancel(self->_src);self->_src=nil;}if(self->_fd>=0){close(self->_fd);self->_fd=-1;}NSArray*a=self->_clients.allValues;[self->_clients removeAllObjects];for(NCClientConnection*c in a)[c close];unlink([NCRuntimePaths socketPath].fileSystemRepresentation);});}
@end
