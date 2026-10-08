#pragma once
#import <Foundation/Foundation.h>

@class NCServerTransaction;

NS_ASSUME_NONNULL_BEGIN

@interface NCDatabase : NSObject
+ (instancetype)shared;
- (BOOL)start;
- (void)insertTransaction:(NCServerTransaction *)tx
               completion:(void (^ _Nullable)(BOOL ok))completion;
@end

NS_ASSUME_NONNULL_END
