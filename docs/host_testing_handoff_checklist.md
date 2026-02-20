# Host Testing Handoff Checklist

This checklist is for host applications integrating `jido_conversation` after
library roadmap completion.

## Goal

Validate that host wiring, runtime behavior, and operational guardrails are
ready before production rollout.

## Recommended test order

1. Integration environment smoke tests
2. Staging functional and failure-mode tests
3. Staging load/replay checks
4. Canary validation in production-like traffic

## Test matrix

| Area | What to validate | How to validate | Pass criteria |
| --- | --- | --- | --- |
| Boot and health | Runtime boots and dependencies are alive | Call `JidoConversation.health/0` from host health endpoint | `status == :ok` and all `*_alive?` fields are `true` |
| Ingress contract gate | Invalid events are rejected and valid events accepted | Send one valid and one invalid ingress signal via `JidoConversation.ingest/2` | Valid ingest returns `{:ok, ...}`; invalid returns `{:error, {:contract_invalid, ...}}` |
| Idempotency | Duplicate event IDs are not double-applied | Ingest same `{subject, id}` twice | Second ingest reports duplicate semantics and no duplicate state effects |
| Causality and scheduling | Cause event is applied before dependent event | Ingest child with `cause_id`, then root | Runtime snapshot/history reflects causal ordering |
| Projection correctness | Timeline and LLM context match expected conversation | Compare host rendering with `JidoConversation.timeline/2` and `JidoConversation.llm_context/2` | Host-visible output matches projection output |
| Control responsiveness | Abort/control events preempt low-value traffic | Generate burst + send abort | Abort latency meets host SLO target |
| Backpressure behavior | Saturation is handled without silent data loss | Run burst traffic and observe queue pressure signals | Host sees retries/backpressure and converges without stuck queues |
| Replay parity | Replay produces expected state/projection parity | Sample conversation IDs, rebuild from replay | Parity checks pass for selected samples |
| Telemetry wiring | Host metrics pipeline receives runtime telemetry | Poll `JidoConversation.telemetry_snapshot/0` and/or subscribe to telemetry events | Dashboard counters/histograms update correctly |
| Failure operations | Runbook steps are executable by on-call | Simulate one failure from `docs/operations/failure_mode_matrix.md` | Team can detect, triage, and recover within expected window |

## Evidence to collect for signoff

- Health snapshots from each environment
- Sample projection outputs for known conversations
- Replay parity results for sampled conversations
- Queue depth/apply latency/abort latency charts
- Failure simulation notes and remediation timing
- Final go/no-go decision with owner approval

## Exit criteria for host go-live

- All matrix rows pass in staging
- Canary run completes without unresolved incidents
- Host SLO/error budget policy is active and monitored
