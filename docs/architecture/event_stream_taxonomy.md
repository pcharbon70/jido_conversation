# Event stream taxonomy and naming conventions

This document defines the stream namespaces and event naming rules for the
conversation runtime.

## Stream namespaces

- `conv.in.*`: normalized ingress from external or internal producers
- `conv.applied.*`: reducer application confirmations
- `conv.effect.*`: effect lifecycle and runtime events
- `conv.out.*`: user-facing output stream events
- `conv.audit.*`: compliance, audit, and forensic projection events

## Naming format

Use dot-separated type names:

`conv.<stream>.<domain>.<action>[.<state>]`

Examples:

- `conv.in.message.received`
- `conv.in.control.abort_requested`
- `conv.effect.tool.execution.started`
- `conv.effect.tool.execution.completed`
- `conv.applied.message.received`
- `conv.out.assistant.delta`
- `conv.out.assistant.completed`
- `conv.audit.policy.decision_recorded`

## Envelope requirements

All events must include:

- `type`
- `source`
- `id`
- `subject` (canonical conversation id)

Recommended fields:

- `cause_id`
- producer metadata relevant to observability and debugging

## Payload conventions

- Payloads should be domain-focused and avoid repeating envelope metadata.
- Include stable ids for referenced artifacts (tool call id, llm run id, message id).
- Lifecycle events should use consistent state transitions:
  - `started`
  - `progress`
  - `completed`
  - `failed`
  - `canceled`

## Routing conventions

- Subscriptions may use wildcard patterns such as `conv.out.**` or `conv.audit.**`.
- Handlers that process broad patterns should be side-effect safe and idempotent.
- Priority behavior is scheduler-controlled and is not encoded in type strings.
