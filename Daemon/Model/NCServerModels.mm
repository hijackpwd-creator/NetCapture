#import "NCServerModels.h"
@implementation NCServerBodyState
- (instancetype)init { if ((self=[super init])) { _fd=-1; _storeEnabled=YES; } return self; }
@end
@implementation NCServerHop
- (instancetype)init { if ((self=[super init])) { _requestHeaders=@[]; _responseHeaders=@[]; _responseBody=[NCServerBodyState new]; } return self; }
@end
@implementation NCServerTransaction
- (instancetype)init { if ((self=[super init])) { _storageIdentifier=[NSUUID UUID].UUIDString; _hops=[NSMutableDictionary dictionary]; _hopOrder=[NSMutableArray array]; _terminationReason=@"unknown"; } return self; }
@end
