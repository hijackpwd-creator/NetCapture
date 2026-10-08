#import "NCTransactionAssembler.h"
#import "NCClientConnection.h"
#import "Model/NCServerModels.h"
#import "Storage/NCBodyWriter.h"
#import "Storage/NCDatabase.h"

static const NSUInteger kNCMaxActiveTransactionsPerConnection = 2048;
static const NSUInteger kNCMaxHopsPerTransaction = 64;

@interface NCTransactionAssembler () {
    dispatch_queue_t _queue;
    NSMutableDictionary<NSString *, NCServerTransaction *> *_transactions;
}
@end

@implementation NCTransactionAssembler

+ (instancetype)shared {
    static NCTransactionAssembler *assembler;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        assembler = [[NCTransactionAssembler alloc] init];
    });
    return assembler;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.netcapture.assembler", DISPATCH_QUEUE_SERIAL);
        _transactions = [NSMutableDictionary dictionary];
    }
    return self;
}

static NSString *NCString(NSDictionary *metadata, NSString *key) {
    id value = metadata[key];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSNumber *NCNumber(NSDictionary *metadata, NSString *key) {
    id value = metadata[key];
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

- (NSString *)transactionKeyForConnection:(NCClientConnection *)connection transactionID:(NSString *)transactionID {
    if (!connection.identifier.length || !transactionID.length) return nil;
    return [NSString stringWithFormat:@"%@:%@", connection.identifier, transactionID];
}

- (NCServerTransaction *)transactionForMetadata:(NSDictionary *)metadata connection:(NCClientConnection *)connection {
    NSString *transactionID = NCString(metadata, @"transaction");
    NSString *key = [self transactionKeyForConnection:connection transactionID:transactionID];
    return key ? _transactions[key] : nil;
}

- (NCServerHop *)hopForMetadata:(NSDictionary *)metadata connection:(NCClientConnection *)connection {
    NCServerTransaction *transaction = [self transactionForMetadata:metadata connection:connection];
    NSString *hopID = NCString(metadata, @"hop");
    return (transaction && hopID.length) ? transaction.hops[hopID] : nil;
}

- (NSUInteger)activeCountForConnection:(NCClientConnection *)connection {
    NSUInteger count = 0;
    for (NCServerTransaction *transaction in _transactions.allValues) {
        if ([transaction.connectionIdentifier isEqualToString:connection.identifier]) count++;
    }
    return count;
}

- (void)finishBodyState:(NCServerBodyState *)state metadata:(NSDictionary *)metadata {
    if (!state || state.ended) return;
    state.clientObservedBytes = [NCNumber(metadata, @"observed") unsignedLongLongValue];
    state.ipcDroppedBytes = [NCNumber(metadata, @"ipc_dropped") unsignedLongLongValue];
    state.reachedEOF = [NCNumber(metadata, @"eof") boolValue];
    if (!state.reachedEOF || state.ipcDroppedBytes > 0 || state.clientObservedBytes > state.receivedBytes) {
        state.truncated = YES;
    }
    state.ended = YES;
    [[NCBodyWriter shared] closeFileForState:state];
}

- (void)closeBodiesForHop:(NCServerHop *)hop markIncomplete:(BOOL)markIncomplete {
    for (NCServerBodyState *state in @[hop.requestBody, hop.responseBody]) {
        if (!state.ended) {
            if (markIncomplete && state.receivedBytes > 0) state.truncated = YES;
            state.ended = YES;
        }
        [[NCBodyWriter shared] closeFileForState:state];
    }
}

- (void)receiveMessage:(NCMessageType)type
              metadata:(NSDictionary *)metadata
               payload:(NSData *)payload
            connection:(NCClientConnection *)connection {
    if (!metadata || !connection) return;

    dispatch_async(_queue, ^{
        @autoreleasepool {
            if (type == NCMessageTransactionBegin) {
                NSString *transactionID = NCString(metadata, @"transaction");
                if (!transactionID.length) return;
                NSString *key = [self transactionKeyForConnection:connection transactionID:transactionID];
                if (!key || self->_transactions[key]) return;
                if ([self activeCountForConnection:connection] >= kNCMaxActiveTransactionsPerConnection) return;

                NCServerTransaction *transaction = [[NCServerTransaction alloc] init];
                transaction.identifier = transactionID;
                transaction.connectionIdentifier = connection.identifier;
                transaction.sessionIdentifier = connection.sessionID ?: @"";
                transaction.peerUID = connection.peerUID;
                transaction.peerGID = connection.peerGID;
                transaction.source = (NCCaptureSource)[NCNumber(metadata, @"source") unsignedIntegerValue];
                transaction.taskIdentifier = [NCNumber(metadata, @"task_id") unsignedIntegerValue];
                transaction.startedAt = [NCNumber(metadata, @"started_at") doubleValue];
                self->_transactions[key] = transaction;
                return;
            }

            NCServerTransaction *transaction = [self transactionForMetadata:metadata connection:connection];
            if (!transaction) return;

            if (type == NCMessageHopBegin) {
                NSString *hopID = NCString(metadata, @"hop");
                if (!hopID.length || transaction.hops[hopID]) return;
                if (transaction.hops.count >= kNCMaxHopsPerTransaction) return;

                NCServerHop *hop = [[NCServerHop alloc] init];
                hop.identifier = hopID;
                hop.index = [NCNumber(metadata, @"index") unsignedIntegerValue];
                hop.method = NCString(metadata, @"method") ?: @"GET";
                hop.URLString = NCString(metadata, @"url") ?: @"";
                hop.requestHeaders = [metadata[@"headers"] isKindOfClass:NSArray.class] ? [metadata[@"headers"] copy] : @[];
                hop.startedAt = [NCNumber(metadata, @"started_at") doubleValue];
                transaction.hops[hopID] = hop;
                [transaction.hopOrder addObject:hopID];
                return;
            }

            NCServerHop *hop = [self hopForMetadata:metadata connection:connection];
            if (!hop) return;

            switch (type) {
                case NCMessageHopResponse:
                    hop.statusCode = [NCNumber(metadata, @"status") integerValue];
                    hop.responseHeaders = [metadata[@"headers"] isKindOfClass:NSArray.class] ? [metadata[@"headers"] copy] : @[];
                    break;

                case NCMessageRequestBody: {
                    NSUInteger attempt = [NCNumber(metadata, @"attempt") unsignedIntegerValue];
                    if (attempt != 1 || !payload.length) break; // MVP: known HTTPBody only.
                    uint64_t offset = [NCNumber(metadata, @"offset") unsignedLongLongValue];
                    [[NCBodyWriter shared] appendPayload:payload
                                                 offset:offset
                                            transaction:transaction
                                                    hop:hop
                                              direction:@"request"
                                                  state:hop.requestBody];
                    break;
                }

                case NCMessageRequestBodyEnd: {
                    NSUInteger attempt = [NCNumber(metadata, @"attempt") unsignedIntegerValue];
                    if (attempt == 1) [self finishBodyState:hop.requestBody metadata:metadata];
                    break;
                }

                case NCMessageResponseBody: {
                    if (!payload.length) break;
                    uint64_t offset = [NCNumber(metadata, @"offset") unsignedLongLongValue];
                    [[NCBodyWriter shared] appendPayload:payload
                                                 offset:offset
                                            transaction:transaction
                                                    hop:hop
                                              direction:@"response"
                                                  state:hop.responseBody];
                    break;
                }

                case NCMessageResponseBodyEnd:
                    [self finishBodyState:hop.responseBody metadata:metadata];
                    break;

                case NCMessageHopEnd:
                    hop.endedAt = [NCNumber(metadata, @"ended_at") doubleValue];
                    [self closeBodiesForHop:hop markIncomplete:YES];
                    break;

                case NCMessageTransactionEnd: {
                    transaction.endedAt = [NCNumber(metadata, @"ended_at") doubleValue];
                    transaction.complete = YES;
                    transaction.cancelRequested = [NCNumber(metadata, @"cancel_requested") boolValue];
                    transaction.failureCategory = (NCFailureCategory)[NCNumber(metadata, @"failure_category") unsignedIntegerValue];
                    transaction.terminationReason = NCString(metadata, @"termination_reason") ?: @"normal";

                    NSDictionary *error = [metadata[@"error"] isKindOfClass:NSDictionary.class] ? metadata[@"error"] : nil;
                    if (error) {
                        transaction.errorDomain = NCString(error, @"domain");
                        transaction.errorCode = [NCNumber(error, @"code") integerValue];
                        transaction.errorDescription = NCString(error, @"description");
                    }

                    for (NSString *hopID in transaction.hopOrder) {
                        [self closeBodiesForHop:transaction.hops[hopID] markIncomplete:YES];
                    }

                    NSString *key = [self transactionKeyForConnection:connection transactionID:transaction.identifier];
                    if (key) [self->_transactions removeObjectForKey:key];
                    [[NCDatabase shared] insertTransaction:transaction completion:nil];
                    break;
                }

                default:
                    break;
            }
        }
    });
}

- (void)connectionDidClose:(NCClientConnection *)connection {
    if (!connection) return;
    dispatch_async(_queue, ^{
        NSMutableArray<NSString *> *keys = [NSMutableArray array];
        for (NSString *key in self->_transactions) {
            NCServerTransaction *transaction = self->_transactions[key];
            if ([transaction.connectionIdentifier isEqualToString:connection.identifier]) [keys addObject:key];
        }

        for (NSString *key in keys) {
            NCServerTransaction *transaction = self->_transactions[key];
            transaction.complete = NO;
            transaction.ipcLoss = YES;
            transaction.terminationReason = @"client_disconnect";
            transaction.endedAt = NSDate.date.timeIntervalSince1970;
            for (NSString *hopID in transaction.hopOrder) {
                [self closeBodiesForHop:transaction.hops[hopID] markIncomplete:YES];
            }
            [self->_transactions removeObjectForKey:key];
            [[NCDatabase shared] insertTransaction:transaction completion:nil];
        }
    });
}

@end
