#import <Foundation/Foundation.h>
#import "NCURLSessionHook.h"
#import "NCHookRegistry.h"
#import "../Core/NCCaptureManager.h"

static void ncResume(NSURLSessionTask *self, SEL cmd) {
    @try { [[NCCaptureManager shared] taskWillResume:self]; }
    @catch (__unused NSException *x) {}

    IMP imp = [[NCHookRegistry shared] originalIMPForObject:self selector:cmd];
    if (imp) ((void(*)(id,SEL))imp)(self, cmd);
}

static void NCInstallTaskHooksForClass(Class c) {
    if (!c) return;
    [[NCHookRegistry shared] hookClass:c selector:@selector(resume) replacement:(IMP)ncResume];
}

typedef NSURLSessionDataTask *(*NCReqCompletionIMP)(id, SEL, NSURLRequest *, void(^)(NSData *, NSURLResponse *, NSError *));

static NSURLSessionDataTask *ncReqCompletion(NSURLSession *self, SEL cmd, NSURLRequest *req,
                                               void(^completion)(NSData *, NSURLResponse *, NSError *)) {
    __block __weak NSURLSessionDataTask *weakTask = nil;
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        NSURLSessionDataTask *t = weakTask;
        if (t) {
            @try { [[NCCaptureManager shared] task:t completionData:d response:r error:e]; }
            @catch (__unused NSException *x) {}
        }
        if (completion) completion(d, r, e);
    };

    IMP raw = [[NCHookRegistry shared] originalIMPForObject:self selector:cmd];
    if (!raw) return nil;
    NSURLSessionDataTask *t = ((NCReqCompletionIMP)raw)(self, cmd, req, wrapped);
    weakTask = t;
    @try {
        [[NCCaptureManager shared] observeCreatedTask:t request:req];
        NCInstallTaskHooksForClass([t class]);
    } @catch (__unused NSException *x) {}
    return t;
}

static void NCInstallCreationHooksForClass(Class c) {
    if (!c) return;
    [[NCHookRegistry shared] hookClass:c
                              selector:@selector(dataTaskWithRequest:completionHandler:)
                           replacement:(IMP)ncReqCompletion];
}

void NCInstallURLSessionHooks(void) {
    Class base = NSClassFromString(@"NSURLSession");
    if (!base) return;
    NCInstallCreationHooksForClass(base);
    NSURLSession *shared = [NSURLSession sharedSession];
    NCInstallCreationHooksForClass([shared class]);
    Class taskBase = NSClassFromString(@"NSURLSessionTask");
    NCInstallTaskHooksForClass(taskBase);
}
