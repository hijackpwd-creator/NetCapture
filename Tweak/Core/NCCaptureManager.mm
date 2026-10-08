#import "NCCaptureManager.h"
#import "../IPC/NCIPCClient.h"
#import "../../Shared/NCHeaderField.h"
#import "../../Shared/NCModels.h"
#import <os/lock.h>

@interface NCClientRecord : NSObject
@property(nonatomic, copy) NSString *tx, *hop;
@property(nonatomic, strong) NSURLRequest *request;
@property BOOL begun, ended;
@end
@implementation NCClientRecord @end

@interface NCCaptureManager () {
    os_unfair_lock _lock;
    NSMapTable *_map;
}
@end

@implementation NCCaptureManager
+ (instancetype)shared { static id x; static dispatch_once_t once; dispatch_once(&once, ^{ x=[self new]; }); return x; }
- (instancetype)init { if ((self=[super init])) { _lock=OS_UNFAIR_LOCK_INIT; _map=[NSMapTable weakToStrongObjectsMapTable]; } return self; }

- (void)observeCreatedTask:(NSURLSessionTask *)task request:(NSURLRequest *)request {
    if (!task || !request) return;
    os_unfair_lock_lock(&_lock);
    if (![_map objectForKey:task]) {
        NCClientRecord *r=[NCClientRecord new];
        r.tx=[NSUUID UUID].UUIDString;
        r.hop=[NSUUID UUID].UUIDString;
        r.request=request;
        [_map setObject:r forKey:task];
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)taskWillResume:(NSURLSessionTask *)task {
    NCClientRecord *r=nil;
    os_unfair_lock_lock(&_lock);
    r=[_map objectForKey:task];
    if (r && !r.begun) r.begun=YES; else r=nil;
    os_unfair_lock_unlock(&_lock);
    if (!r) return;

    NSTimeInterval now=[NSDate date].timeIntervalSince1970;
    [[NCIPCClient shared] sendType:NCMessageTransactionBegin metadata:@{
        @"transaction":r.tx, @"source":@(NCCaptureSourceNSURLSession),
        @"task_id":@(task.taskIdentifier), @"started_at":@(now)
    } payload:nil];
    [[NCIPCClient shared] sendType:NCMessageHopBegin metadata:@{
        @"transaction":r.tx, @"hop":r.hop, @"index":@0, @"started_at":@(now),
        @"method":r.request.HTTPMethod?:@"GET", @"url":r.request.URL.absoluteString?:@"",
        @"headers":NCHeaderJSONList(NCHeaderListFromDictionary(r.request.allHTTPHeaderFields?:@{}))
    } payload:nil];

    NSData *b=r.request.HTTPBody;
    if (b.length) {
        uint64_t offset=0, dropped=0;
        while (offset < b.length) {
            NSUInteger n=(NSUInteger)MIN((uint64_t)NC_MAX_PAYLOAD_SIZE, (uint64_t)b.length-offset);
            NSData *chunk=[b subdataWithRange:NSMakeRange((NSUInteger)offset,n)];
            BOOL queued=[[NCIPCClient shared] sendType:NCMessageRequestBody metadata:@{
                @"transaction":r.tx,@"hop":r.hop,@"attempt":@1,@"offset":@(offset)
            } payload:chunk];
            if (!queued) dropped += n;
            offset += n;
        }
        [[NCIPCClient shared] sendType:NCMessageRequestBodyEnd metadata:@{
            @"transaction":r.tx,@"hop":r.hop,@"attempt":@1,@"observed":@(b.length),
            @"ipc_dropped":@(dropped),@"eof":@YES
        } payload:nil];
    }
}

static NCFailureCategory NCCategory(NSError *e) {
    if (!e) return NCFailureNone;
    if (![e.domain isEqualToString:NSURLErrorDomain]) return NCFailureUnknown;
    switch (e.code) {
        case NSURLErrorCancelled: return NCFailureCancelled;
        case NSURLErrorTimedOut: return NCFailureTimeout;
        case NSURLErrorCannotFindHost:
        case NSURLErrorDNSLookupFailed: return NCFailureDNS;
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorNetworkConnectionLost: return NCFailureConnection;
        case NSURLErrorNotConnectedToInternet: return NCFailureOffline;
        case NSURLErrorSecureConnectionFailed: return NCFailureTLS;
        default: return NCFailureUnknown;
    }
}

static NSString *NCTermination(NSError *e) {
    switch (NCCategory(e)) {
        case NCFailureNone: return @"normal";
        case NCFailureCancelled: return @"cancelled";
        case NCFailureTimeout: return @"timeout";
        case NCFailureDNS: return @"dns_failure";
        case NCFailureConnection: return @"connection_failure";
        case NCFailureTLS: return @"tls_failure";
        case NCFailureOffline: return @"offline";
        default: return @"transport_error";
    }
}

- (void)task:(NSURLSessionTask *)task completionData:(NSData *)data response:(NSURLResponse *)resp error:(NSError *)err {
    NCClientRecord *r=nil;
    os_unfair_lock_lock(&_lock);
    r=[_map objectForKey:task];
    if (!r || r.ended) { os_unfair_lock_unlock(&_lock); return; }
    r.ended=YES;
    [_map removeObjectForKey:task];
    os_unfair_lock_unlock(&_lock);
    if (!r.begun) return;

    if (resp) {
        NSInteger status=[resp isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse*)resp statusCode]:0;
        NSDictionary *h=[resp isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse*)resp allHeaderFields]:@{};
        [[NCIPCClient shared] sendType:NCMessageHopResponse metadata:@{
            @"transaction":r.tx,@"hop":r.hop,@"status":@(status),
            @"headers":NCHeaderJSONList(NCHeaderListFromDictionary(h?:@{}))
        } payload:nil];
    }

    uint64_t dropped=0;
    if (data.length) {
        uint64_t off=0;
        while (off<data.length) {
            NSUInteger n=(NSUInteger)MIN((uint64_t)NC_MAX_PAYLOAD_SIZE,(uint64_t)data.length-off);
            NSData *c=[data subdataWithRange:NSMakeRange((NSUInteger)off,n)];
            BOOL queued=[[NCIPCClient shared] sendType:NCMessageResponseBody metadata:@{
                @"transaction":r.tx,@"hop":r.hop,@"offset":@(off)
            } payload:c];
            if (!queued) dropped += n;
            off += n;
        }
    }
    [[NCIPCClient shared] sendType:NCMessageResponseBodyEnd metadata:@{
        @"transaction":r.tx,@"hop":r.hop,@"observed":@(data.length),
        @"ipc_dropped":@(dropped),@"eof":@(err==nil)
    } payload:nil];

    NSTimeInterval now=[NSDate date].timeIntervalSince1970;
    [[NCIPCClient shared] sendType:NCMessageHopEnd metadata:@{
        @"transaction":r.tx,@"hop":r.hop,@"ended_at":@(now)
    } payload:nil];
    NSMutableDictionary *m=[@{
        @"transaction":r.tx,@"ended_at":@(now),
        @"cancel_requested":@(err.code==NSURLErrorCancelled),
        @"failure_category":@(NCCategory(err)),@"termination_reason":NCTermination(err)
    } mutableCopy];
    if (err) m[@"error"]=@{@"domain":err.domain?:@"",@"code":@(err.code),@"description":err.localizedDescription?:@""};
    [[NCIPCClient shared] sendType:NCMessageTransactionEnd metadata:m payload:nil];
}
@end
