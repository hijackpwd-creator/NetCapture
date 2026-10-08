#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
@interface NCHookRegistry : NSObject
+ (instancetype)shared;
- (BOOL)hookClass:(Class)cls selector:(SEL)sel replacement:(IMP)replacement;
- (IMP)originalIMPForObject:(id)object selector:(SEL)sel;
@end
