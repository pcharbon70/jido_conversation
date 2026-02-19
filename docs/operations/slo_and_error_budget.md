# SLO and error budget baseline

This baseline defines phase-0 targets for runtime behavior. Values can be adjusted
after phase-8 load testing, but changes must be explicit and versioned.

## Service level objectives

### Control-plane responsiveness

- Abort acknowledgement latency:
  - SLO: p95 <= 300 ms, p99 <= 600 ms
  - Measurement: `abort_requested` to `abort_applied`

### User response initiation

- Time to first assistant output token/chunk:
  - SLO: p95 <= 2.5 s, p99 <= 5.0 s
  - Measurement: `conv.in.message.received` to first `conv.out.assistant.delta`

### Event application latency

- Reducer apply latency per event:
  - SLO: p95 <= 40 ms, p99 <= 100 ms
  - Measurement: scheduler dequeue to `conv.applied.*` emission

### Replay correctness

- Replay state parity:
  - SLO: 100% parity on sampled conversations
  - Measurement: replayed state hash equals recorded live state hash

### Delivery reliability

- Event apply success ratio (excluding explicit rejects):
  - SLO: >= 99.95% over rolling 30 days

## Error budget policy

For monthly windows:

- Allowed failed applies (non-rejected): 0.05%
- Allowed control-plane SLO misses: 1% of abort requests
- Allowed response-initiation SLO misses: 2% of conversations

If any budget is exhausted:

- Freeze feature work touching runtime scheduling/effects.
- Prioritize reliability and performance remediation.
- Require post-incident review before resuming roadmap work.

## Required telemetry

- Queue depth by partition
- Reducer apply latency histogram
- Abort requested/applied timestamps
- First-output latency histogram
- Retry counts and DLQ counts
- Replay parity check results
