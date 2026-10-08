#import "NCServerModels.h"

@implementation NCServerBodyState
- (instancetype)init {
    self = [super init];
    if (self) {
        _fd = -1;
        _storeEnabled = YES;
    }
    return self;
}
@end

@implementation NCServerHop
- (instancetype)init {
    self = [super init];
    if (self) {
        _requestHeaders = @[];
        _responseHeaders = @[];
        _requestBody = [[NCServerBodyState alloc] init];
        _responseBody = [[NCServerBodyState alloc] init];
    }
    return self;
}
@end

@implementation NCServerTransaction
- (instancetype)init {
    self = [super init];
    if (self) {
        _storageIdentifier = NSUUID.UUID.UUIDString;
        _hops = [NSMutableDictionary dictionary];
        _hopOrder = [NSMutableArray array];
        _terminationReason = @"unknown";
    }
    return self;
}
@end
