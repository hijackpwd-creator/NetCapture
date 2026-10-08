#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static inline NSArray<NSString *> *NCCaptureConfiguredBundles(void) {
    return @[@"com.apple.locationd"];
}

static inline NSArray<NSString *> *NCCaptureConfiguredExecutables(void) {
    return @[@"imagent", @"locationd"];
}

NS_ASSUME_NONNULL_END
