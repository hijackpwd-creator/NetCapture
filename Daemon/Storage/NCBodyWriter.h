#pragma once
#import <Foundation/Foundation.h>
@class NCServerTransaction, NCServerHop, NCServerBodyState;

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
