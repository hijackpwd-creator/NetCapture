#pragma once
#import <Foundation/Foundation.h>
@class NCServerTransaction;
@interface NCDatabase : NSObject
+ (instancetype)shared;
- (BOOL)start;
- (void)insertTransaction:(NCServerTransaction *)tx completion:(void(^ _Nullable)(BOOL ok))completion;
@end
