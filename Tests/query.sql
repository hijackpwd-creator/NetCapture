SELECT id, source, complete, ipc_loss, cancel_requested, failure_category,
       termination_reason, started_at, ended_at
FROM transactions
ORDER BY started_at DESC
LIMIT 20;

SELECT transaction_id, hop_index, method, url, status_code,
       request_body_total, request_body_stored, request_body_ipc_dropped,
       request_body_truncated, request_body_corrupted,
       response_body_total, response_body_stored, response_body_ipc_dropped,
       response_body_truncated, response_body_corrupted
FROM hops
ORDER BY rowid DESC
LIMIT 20;
