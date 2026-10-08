#import <Foundation/Foundation.h>
#import "Hook/NCURLSessionHook.h"
#import "Generated/NCTargetConfig.h"

static BOOL NCStringInConfiguredList(NSString *value, NSArray<NSString *> *values) {
    if (!value.length) return NO;
    return [values containsObject:value];
}

static BOOL NCShouldLoad(void) {
    NSString *process = NSProcessInfo.processInfo.processName ?: @"";
    if ([process isEqualToString:@"netcaptured"]) return NO;

    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    BOOL executableMatch = NCStringInConfiguredList(process, NCCaptureConfiguredExecutables());
    BOOL bundleMatch = NCStringInConfiguredList(bundle, NCCaptureConfiguredBundles());
    return executableMatch || bundleMatch;
}

%ctor {
    @autoreleasepool {
        if (NCShouldLoad()) {
            NCInstallURLSessionHooks();
        }
    }
}
