#pragma once
#import <Foundation/Foundation.h>
#import "../../Shared/NCProtocol.h"
@interface NCIPCClient : NSObject
+ (instancetype)shared;
- (BOOL)sendType:(NCMessageType)type metadata:(NSDictionary *)metadata payload:(NSData * _Nullable)payload;
@end
