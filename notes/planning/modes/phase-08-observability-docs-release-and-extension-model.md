# Phase 8 - Cross-Repo Integration, Documentation, and Release Readiness

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `jido_conversation` developer and user guides
- `jido_code_server` developer and user guides
- Cross-repo CI pipelines and quality gates
- Release notes and migration documentation

## Relevant Assumptions / Defaults
- Architecture cutover is complete before release finalization.
- CI must validate both repos against shared contract fixtures.
- Documentation must reflect final ownership boundaries unambiguously.

[ ] 8 Phase 8 - Cross-Repo Integration, Documentation, and Release Readiness
  Finalize the new architecture with enforceable cross-repo quality gates, complete documentation, and release governance.

  [ ] 8.1 Section - Cross-Repo CI and Contract Drift Prevention
    Introduce CI gates that fail on behavioral or contract divergence between repos.

    [ ] 8.1.1 Task - Add shared contract compatibility suite
      Enforce canonical event shape and lifecycle parity across both repositories.

      [ ] 8.1.1.1 Subtask - Add shared fixtures for representative user->strategy->tool->strategy traces.
      [ ] 8.1.1.2 Subtask - Validate `conversation.*` to `conv.*` mapping parity in CI.
      [ ] 8.1.1.3 Subtask - Validate projection/replay parity from canonical streams.

    [ ] 8.1.2 Task - Add orchestration determinism and resilience gates
      Validate deterministic outcomes and recovery semantics under controlled fault scenarios.

      [ ] 8.1.2.1 Subtask - Add deterministic ordering checks for repeated orchestration runs.
      [ ] 8.1.2.2 Subtask - Add interruption/cancellation resilience checks under async tool/strategy execution.
      [ ] 8.1.2.3 Subtask - Add restart/recovery parity checks for in-flight and terminal runs.

  [ ] 8.2 Section - Documentation and Developer Experience
    Publish clear architecture guidance and extension instructions for strategy and mode evolution.

    [ ] 8.2.1 Task - Update architecture and flow guides
      Replace legacy mode ownership narratives with final cross-repo architecture.

      [ ] 8.2.1.1 Subtask - Update `jido_conversation` docs to emphasize substrate-only role.
      [ ] 8.2.1.2 Subtask - Update `jido_code_server` docs with mode orchestration and single `ExecutionRunner` gateway internals.
      [ ] 8.2.1.3 Subtask - Add sequence diagrams for mode pipeline, tool loop, and cancellation flows.

    [ ] 8.2.2 Task - Publish extension model for new modes and strategies
      Define how contributors add new mode templates and strategy adapters safely.

      [ ] 8.2.2.1 Subtask - Document mode template contract and required tests.
      [ ] 8.2.2.2 Subtask - Document strategy sub-runner/adapter contract, capability requirements, and `ExecutionRunner` delegation rules.
      [ ] 8.2.2.3 Subtask - Document governance for execution-kind contract evolution and review criteria.

  [ ] 8.3 Section - Release Governance and Operational Readiness
    Establish release criteria and post-release monitoring tied to new ownership model.

    [ ] 8.3.1 Task - Define release checklist and migration notes
      Ensure release artifacts provide clear adoption guidance and operational expectations.

      [ ] 8.3.1.1 Subtask - Publish migration notes from in-library mode runtime to code-server orchestration.
      [ ] 8.3.1.2 Subtask - Publish known limitations and follow-up roadmap items.
      [ ] 8.3.1.3 Subtask - Define rollback/mitigation playbook for critical regressions.

    [ ] 8.3.2 Task - Define telemetry and incident response baselines
      Use standardized signals and metrics to monitor runtime health after release.

      [ ] 8.3.2.1 Subtask - Define core SLO metrics for strategy latency, tool latency, and cancellation success.
      [ ] 8.3.2.2 Subtask - Define alert thresholds and incident triage signals across both repos.
      [ ] 8.3.2.3 Subtask - Define post-release validation window and success criteria.

  [ ] 8.4 Section - Phase 8 Integration Tests
    Validate release readiness through full-stack, cross-repo scenarios and quality gates.

    [ ] 8.4.1 Task - End-to-end release-candidate integration scenarios
      Prove core user journeys and operational controls before tagging release.

      [ ] 8.4.1.1 Subtask - Verify full coding-mode loop with tool calls and successful completion.
      [ ] 8.4.1.2 Subtask - Verify planning and engineering mode pipelines with strategy variation.
      [ ] 8.4.1.3 Subtask - Verify interruption, resume, and cancel behaviors across all modes.

    [ ] 8.4.2 Task - Cross-repo quality gate integration scenarios
      Prove CI and contract drift protections operate as intended.

      [ ] 8.4.2.1 Subtask - Verify shared contract fixture suites run in both repos.
      [ ] 8.4.2.2 Subtask - Verify drift injection fails CI with actionable diagnostics.
      [ ] 8.4.2.3 Subtask - Verify release checklist gate blocks publication until all criteria pass.
