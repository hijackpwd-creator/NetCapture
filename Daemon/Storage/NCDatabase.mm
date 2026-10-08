#import "NCDatabase.h"
#import "../Model/NCServerModels.h"
#import "../../Shared/NCRuntimePaths.h"
#import <sqlite3.h>

static const int kNCDatabaseSchemaVersion = 2;

@interface NCDatabase () {
    sqlite3 *_db;
    dispatch_queue_t _queue;
    BOOL _started;
}
@end

@implementation NCDatabase

+ (instancetype)shared {
    static NCDatabase *database;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        database = [[NCDatabase alloc] init];
    });
    return database;
}

- (instancetype)init {
    self = [super init];
    if (self) _queue = dispatch_queue_create("com.netcapture.database", DISPATCH_QUEUE_SERIAL);
    return self;
}

static void NCBindText(sqlite3_stmt *statement, int index, NSString *value) {
    if (value) sqlite3_bind_text(statement, index, value.UTF8String, -1, SQLITE_TRANSIENT);
    else sqlite3_bind_null(statement, index);
}

static NSString *NCJSONText(id object) {
    if (!object || ![NSJSONSerialization isValidJSONObject:object]) return nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

- (BOOL)execLocked:(const char *)sql {
    char *message = NULL;
    int rc = sqlite3_exec(_db, sql, NULL, NULL, &message);
    if (rc != SQLITE_OK) {
        if (message) sqlite3_free(message);
        return NO;
    }
    return YES;
}

- (BOOL)columnExistsLocked:(NSString *)column table:(NSString *)table {
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(%@)", table];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_db, sql.UTF8String, -1, &statement, NULL) != SQLITE_OK) return NO;
    BOOL found = NO;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *name = sqlite3_column_text(statement, 1);
        if (name && [column isEqualToString:[NSString stringWithUTF8String:(const char *)name]]) {
            found = YES;
            break;
        }
    }
    sqlite3_finalize(statement);
    return found;
}

