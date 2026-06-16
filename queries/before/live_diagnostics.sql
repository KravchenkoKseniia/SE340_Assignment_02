SELECT
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

SELECT
    blocked.pid AS blocked_pid,
    blocked.usename AS blocked_user,
    blocked.query AS blocked_query,
    blocking.pid AS blocking_pid,
    blocking.usename AS blocking_user,
    blocking.query AS blocking_query,
    blocked.wait_event_type,
    blocked.wait_event
FROM pg_stat_activity blocked
         JOIN pg_stat_activity blocking
              ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
ORDER BY blocked.pid;

SELECT
    pid,
    usename,
    state,
    xact_start,
    now() - xact_start AS transaction_duration,
    query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start;

SELECT
    pid,
    usename,
    state,
    wait_event_type,
    wait_event,
    query_start,
    now() - query_start AS running_for,
    query
FROM pg_stat_activity
WHERE wait_event_type = 'Lock';

SELECT l.pid, l.granted, l.mode, l.locktype, COALESCE(c.relname, l.locktype) AS object, left(regexp_replace(a.query, '\s+', ' ', 'g'), 55) AS query
FROM pg_locks l
LEFT JOIN pg_class c ON c.oid = l.relation
LEFT JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.pid <> pg_backend_pid()
ORDER BY l.granted, object, l.pid;
