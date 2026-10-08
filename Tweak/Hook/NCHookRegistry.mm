#import "NCHookRegistry.h"
#import <substrate.h>
#import <objc/runtime.h>
#import <os/lock.h>

@interface NCHookRegistry () {
    os_unfair_lock _lock;
    dispatch_queue_t _hookQueue;
    NSMutableDictionary<NSString *, NSData *> *_originals;
    NSMutableSet<NSString *> *_hooked;
}
@end

@implementation NCHookRegistry

+ (instancetype)shared {
    static NCHookRegistry *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [[NCHookRegistry alloc] init];
    });
    return registry;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _hookQueue = dispatch_queue_create("com.netcapture.hooks", DISPATCH_QUEUE_SERIAL);
        _originals = [NSMutableDictionary dictionary];
        _hooked = [NSMutableSet set];
    }
    return self;
}

static NSString *NCHookKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%s::%s", class_getName(cls), sel_getName(selector)];
}

static BOOL NCClassOwnsSelector(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

- (BOOL)hookClass:(Class)cls selector:(SEL)selector replacement:(IMP)replacement {
    if (!cls || !selector || !replacement) return NO;

    __block BOOL success = NO;
    dispatch_sync(_hookQueue, ^{
        Method resolved = class_getInstanceMethod(cls, selector);
        if (!resolved) return;

        NSString *key = NCHookKey(cls, selector);

        os_unfair_lock_lock(&self->_lock);
        BOOL alreadyHooked = [self->_hooked containsObject:key];
        os_unfair_lock_unlock(&self->_lock);
        if (alreadyHooked) {
            success = YES;
            return;
        }

        if (!NCClassOwnsSelector(cls, selector)) {
            // If an ancestor is already hooked, inherited dispatch reaches that hook.
            // Materializing the already-replaced IMP here would make it the subclass
            // "original" and recurse.
            os_unfair_lock_lock(&self->_lock);
            BOOL hookedAncestor = NO;
            for (Class parent = class_getSuperclass(cls); parent; parent = class_getSuperclass(parent)) {
                if ([self->_hooked containsObject:NCHookKey(parent, selector)]) {
                    hookedAncestor = YES;
                    break;
                }
            }
            os_unfair_lock_unlock(&self->_lock);
            if (hookedAncestor) {
                success = YES;
                return;
            }

            IMP inherited = method_getImplementation(resolved);
            const char *types = method_getTypeEncoding(resolved);
            if (!class_addMethod(cls, selector, inherited, types)) return;
        }

        IMP original = NULL;
        MSHookMessageEx(cls, selector, replacement, &original);
        if (!original) return;

        // Store function-pointer bytes directly. This avoids the stricter Xcode 26
        // diagnostic for converting IMP (a function pointer) to const void *.
        NSData *originalBytes = [NSData dataWithBytes:&original length:sizeof(original)];
        os_unfair_lock_lock(&self->_lock);
        self->_originals[key] = originalBytes;
        [self->_hooked addObject:key];
        os_unfair_lock_unlock(&self->_lock);
        success = YES;
    });

    return success;
}

- (IMP _Nullable)originalIMPForObject:(id)object selector:(SEL)selector {
    if (!object || !selector) return NULL;

    IMP result = NULL;
    os_unfair_lock_lock(&_lock);
    for (Class cls = object_getClass(object); cls && !result; cls = class_getSuperclass(cls)) {
        NSData *bytes = _originals[NCHookKey(cls, selector)];
        if (bytes.length == sizeof(result)) {
            memcpy(&result, bytes.bytes, sizeof(result));
        }
    }
    os_unfair_lock_unlock(&_lock);
    return result;
}

@end
