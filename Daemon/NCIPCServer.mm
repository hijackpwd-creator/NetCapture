#import "NCIPCServer.h"
#import "NCClientConnection.h"
#import "../Shared/NCRuntimePaths.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

static const NSUInteger kNCMaxClients = 128;

@interface NCIPCServer () {
    int _listenFD;
    dispatch_queue_t _queue;
    dispatch_source_t _acceptSource;
    NSMutableDictionary<NSString *, NCClientConnection *> *_clients;
    BOOL _running;
}
@end

@implementation NCIPCServer

- (instancetype)init {
    self = [super init];
    if (self) {
        _listenFD = -1;
        _queue = dispatch_queue_create("com.netcapture.server", DISPATCH_QUEUE_SERIAL);
        _clients = [NSMutableDictionary dictionary];
    }
    return self;
}

static BOOL NCConfigureSocketFD(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) return NO;

    int fdFlags = fcntl(fd, F_GETFD, 0);
    if (fdFlags >= 0) (void)fcntl(fd, F_SETFD, fdFlags | FD_CLOEXEC);

#ifdef SO_NOSIGPIPE
    int one = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    return YES;
}

- (BOOL)start {
    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        if (self->_running) {
            success = YES;
            return;
        }

        NSString *path = [NCRuntimePaths socketPath];
        const char *fsPath = path.fileSystemRepresentation;
        if (!fsPath || strlen(fsPath) >= sizeof(((struct sockaddr_un *)0)->sun_path)) return;

        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0 || !NCConfigureSocketFD(fd)) {
            if (fd >= 0) close(fd);
            return;
        }

        // The runtime directory is daemon-managed, so only this exact managed socket is unlinked.
        unlink(fsPath);

        struct sockaddr_un address = {};
        address.sun_family = AF_UNIX;
        strlcpy(address.sun_path, fsPath, sizeof(address.sun_path));

        if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 32) != 0) {
            close(fd);
            unlink(fsPath);
            return;
        }

        // Daemon and injected applications normally run as mobile; owner-only access is sufficient.
        (void)chmod(fsPath, 0600);

        self->_listenFD = fd;
        self->_acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self->_queue);
        if (!self->_acceptSource) {
            close(fd);
            self->_listenFD = -1;
            unlink(fsPath);
            return;
        }

        __weak NCIPCServer *weakSelf = self;
        dispatch_source_set_event_handler(self->_acceptSource, ^{
            [weakSelf acceptLoopLocked];
        });
        dispatch_resume(self->_acceptSource);
        self->_running = YES;
        success = YES;
    });
    return success;
}

- (void)acceptLoopLocked {
    for (;;) {
        int clientFD = accept(_listenFD, NULL, NULL);
        if (clientFD >= 0) {
            if (_clients.count >= kNCMaxClients || !NCConfigureSocketFD(clientFD)) {
                close(clientFD);
                continue;
            }

            uid_t uid = (uid_t)-1;
            gid_t gid = (gid_t)-1;
            if (getpeereid(clientFD, &uid, &gid) != 0) {
                close(clientFD);
                continue;
            }

            // Fail closed for unexpected Unix users. Root can bypass this by definition,
            // but ordinary unrelated service users cannot inject capture frames.
            if (uid != getuid()) {
                close(clientFD);
                continue;
            }

            NCClientConnection *connection = [[NCClientConnection alloc] initWithFD:clientFD];
            connection.peerUID = uid;
            connection.peerGID = gid;

            __weak NCIPCServer *weakSelf = self;
            connection.closeHandler = ^(NCClientConnection *closed) {
                __strong NCIPCServer *strongSelf = weakSelf;
                if (!strongSelf) return;
                dispatch_async(strongSelf->_queue, ^{
                    if (strongSelf->_clients[closed.identifier] == closed) {
                        [strongSelf->_clients removeObjectForKey:closed.identifier];
                    }
                });
            };

            _clients[connection.identifier] = connection;
            [connection start];
            continue;
        }

        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) break;
        break;
    }
}

- (void)stop {
    dispatch_async(_queue, ^{
        if (!self->_running) return;
        self->_running = NO;

        if (self->_acceptSource) {
            dispatch_source_cancel(self->_acceptSource);
            self->_acceptSource = nil;
        }
        if (self->_listenFD >= 0) {
            close(self->_listenFD);
            self->_listenFD = -1;
        }

        NSArray<NCClientConnection *> *connections = self->_clients.allValues;
        [self->_clients removeAllObjects];
        for (NCClientConnection *connection in connections) [connection close];

        unlink([NCRuntimePaths socketPath].fileSystemRepresentation);
    });
}

@end