- (BOOL)ensureColumnLocked:(NSString *)column definition:(NSString *)definition table:(NSString *)table {
    if ([self columnExistsLocked:column table:table]) return YES;
    NSString *sql = [NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@", table, column, definition];
    return [self execLocked:sql.UTF8String];
}

- (BOOL)createOrMigrateSchemaLocked {
    const char *baseSchema =
        "CREATE TABLE IF NOT EXISTS transactions("
        "id TEXT PRIMARY KEY,storage_id TEXT NOT NULL,session_id TEXT,connection_id TEXT,"
        "peer_uid INTEGER NOT NULL,peer_gid INTEGER NOT NULL,source INTEGER NOT NULL,task_id INTEGER,"
        "started_at REAL NOT NULL,ended_at REAL,complete INTEGER DEFAULT 0,ipc_loss INTEGER DEFAULT 0,"
        "cancel_requested INTEGER DEFAULT 0,failure_category INTEGER DEFAULT 0,error_domain TEXT,"
        "error_code INTEGER DEFAULT 0,error_description TEXT,termination_reason TEXT);"
        "CREATE TABLE IF NOT EXISTS hops("
        "id TEXT PRIMARY KEY,transaction_id TEXT NOT NULL,hop_index INTEGER NOT NULL,started_at REAL,ended_at REAL,"
        "method TEXT,url TEXT,status_code INTEGER DEFAULT 0,request_headers TEXT,response_headers TEXT,"
        "request_body_path TEXT,request_body_total INTEGER DEFAULT 0,request_body_stored INTEGER DEFAULT 0,"
        "request_body_ipc_dropped INTEGER DEFAULT 0,request_body_truncated INTEGER DEFAULT 0,request_body_corrupted INTEGER DEFAULT 0,"
        "response_body_path TEXT,response_body_total INTEGER DEFAULT 0,response_body_stored INTEGER DEFAULT 0,"
        "response_body_ipc_dropped INTEGER DEFAULT 0,response_body_truncated INTEGER DEFAULT 0,response_body_corrupted INTEGER DEFAULT 0,"
        "FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE);"
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_hops_tx_idx ON hops(transaction_id,hop_index);"
        "CREATE INDEX IF NOT EXISTS idx_transactions_started ON transactions(started_at DESC);"
        "CREATE INDEX IF NOT EXISTS idx_hops_status ON hops(status_code);";

    if (![self execLocked:"BEGIN IMMEDIATE"]) return NO;
    BOOL ok = [self execLocked:baseSchema];

    // Upgrade databases produced by the earlier Phase 2.1 schema.
    if (ok) ok = [self ensureColumnLocked:@"request_body_path" definition:@"TEXT" table:@"hops"];
    if (ok) ok = [self ensureColumnLocked:@"request_body_total" definition:@"INTEGER DEFAULT 0" table:@"hops"];
    if (ok) ok = [self ensureColumnLocked:@"request_body_stored" definition:@"INTEGER DEFAULT 0" table:@"hops"];
    if (ok) ok = [self ensureColumnLocked:@"request_body_ipc_dropped" definition:@"INTEGER DEFAULT 0" table:@"hops"];
    if (ok) ok = [self ensureColumnLocked:@"request_body_truncated" definition:@"INTEGER DEFAULT 0" table:@"hops"];
    if (ok) ok = [self ensureColumnLocked:@"request_body_corrupted" definition:@"INTEGER DEFAULT 0" table:@"hops"];

    if (ok) {
        NSString *versionSQL = [NSString stringWithFormat:@"PRAGMA user_version=%d", kNCDatabaseSchemaVersion];
        ok = [self execLocked:versionSQL.UTF8String];
    }

    if (ok) {
        if ([self execLocked:"COMMIT"]) return YES;
    }
    [self execLocked:"ROLLBACK"];
    return NO;
}

- (void)closeDatabaseLocked {
    if (_db) {
        sqlite3_close(_db);
        _db = NULL;
    }
    _started = NO;
}

- (BOOL)start {
    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        if (self->_started) {
            success = YES;
            return;
        }

        NSString *path = [NCRuntimePaths databasePath];
        int rc = sqlite3_open_v2(path.fileSystemRepresentation,
                                 &self->_db,
                                 SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                                 NULL);
        if (rc != SQLITE_OK) {
            [self closeDatabaseLocked];
            return;
        }

        sqlite3_extended_result_codes(self->_db, 1);
        sqlite3_busy_timeout(self->_db, 2000);

        BOOL configured = [self execLocked:"PRAGMA journal_mode=WAL"] &&
                          [self execLocked:"PRAGMA synchronous=NORMAL"] &&
                          [self execLocked:"PRAGMA foreign_keys=ON"] &&
                          [self execLocked:"PRAGMA temp_store=MEMORY"];
        if (!configured || ![self createOrMigrateSchemaLocked]) {
            [self closeDatabaseLocked];
            return;
        }

        self->_started = YES;
        success = YES;
    });
    return success;
}

- (BOOL)insertTransactionRowLocked:(NCServerTransaction *)transaction {
    static const char *sql =
        "INSERT INTO transactions("
        "id,storage_id,session_id,connection_id,peer_uid,peer_gid,source,task_id,started_at,ended_at,"
        "complete,ipc_loss,cancel_requested,failure_category,error_domain,error_code,error_description,termination_reason"
        ") VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";

    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &statement, NULL) != SQLITE_OK) return NO;

    int i = 1;
    NCBindText(statement, i++, transaction.identifier);
    NCBindText(statement, i++, transaction.storageIdentifier);
    NCBindText(statement, i++, transaction.sessionIdentifier);
    NCBindText(statement, i++, transaction.connectionIdentifier);
    sqlite3_bind_int64(statement, i++, transaction.peerUID);
    sqlite3_bind_int64(statement, i++, transaction.peerGID);
    sqlite3_bind_int64(statement, i++, transaction.source);
    sqlite3_bind_int64(statement, i++, transaction.taskIdentifier);
    sqlite3_bind_double(statement, i++, transaction.startedAt);
    if (transaction.endedAt > 0) sqlite3_bind_double(statement, i++, transaction.endedAt);
    else sqlite3_bind_null(statement, i++);
    sqlite3_bind_int(statement, i++, transaction.complete ? 1 : 0);
    sqlite3_bind_int(statement, i++, transaction.ipcLoss ? 1 : 0);
    sqlite3_bind_int(statement, i++, transaction.cancelRequested ? 1 : 0);
    sqlite3_bind_int64(statement, i++, transaction.failureCategory);
    NCBindText(statement, i++, transaction.errorDomain);
    sqlite3_bind_int64(statement, i++, transaction.errorCode);
    NCBindText(statement, i++, transaction.errorDescription);
    NCBindText(statement, i++, transaction.terminationReason);

    BOOL ok = sqlite3_step(statement) == SQLITE_DONE;
    sqlite3_finalize(statement);
    return ok;
}

