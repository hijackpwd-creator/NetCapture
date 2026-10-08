#import "NCHookRegistry.h"
#import <substrate.h>
#import <objc/runtime.h>
#import <os/lock.h>

@interface NCHookRegistry () {
    os_unfair_lock _lock;
    NSMutableDictionary<NSString *, NSValue *> *_originals;
    NSMutableSet<NSString *> *_hooked;
}
@end

@implementation NCHookRegistry

+ (instancetype)shared {
    static NCHookRegistry *x;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ x = [NCHookRegistry new]; });
    return x;
}

- (instancetype)init {
    if ((self = [super init])) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _originals = [NSMutableDictionary dictionary];
        _hooked = [NSMutableSet set];
    }
    return self;
}

static NSString *NCHookKey(Class c, SEL s) {
    return [NSString stringWithFormat:@"%s::%s", class_getName(c), sel_getName(s)];
}

static BOOL NCClassOwnsSelector(Class cls, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) { found = YES; break; }
    }
    free(methods);
    return found;
}

- (BOOL)hookClass:(Class)c selector:(SEL)s replacement:(IMP)r {
    if (!c || !s || !r) return NO;
    Method resolved = class_getInstanceMethod(c, s);
    if (!resolved) return NO;

    NSString *key = NCHookKey(c, s);
    os_unfair_lock_lock(&_lock);
    if ([_hooked containsObject:key]) {
        os_unfair_lock_unlock(&_lock);
        return YES;
    }
    if (!NCClassOwnsSelector(c, s)) {
        /* If an ancestor is already hooked, normal ObjC dispatch already reaches it.
         * Do not materialize that replacement into the subclass or it becomes the
         * subclass "original" and recurses. */
        for (Class parent = class_getSuperclass(c); parent; parent = class_getSuperclass(parent)) {
            if ([_hooked containsObject:NCHookKey(parent, s)]) {
                os_unfair_lock_unlock(&_lock);
                return YES;
            }
        }
    }
    os_unfair_lock_unlock(&_lock);

    if (!NCClassOwnsSelector(c, s)) {
        IMP inherited = method_getImplementation(resolved);
        const char *types = method_getTypeEncoding(resolved);
        if (!class_addMethod(c, s, inherited, types)) return NO;
    }

    IMP old = NULL;
    MSHookMessageEx(c, s, r, &old);
    if (!old) return NO;

    os_unfair_lock_lock(&_lock);
    _originals[key] = [NSValue valueWithPointer:old];
    [_hooked addObject:key];
    os_unfair_lock_unlock(&_lock);
    return YES;
}

- (IMP)originalIMPForObject:(id)o selector:(SEL)s {
    if (!o || !s) return NULL;
    os_unfair_lock_lock(&_lock);
    IMP out = NULL;
    for (Class c = object_getClass(o); c && !out; c = class_getSuperclass(c)) {
        NSValue *v = _originals[NCHookKey(c, s)];
        if (v) out = (IMP)v.pointerValue;
    }
    os_unfair_lock_unlock(&_lock);
    return out;
}

@end
