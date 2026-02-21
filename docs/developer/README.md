# Developer Guides

These guides are for contributors who need to understand internal architecture,
design decisions, and extension patterns.

## Guide map

1. [Design Principles](./design_principles.md)
   - Core architecture rules and why they exist
2. [Component Map](./component_map.md)
   - Major modules, responsibilities, and boundaries
3. [Runtime Execution Flow](./runtime_execution_flow.md)
   - End-to-end ingest/scheduling/reducer/effect/projection flow
4. [Extending the Library](./extending_the_library.md)
   - Safe patterns for adding events, adapters, effects, and projections
5. [Testing Strategy](./testing_strategy.md)
   - Test layers, quality gates, and determinism expectations
6. [Unified LLM Client Integration Plan](./llm_client_integration_plan.md)
   - Phased implementation and tracking plan for JidoAI/Harness backend support

## Related references

- ADRs: `docs/adr/`
- Event taxonomy: `docs/architecture/event_stream_taxonomy.md`
- Implementation plan: `notes/research/events_based_architecture_implementation_plan.md`
