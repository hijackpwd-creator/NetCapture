#pragma once
#import <Foundation/Foundation.h>
#import "../../Shared/NCModels.h"
@interface NCServerBodyState : NSObject
@property uint64_t expectedOffset, receivedBytes, storedBytes, clientObservedBytes, ipcDroppedBytes;
@property BOOL truncated, corrupted, ended, reachedEOF, storeEnabled;
@property(nonatomic, copy, nullable) NSString *path;
@property int fd;
@end
@interface NCServerHop : NSObject
@property(nonatomic, copy) NSString *identifier, *method, *URLString;
@property NSUInteger index;
@property NSInteger statusCode;
@property NSTimeInterval startedAt, endedAt;
@property(nonatomic, copy) NSArray *requestHeaders, *responseHeaders;
@property(nonatomic, strong) NCServerBodyState *responseBody;
@end
@interface NCServerTransaction : NSObject
@property(nonatomic, copy) NSString *identifier, *storageIdentifier, *connectionIdentifier, *sessionIdentifier, *terminationReason;
@property uid_t peerUID; @property gid_t peerGID; @property NCCaptureSource source; @property NSUInteger taskIdentifier;
@property NSTimeInterval startedAt, endedAt; @property BOOL complete, ipcLoss, cancelRequested;
@property NCFailureCategory failureCategory; @property(nonatomic, copy, nullable) NSString *errorDomain, *errorDescription; @property NSInteger errorCode;
@property(nonatomic, strong) NSMutableDictionary<NSString*,NCServerHop*> *hops; @property(nonatomic, strong) NSMutableArray<NSString*> *hopOrder;
@end
