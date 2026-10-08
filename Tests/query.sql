SELECT id,source,complete,failure_category,termination_reason,started_at,ended_at FROM transactions ORDER BY started_at DESC LIMIT 20;
SELECT transaction_id,hop_index,method,url,status_code,response_body_total,response_body_stored,response_body_truncated,response_body_corrupted FROM hops ORDER BY rowid DESC LIMIT 20;
