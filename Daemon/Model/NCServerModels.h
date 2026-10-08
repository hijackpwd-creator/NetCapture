#pragma once
#import <Foundation/Foundation.h>
#include <sys/types.h>
#import "../../Shared/NCModels.h"

@interface NCServerBodyState : NSObject
@property(nonatomic, assign) uint64_t expectedOffset;
@property(nonatomic, assign) uint64_t receivedBytes;
@property(nonatomic, assign) uint64_t storedBytes;
@property(nonatomic, assign) uint64_t clientObservedBytes;
@property(nonatomic, assign) uint64_t ipcDroppedBytes;
@property(nonatomic, assign) BOOL truncated;
@property(nonatomic, assign) BOOL corrupted;
@property(nonatomic, assign) BOOL ended;
@property(nonatomic, assign) BOOL reachedEOF;
@property(nonatomic, assign) BOOL storeEnabled;
@property(nonatomic, copy, nullable) NSString *path;
@property(nonatomic, assign) int fd;
@end

@interface NCServerHop : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *method;
@property(nonatomic, copy) NSString *URLString;
@property(nonatomic, assign) NSUInteger index;
@property(nonatomic, assign) NSInteger statusCode;
@property(nonatomic, assign) NSTimeInterval startedAt;
@property(nonatomic, assign) NSTimeInterval endedAt;
@property(nonatomic, copy) NSArray *requestHeaders;
@property(nonatomic, copy) NSArray *responseHeaders;
@property(nonatomic, strong) NCServerBodyState *requestBody;
@property(nonatomic, strong) NCServerBodyState *responseBody;
@end

@interface NCServerTransaction : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *storageIdentifier;
@property(nonatomic, copy) NSString *connectionIdentifier;
@property(nonatomic, copy) NSString *sessionIdentifier;
@property(nonatomic, copy) NSString *terminationReason;
@property(nonatomic, assign) uid_t peerUID;
@property(nonatomic, assign) gid_t peerGID;
@property(nonatomic, assign) NCCaptureSource source;
@property(nonatomic, assign) NSUInteger taskIdentifier;
@property(nonatomic, assign) NSTimeInterval startedAt;
@property(nonatomic, assign) NSTimeInterval endedAt;
@property(nonatomic, assign) BOOL complete;
@property(nonatomic, assign) BOOL ipcLoss;
@property(nonatomic, assign) BOOL cancelRequested;
@property(nonatomic, assign) NCFailureCategory failureCategory;
@property(nonatomic, copy, nullable) NSString *errorDomain;
@property(nonatomic, copy, nullable) NSString *errorDescription;
@property(nonatomic, assign) NSInteger errorCode;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NCServerHop *> *hops;
@property(nonatomic, strong) NSMutableArray<NSString *> *hopOrder;
@end
