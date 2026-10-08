#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCIPCServer : NSObject
- (BOOL)start;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
