#import "NCCaptureManager.h"
#import "../IPC/NCIPCClient.h"
#import "../../Shared/NCHeaderField.h"
#import "../../Shared/NCModels.h"
#import <os/lock.h>

@interface NCClientRecord : NSObject
@property(nonatomic, copy) NSString *transactionID;
@property(nonatomic, copy) NSString *hopID;
@property(nonatomic, strong) NSURLRequest *request;
@property(nonatomic, assign) BOOL begun;
@property(nonatomic, assign) BOOL ended;
@property(nonatomic, assign) BOOL cancelRequested;
@end
@implementation NCClientRecord @end

@interface NCCaptureManager () {
    os_unfair_lock _lock;
    NSMapTable<NSURLSessionTask *, NCClientRecord *> *_records;
}
@end

@implementation NCCaptureManager

+ (instancetype)shared {
    static NCCaptureManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[NCCaptureManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _records = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}

- (void)observeCreatedTask:(NSURLSessionTask *)task request:(NSURLRequest *)request {
    if (!task || !request) return;

    os_unfair_lock_lock(&_lock);
    if (![_records objectForKey:task]) {
        NCClientRecord *record = [[NCClientRecord alloc] init];
        record.transactionID = NSUUID.UUID.UUIDString;
        record.hopID = NSUUID.UUID.UUIDString;
        record.request = [request copy];
        [_records setObject:record forKey:task];
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)taskWillResume:(NSURLSessionTask *)task {
    if (!task) return;

    NCClientRecord *record = nil;
    os_unfair_lock_lock(&_lock);
    record = [_records objectForKey:task];
    if (record && !record.begun && !record.ended) record.begun = YES;
    else record = nil;
    os_unfair_lock_unlock(&_lock);
    if (!record) return;

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    [[NCIPCClient shared] sendType:NCMessageTransactionBegin
                          metadata:@{
        @"transaction": record.transactionID,
        @"source": @(NCCaptureSourceNSURLSession),
        @"task_id": @(task.taskIdentifier),
        @"started_at": @(now)
    }
                           payload:nil];

    [[NCIPCClient shared] sendType:NCMessageHopBegin
                          metadata:@{
        @"transaction": record.transactionID,
        @"hop": record.hopID,
        @"index": @0,
        @"started_at": @(now),
        @"method": record.request.HTTPMethod ?: @"GET",
        @"url": record.request.URL.absoluteString ?: @"",
        @"headers": NCHeaderJSONList(NCHeaderListFromDictionary(record.request.allHTTPHeaderFields ?: @{}))
    }
                           payload:nil];

    NSData *body = record.request.HTTPBody;
    if (!body.length) return;

    uint64_t offset = 0;
    uint64_t dropped = 0;
    while (offset < body.length) {
        NSUInteger length = (NSUInteger)MIN((uint64_t)NC_MAX_PAYLOAD_SIZE, (uint64_t)body.length - offset);
        NSData *chunk = [body subdataWithRange:NSMakeRange((NSUInteger)offset, length)];
        BOOL queued = [[NCIPCClient shared] sendType:NCMessageRequestBody
                                            metadata:@{
            @"transaction": record.transactionID,
            @"hop": record.hopID,
            @"attempt": @1,
            @"offset": @(offset)
        }
                                             payload:chunk];
        if (!queued) dropped += length;
        offset += length;
    }

    [[NCIPCClient shared] sendType:NCMessageRequestBodyEnd
                          metadata:@{
        @"transaction": record.transactionID,
        @"hop": record.hopID,
        @"attempt": @1,
        @"observed": @(body.length),
        @"ipc_dropped": @(dropped),
        @"eof": @YES
    }
                           payload:nil];
}

- (void)taskDidRequestCancel:(NSURLSessionTask *)task {
    if (!task) return;
    os_unfair_lock_lock(&_lock);
    NCClientRecord *record = [_records objectForKey:task];
    if (record && !record.ended) {
        record.cancelRequested = YES;
        if (!record.begun) {
            record.ended = YES;
            [_records removeObjectForKey:task];
        }
    }
    os_unfair_lock_unlock(&_lock);
}

static NCFailureCategory NCFailureCategoryForError(NSError *error) {
    if (!error) return NCFailureNone;
    if (![error.domain isEqualToString:NSURLErrorDomain]) return NCFailureUnknown;

    switch (error.code) {
        case NSURLErrorCancelled: return NCFailureCancelled;
        case NSURLErrorTimedOut: return NCFailureTimeout;
        case NSURLErrorCannotFindHost:
        case NSURLErrorDNSLookupFailed: return NCFailureDNS;
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorNetworkConnectionLost: return NCFailureConnection;
        case NSURLErrorNotConnectedToInternet: return NCFailureOffline;
        case NSURLErrorSecureConnectionFailed:
        case NSURLErrorServerCertificateHasBadDate:
        case NSURLErrorServerCertificateUntrusted:
        case NSURLErrorServerCertificateHasUnknownRoot:
        case NSURLErrorServerCertificateNotYetValid:
            return NCFailureTLS;
        default:
            return NCFailureUnknown;
    }
}

static NSString *NCTerminationReasonForError(NSError *error) {
    switch (NCFailureCategoryForError(error)) {
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

- (void)task:(NSURLSessionTask *)task
 completionData:(NSData *)data
       response:(NSURLResponse *)response
          error:(NSError *)error {
    if (!task) return;

    NCClientRecord *record = nil;
    BOOL cancelRequested = NO;
    os_unfair_lock_lock(&_lock);
    record = [_records objectForKey:task];
    if (!record || record.ended) {
        os_unfair_lock_unlock(&_lock);
        return;
    }
    record.ended = YES;
    cancelRequested = record.cancelRequested;
    [_records removeObjectForKey:task];
    os_unfair_lock_unlock(&_lock);

    if (!record.begun) return;

    if (response) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class]
            ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSDictionary *headers = [response isKindOfClass:NSHTTPURLResponse.class]
            ? ((NSHTTPURLResponse *)response).allHeaderFields : @{};

        [[NCIPCClient shared] sendType:NCMessageHopResponse
                              metadata:@{
            @"transaction": record.transactionID,
            @"hop": record.hopID,
            @"status": @(status),
            @"headers": NCHeaderJSONList(NCHeaderListFromDictionary(headers ?: @{}))
        }
                               payload:nil];
    }

    uint64_t dropped = 0;
    uint64_t offset = 0;
    while (offset < data.length) {
        NSUInteger length = (NSUInteger)MIN((uint64_t)NC_MAX_PAYLOAD_SIZE, (uint64_t)data.length - offset);
        NSData *chunk = [data subdataWithRange:NSMakeRange((NSUInteger)offset, length)];
        BOOL queued = [[NCIPCClient shared] sendType:NCMessageResponseBody
                                            metadata:@{
            @"transaction": record.transactionID,
            @"hop": record.hopID,
            @"offset": @(offset)
        }
                                             payload:chunk];
        if (!queued) dropped += length;
        offset += length;
    }

    [[NCIPCClient shared] sendType:NCMessageResponseBodyEnd
                          metadata:@{
        @"transaction": record.transactionID,
        @"hop": record.hopID,
        @"observed": @(data.length),
        @"ipc_dropped": @(dropped),
        @"eof": @(error == nil)
    }
                           payload:nil];

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    [[NCIPCClient shared] sendType:NCMessageHopEnd
                          metadata:@{
        @"transaction": record.transactionID,
        @"hop": record.hopID,
        @"ended_at": @(now)
    }
                           payload:nil];

    NSMutableDictionary *metadata = [@{
        @"transaction": record.transactionID,
        @"ended_at": @(now),
        @"cancel_requested": @(cancelRequested),
        @"failure_category": @(NCFailureCategoryForError(error)),
        @"termination_reason": NCTerminationReasonForError(error)
    } mutableCopy];

    if (error) {
        metadata[@"error"] = @{
            @"domain": error.domain ?: @"",
            @"code": @(error.code),
            @"description": error.localizedDescription ?: @""
        };
    }

    [[NCIPCClient shared] sendType:NCMessageTransactionEnd metadata:metadata payload:nil];
}

@end
