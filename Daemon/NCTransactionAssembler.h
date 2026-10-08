#pragma once
#import <Foundation/Foundation.h>
#import "../Shared/NCProtocol.h"

@class NCClientConnection;

NS_ASSUME_NONNULL_BEGIN

@interface NCTransactionAssembler : NSObject
+ (instancetype)shared;
- (void)receiveMessage:(NCMessageType)type
              metadata:(NSDictionary *)metadata
               payload:(NSData *)payload
            connection:(NCClientConnection *)connection;
- (void)connectionDidClose:(NCClientConnection *)connection;
@end

NS_ASSUME_NONNULL_END
