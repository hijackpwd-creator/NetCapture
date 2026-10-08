#pragma once
#import <Foundation/Foundation.h>
#import "../Shared/NCProtocol.h"
@class NCClientConnection;
@interface NCTransactionAssembler : NSObject
+ (instancetype)shared;
- (void)receiveMessage:(NCMessageType)type metadata:(NSDictionary *)metadata payload:(NSData *)payload connection:(NCClientConnection *)connection;
- (void)connectionDidClose:(NCClientConnection *)connection;
@end
