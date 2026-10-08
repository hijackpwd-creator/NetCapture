#pragma once
#import <Foundation/Foundation.h>

@class NCServerTransaction, NCServerHop, NCServerBodyState;

NS_ASSUME_NONNULL_BEGIN

@interface NCBodyWriter : NSObject
+ (instancetype)shared;
- (BOOL)appendPayload:(NSData *)payload
               offset:(uint64_t)offset
          transaction:(NCServerTransaction *)transaction
                  hop:(NCServerHop *)hop
            direction:(NSString *)direction
                state:(NCServerBodyState *)state;
- (void)closeFileForState:(NCServerBodyState *)state;
@end

NS_ASSUME_NONNULL_END
