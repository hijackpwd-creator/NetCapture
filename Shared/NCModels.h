#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, NCCaptureSource) {
    NCCaptureSourceUnknown = 0,
    NCCaptureSourceCFNetwork = 50,
    NCCaptureSourceNSURLConnection = 80,
    NCCaptureSourceNSURLSession = 100,
};

typedef NS_ENUM(NSUInteger, NCFailureCategory) {
    NCFailureNone = 0,
    NCFailureCancelled,
    NCFailureTimeout,
    NCFailureDNS,
    NCFailureConnection,
    NCFailureTLS,
    NCFailureOffline,
    NCFailureUnknown,
};

typedef NS_ENUM(NSUInteger, NCHeaderFidelity) {
    NCHeaderFidelityUnknown = 0,
    NCHeaderFidelityNormalized,
    NCHeaderFidelityMultiValue,
    NCHeaderFidelityWireLike,
};

NS_ASSUME_NONNULL_END
