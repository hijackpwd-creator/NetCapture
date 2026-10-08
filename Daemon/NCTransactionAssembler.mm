#import "NCTransactionAssembler.h"
#import "NCClientConnection.h"
#import "Model/NCServerModels.h"
#import "Storage/NCBodyWriter.h"
#import "Storage/NCDatabase.h"
@interface NCTransactionAssembler () { dispatch_queue_t _queue; NSMutableDictionary *_txs; } @end
@implementation NCTransactionAssembler
+ (instancetype)shared{static id x;static dispatch_once_t once;dispatch_once(&once,^{x=[self new];});return x;}
- (instancetype)init{if((self=[super init])){_queue=dispatch_queue_create("com.netcapture.asm",DISPATCH_QUEUE_SERIAL);_txs=[NSMutableDictionary dictionary];}return self;}
static NSString *S(NSDictionary*m,NSString*k){id v=m[k];return [v isKindOfClass:NSString.class]?v:nil;} static NSNumber*N(NSDictionary*m,NSString*k){id v=m[k];return [v isKindOfClass:NSNumber.class]?v:nil;}
- (NSString*)key:(NCClientConnection*)c tx:(NSString*)tid{return [NSString stringWithFormat:@"%@:%@",c.identifier,tid];}
- (NCServerTransaction*)txFor:(NSDictionary*)m c:(NCClientConnection*)c{return _txs[[self key:c tx:S(m,@"transaction")?:@""]];}
- (NCServerHop*)hopFor:(NSDictionary*)m c:(NCClientConnection*)c{NCServerTransaction*t=[self txFor:m c:c];return t.hops[S(m,@"hop")?:@""];}
- (void)receiveMessage:(NCMessageType)type metadata:(NSDictionary*)m payload:(NSData*)p connection:(NCClientConnection*)c{dispatch_async(_queue,^{@autoreleasepool{
    if(type==NCMessageTransactionBegin){NSString*tid=S(m,@"transaction");if(!tid.length)return;NSString*k=[self key:c tx:tid];if(self->_txs[k])return;NCServerTransaction*t=[NCServerTransaction new];t.identifier=tid;t.connectionIdentifier=c.identifier;t.sessionIdentifier=c.sessionID?:@"";t.peerUID=c.peerUID;t.peerGID=c.peerGID;t.source=[N(m,@"source") unsignedIntegerValue];t.taskIdentifier=[N(m,@"task_id") unsignedIntegerValue];t.startedAt=[N(m,@"started_at") doubleValue];self->_txs[k]=t;return;}
    NCServerTransaction*t=[self txFor:m c:c]; if(!t)return;
    if(type==NCMessageHopBegin){NSString*hid=S(m,@"hop");if(!hid.length||t.hops[hid])return;NCServerHop*h=[NCServerHop new];h.identifier=hid;h.index=[N(m,@"index") unsignedIntegerValue];h.method=S(m,@"method")?:@"GET";h.URLString=S(m,@"url")?:@"";h.requestHeaders=[m[@"headers"] isKindOfClass:NSArray.class]?m[@"headers"]:@[];h.startedAt=[N(m,@"started_at") doubleValue];t.hops[hid]=h;[t.hopOrder addObject:hid];return;}
    NCServerHop*h=[self hopFor:m c:c]; if(!h)return;
    if(type==NCMessageHopResponse){h.statusCode=[N(m,@"status") integerValue];h.responseHeaders=[m[@"headers"] isKindOfClass:NSArray.class]?m[@"headers"]:@[];return;}
    if(type==NCMessageResponseBody){uint64_t off=[N(m,@"offset") unsignedLongLongValue];[[NCBodyWriter shared]appendPayload:p offset:off transaction:t hop:h state:h.responseBody];return;}
    if(type==NCMessageResponseBodyEnd){h.responseBody.clientObservedBytes=[N(m,@"observed") unsignedLongLongValue];h.responseBody.ipcDroppedBytes=[N(m,@"ipc_dropped") unsignedLongLongValue];h.responseBody.reachedEOF=[N(m,@"eof") boolValue];if(!h.responseBody.reachedEOF||h.responseBody.ipcDroppedBytes||h.responseBody.clientObservedBytes>h.responseBody.receivedBytes)h.responseBody.truncated=YES;h.responseBody.ended=YES;[[NCBodyWriter shared]closeFileForState:h.responseBody];return;}
    if(type==NCMessageHopEnd){h.endedAt=[N(m,@"ended_at") doubleValue];[[NCBodyWriter shared]closeFileForState:h.responseBody];return;}
    if(type==NCMessageTransactionEnd){t.endedAt=[N(m,@"ended_at") doubleValue];t.complete=YES;t.cancelRequested=[N(m,@"cancel_requested") boolValue];t.failureCategory=[N(m,@"failure_category") unsignedIntegerValue];t.terminationReason=S(m,@"termination_reason")?:@"normal";NSDictionary*e=[m[@"error"] isKindOfClass:NSDictionary.class]?m[@"error"]:nil;if(e){t.errorDomain=S(e,@"domain");t.errorCode=[N(e,@"code") integerValue];t.errorDescription=S(e,@"description");}NSString*k=[self key:c tx:t.identifier];[self->_txs removeObjectForKey:k];[[NCDatabase shared]insertTransaction:t completion:nil];return;}
}});}
- (void)connectionDidClose:(NCClientConnection*)c{dispatch_async(_queue,^{NSMutableArray*keys=[NSMutableArray array];for(NSString*k in self->_txs){NCServerTransaction*t=self->_txs[k];if([t.connectionIdentifier isEqualToString:c.identifier])[keys addObject:k];}for(NSString*k in keys){NCServerTransaction*t=self->_txs[k];t.complete=NO;t.ipcLoss=YES;t.terminationReason=@"client_disconnect";t.endedAt=[NSDate date].timeIntervalSince1970;for(NSString*hid in t.hopOrder)[[NCBodyWriter shared]closeFileForState:t.hops[hid].responseBody];[self->_txs removeObjectForKey:k];[[NCDatabase shared]insertTransaction:t completion:nil];}});}
@end
