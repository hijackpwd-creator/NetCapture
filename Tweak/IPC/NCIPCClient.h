#pragma once
#import <Foundation/Foundation.h>
#import "../../Shared/NCProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface NCIPCClient : NSObject
+ (instancetype)shared;
- (BOOL)sendType:(NCMessageType)type
        metadata:(NSDictionary *)metadata
         payload:(NSData * _Nullable)payload;
@end

NS_ASSUME_NONNULL_END
