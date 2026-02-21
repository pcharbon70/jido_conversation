# User Guides

These guides explain how `jido_conversation` works and how to integrate it into
an application.

## Guide map

1. [How It Works](./how_it_works.md)
   - Runtime model, event streams, scheduler/reducer flow, determinism
2. [Getting Started](./getting_started.md)
   - Dependency setup, config, first ingest, first projections
3. [Ingesting Events](./ingesting_events.md)
   - Direct ingest, adapters, causality, dedupe/backpressure notes
4. [Projections and Replay](./projections_and_replay.md)
   - Timeline/LLM context options and replay/query usage
5. [Operations and Host Integration](./operations_and_host_integration.md)
   - Health/telemetry usage and host responsibilities
6. [LLM Backend Configuration](./llm_backend_configuration.md)
   - Backend selection, provider/model routing, and override precedence

## Related docs

- Host integration patterns: `docs/host_integration_patterns.md`
- Host testing handoff checklist: `docs/host_testing_handoff_checklist.md`
- Event stream taxonomy: `docs/architecture/event_stream_taxonomy.md`
