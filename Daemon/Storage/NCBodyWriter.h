#pragma once
#import <Foundation/Foundation.h>
@class NCServerTransaction, NCServerHop, NCServerBodyState;
@interface NCBodyWriter : NSObject
+ (instancetype)shared;
- (BOOL)appendPayload:(NSData *)payload offset:(uint64_t)offset transaction:(NCServerTransaction *)tx hop:(NCServerHop *)hop state:(NCServerBodyState *)state;
- (void)closeFileForState:(NCServerBodyState *)state;
@end
