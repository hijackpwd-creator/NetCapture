#pragma once
#import <Foundation/Foundation.h>
#include <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCClientConnection : NSObject
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, nullable) NSString *sessionID;
@property(nonatomic, assign) uid_t peerUID;
@property(nonatomic, assign) gid_t peerGID;
@property(nonatomic, copy, nullable) void (^closeHandler)(NCClientConnection *connection);
- (instancetype)initWithFD:(int)fd;
- (void)start;
- (void)close;
@end

NS_ASSUME_NONNULL_END
