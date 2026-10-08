#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "NCURLSessionHook.h"
#import "NCHookRegistry.h"
#import "../Core/NCCaptureManager.h"

static void ncResume(NSURLSessionTask *task, SEL selector) {
    @try {
        [[NCCaptureManager shared] taskWillResume:task];
    } @catch (__unused NSException *exception) {}

    IMP original = [[NCHookRegistry shared] originalIMPForObject:task selector:selector];
    if (original) ((void (*)(id, SEL))original)(task, selector);
}

static void ncCancel(NSURLSessionTask *task, SEL selector) {
    IMP original = [[NCHookRegistry shared] originalIMPForObject:task selector:selector];
    if (original) ((void (*)(id, SEL))original)(task, selector);

    @try {
        [[NCCaptureManager shared] taskDidRequestCancel:task];
    } @catch (__unused NSException *exception) {}
}

static void NCInstallTaskHooksForClass(Class cls) {
    if (!cls) return;
    NCHookRegistry *registry = [NCHookRegistry shared];
    [registry hookClass:cls selector:@selector(resume) replacement:(IMP)ncResume];
    [registry hookClass:cls selector:@selector(cancel) replacement:(IMP)ncCancel];
}

typedef NSURLSessionDataTask *(*NCRequestCompletionIMP)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
typedef NSURLSessionDataTask *(*NCURLCompletionIMP)(id, SEL, NSURL *, void (^)(NSData *, NSURLResponse *, NSError *));

static void NCCaptureCompletion(NSURLSessionTask *task,
                                NSData *data,
                                NSURLResponse *response,
                                NSError *error,
                                void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    if (task) {
        @try {
            [[NCCaptureManager shared] task:task completionData:data response:response error:error];
        } @catch (__unused NSException *exception) {}
    }
    // App callback intentionally stays outside the capture exception handler.
    if (completion) completion(data, response, error);
}

static NSURLSessionDataTask *ncDataTaskWithRequestCompletion(NSURLSession *session,
                                                              SEL selector,
                                                              NSURLRequest *request,
                                                              void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    __block __weak NSURLSessionDataTask *weakTask = nil;
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NCCaptureCompletion(weakTask, data, response, error, completion);
    };

    IMP raw = [[NCHookRegistry shared] originalIMPForObject:session selector:selector];
    if (!raw) return nil;
    NSURLSessionDataTask *task = ((NCRequestCompletionIMP)raw)(session, selector, request, wrapped);
    weakTask = task;

    @try {
        [[NCCaptureManager shared] observeCreatedTask:task request:request];
        NCInstallTaskHooksForClass([task class]);
    } @catch (__unused NSException *exception) {}
    return task;
}

static NSURLSessionDataTask *ncDataTaskWithURLCompletion(NSURLSession *session,
                                                          SEL selector,
                                                          NSURL *URL,
                                                          void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    __block __weak NSURLSessionDataTask *weakTask = nil;
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NCCaptureCompletion(weakTask, data, response, error, completion);
    };

    IMP raw = [[NCHookRegistry shared] originalIMPForObject:session selector:selector];
    if (!raw) return nil;
    NSURLSessionDataTask *task = ((NCURLCompletionIMP)raw)(session, selector, URL, wrapped);
    weakTask = task;

    @try {
        NSURLRequest *request = URL ? [NSURLRequest requestWithURL:URL] : nil;
        if (request) [[NCCaptureManager shared] observeCreatedTask:task request:request];
        NCInstallTaskHooksForClass([task class]);
    } @catch (__unused NSException *exception) {}
    return task;
}

static void NCInstallCreationHooksForClass(Class cls) {
    if (!cls) return;
    NCHookRegistry *registry = [NCHookRegistry shared];
    [registry hookClass:cls
               selector:@selector(dataTaskWithRequest:completionHandler:)
            replacement:(IMP)ncDataTaskWithRequestCompletion];
    [registry hookClass:cls
               selector:@selector(dataTaskWithURL:completionHandler:)
            replacement:(IMP)ncDataTaskWithURLCompletion];
}

typedef NSURLSession *(*NCSessionConfigIMP)(id, SEL, NSURLSessionConfiguration *);
typedef NSURLSession *(*NCSessionDelegateIMP)(id, SEL, NSURLSessionConfiguration *, id<NSURLSessionDelegate>, NSOperationQueue *);

static NSURLSession *ncSessionWithConfiguration(id cls, SEL selector, NSURLSessionConfiguration *configuration) {
    IMP raw = [[NCHookRegistry shared] originalIMPForObject:cls selector:selector];
    NSURLSession *session = raw ? ((NCSessionConfigIMP)raw)(cls, selector, configuration) : nil;
    if (session) NCInstallCreationHooksForClass([session class]);
    return session;
}

static NSURLSession *ncSessionWithConfigurationDelegate(id cls,
                                                         SEL selector,
                                                         NSURLSessionConfiguration *configuration,
                                                         id<NSURLSessionDelegate> delegate,
                                                         NSOperationQueue *queue) {
    IMP raw = [[NCHookRegistry shared] originalIMPForObject:cls selector:selector];
    NSURLSession *session = raw ? ((NCSessionDelegateIMP)raw)(cls, selector, configuration, delegate, queue) : nil;
    if (session) NCInstallCreationHooksForClass([session class]);
    return session;
}

void NCInstallURLSessionHooks(void) {
    Class sessionClass = NSClassFromString(@"NSURLSession");
    if (!sessionClass) return;

    NCInstallCreationHooksForClass(sessionClass);

    NSURLSession *shared = NSURLSession.sharedSession;
    if (shared) NCInstallCreationHooksForClass([shared class]);

    Class metaClass = object_getClass(sessionClass);
    if (metaClass) {
        NCHookRegistry *registry = [NCHookRegistry shared];
        [registry hookClass:metaClass
                   selector:@selector(sessionWithConfiguration:)
                replacement:(IMP)ncSessionWithConfiguration];
        [registry hookClass:metaClass
                   selector:@selector(sessionWithConfiguration:delegate:delegateQueue:)
                replacement:(IMP)ncSessionWithConfigurationDelegate];
    }

    Class taskClass = NSClassFromString(@"NSURLSessionTask");
    if (taskClass) NCInstallTaskHooksForClass(taskClass);
}
