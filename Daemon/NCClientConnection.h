#pragma once
#import <Foundation/Foundation.h>
@interface NCClientConnection : NSObject
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, nullable) NSString *sessionID;
@property uid_t peerUID; @property gid_t peerGID;
@property(nonatomic, copy, nullable) void (^closeHandler)(NCClientConnection *);
- (instancetype)initWithFD:(int)fd;
- (void)start;
- (void)close;
@end