- (BOOL)insertHopLocked:(NCServerHop *)hop transaction:(NCServerTransaction *)transaction {
    static const char *sql =
        "INSERT INTO hops("
        "id,transaction_id,hop_index,started_at,ended_at,method,url,status_code,request_headers,response_headers,"
        "request_body_path,request_body_total,request_body_stored,request_body_ipc_dropped,request_body_truncated,request_body_corrupted,"
        "response_body_path,response_body_total,response_body_stored,response_body_ipc_dropped,response_body_truncated,response_body_corrupted"
        ") VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";

    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &statement, NULL) != SQLITE_OK) return NO;

    NCServerBodyState *request = hop.requestBody;
    NCServerBodyState *response = hop.responseBody;
    int i = 1;
    NCBindText(statement, i++, hop.identifier);
    NCBindText(statement, i++, transaction.identifier);
    sqlite3_bind_int64(statement, i++, hop.index);
    sqlite3_bind_double(statement, i++, hop.startedAt);
    if (hop.endedAt > 0) sqlite3_bind_double(statement, i++, hop.endedAt);
    else sqlite3_bind_null(statement, i++);
    NCBindText(statement, i++, hop.method);
    NCBindText(statement, i++, hop.URLString);
    sqlite3_bind_int64(statement, i++, hop.statusCode);
    NCBindText(statement, i++, NCJSONText(hop.requestHeaders ?: @[]));
    NCBindText(statement, i++, NCJSONText(hop.responseHeaders ?: @[]));

    NCBindText(statement, i++, request.path);
    sqlite3_bind_int64(statement, i++, MAX(request.clientObservedBytes, request.receivedBytes));
    sqlite3_bind_int64(statement, i++, request.storedBytes);
    sqlite3_bind_int64(statement, i++, request.ipcDroppedBytes);
    sqlite3_bind_int(statement, i++, request.truncated ? 1 : 0);
    sqlite3_bind_int(statement, i++, request.corrupted ? 1 : 0);

    NCBindText(statement, i++, response.path);
    sqlite3_bind_int64(statement, i++, MAX(response.clientObservedBytes, response.receivedBytes));
    sqlite3_bind_int64(statement, i++, response.storedBytes);
    sqlite3_bind_int64(statement, i++, response.ipcDroppedBytes);
    sqlite3_bind_int(statement, i++, response.truncated ? 1 : 0);
    sqlite3_bind_int(statement, i++, response.corrupted ? 1 : 0);

    BOOL ok = sqlite3_step(statement) == SQLITE_DONE;
    sqlite3_finalize(statement);
    return ok;
}

- (void)insertTransaction:(NCServerTransaction *)transaction completion:(void (^)(BOOL))completion {
    if (!transaction) {
        if (completion) completion(NO);
        return;
    }

    dispatch_async(_queue, ^{
        BOOL ok = NO;
        if (self->_started && [self execLocked:"BEGIN IMMEDIATE"]) {
            ok = [self insertTransactionRowLocked:transaction];
            if (ok) {
                for (NSString *hopID in transaction.hopOrder) {
                    NCServerHop *hop = transaction.hops[hopID];
                    if (!hop || ![self insertHopLocked:hop transaction:transaction]) {
                        ok = NO;
                        break;
                    }
                }
            }

            if (ok) ok = [self execLocked:"COMMIT"];
            if (!ok) [self execLocked:"ROLLBACK"];
        }

        if (completion) completion(ok);
    });
}

@end
