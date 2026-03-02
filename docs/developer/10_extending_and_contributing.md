# 10. Extending and Contributing

This guide is a practical checklist for safe architectural changes.

## Cross-repo extension rule

Keep this library focused on conversation substrate concerns:

- event contract and ingest normalization
- deterministic runtime state transitions
- effect lifecycle signaling
- projection/replay behavior

Do not add mode-specific orchestration, strategy selection, or project tool
declaration logic here. Implement those in `jido_code_server` and integrate via
canonical conversation events.

## Adding a new event type

1. Decide stream family (`conv.in|effect|out|audit`).
2. Update contract payload requirements if needed.
3. Add reducer handling and directives if behavior changes.
4. Add projection mapping if user-facing output changes.
5. Add replay and telemetry assertions in tests.

## Adding a new ingest adapter

- Keep adapter responsibilities limited to payload normalization.
- Call `Ingest.ingest/2`; do not bypass contract/pipeline.
- Prefer explicit, typed helper signatures over generic maps.

## Adding a new effect behavior

- Extend reducer directives, not reducer side effects.
- Implement execution in runtime workers/managers.
- Emit lifecycle events with stable payload keys.
- Include timeout/retry/cancel behavior and matrix coverage.

## Adding or changing an LLM backend

- Implement `LLM.Backend` contract.
- Normalize events/results/errors to internal types.
- Wire backend in config/resolver tests.
- Add parity coverage against existing backends.

## Backward compatibility guidance

- Treat event payload shape changes as high risk.
- Preserve existing projection field semantics when possible.
- Add migration notes when changing host-visible behavior.

## PR checklist

- [ ] Architecture invariants preserved (pure reducer, directive side effects)
- [ ] Contract validation and stream namespace consistency maintained
- [ ] Tests added/updated for changed behavior
- [ ] Pre-commit passes (`test`, `credo`, `dialyzer`)
- [ ] Relevant docs in `docs/user` and `docs/developer` updated
