# Failure mode matrix

This matrix captures baseline failure handling decisions for the event-based
conversation architecture.

| Failure mode | Detection signal | Automatic response | Operator action |
| --- | --- | --- | --- |
| Invalid envelope at ingress | Validation reject metric and log | Reject event, emit audit event, do not publish | Inspect producer payload contract and fix adapter |
| Journal append failure | Journal write error telemetry | Retry with bounded backoff; if exhausted, fail ingress and do not ack | Validate journal adapter health and storage availability |
| Bus publish failure after journal append | Publish error telemetry | Retry publish; if exhausted, mark as stranded journal event for re-drive | Run re-drive job for stranded events |
| Reducer apply failure | `conv.applied.*` missing + error telemetry | Retry event apply; if exhausted route to DLQ | Inspect reducer bug or payload drift, then re-drive |
| Effect worker timeout | Effect timeout telemetry | Emit `conv.effect.*.failed`, apply retry policy | Tune timeout/retry, inspect downstream dependency |
| Abort does not complete in SLO | Abort latency SLO breach alert | Escalate event priority and force worker termination fallback | Investigate scheduler starvation or cancel path regression |
| Partition overload | Queue depth and lag alerts | Apply backpressure limits and degrade low-priority stream handling | Increase partitions/capacity and tune scheduling fairness |
| Duplicate delivery (at-least-once) | Duplicate id metric/idempotency check | Drop duplicate or no-op apply based on idempotency keys | Verify dedupe logic and checkpoint behavior |
| DLQ growth spike | DLQ size and rate alerts | Pause non-critical ingest and prioritize re-drive diagnostics | Triage root causes and execute controlled re-drive |
| Replay parity mismatch | Replay parity check failure | Block rollout gate, flag conversation for forensic trace | Investigate scheduler determinism/state mutation bug |

## Notes

- Every automatic response must emit observable telemetry and an audit event where relevant.
- Re-drive tooling is mandatory before production scale rollout.
- Failure-mode simulations must be part of staging validation in phase 8.
