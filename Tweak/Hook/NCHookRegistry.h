#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCHookRegistry : NSObject
+ (instancetype)shared;
- (BOOL)hookClass:(Class)cls selector:(SEL)sel replacement:(IMP)replacement;
- (IMP _Nullable)originalIMPForObject:(id)object selector:(SEL)sel;
@end

NS_ASSUME_NONNULL_END
