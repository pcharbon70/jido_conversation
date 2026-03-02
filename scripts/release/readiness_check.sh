#!/usr/bin/env bash
set -euo pipefail

echo "[release-readiness] validating governance docs"
required_docs=(
  "docs/operations/cross_repo_release_governance.md"
  "docs/operations/slo_and_error_budget.md"
  "docs/operations/failure_mode_matrix.md"
)

for file in "${required_docs[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[release-readiness] missing required document: $file" >&2
    exit 1
  fi
done

echo "[release-readiness] running cross-repo contract gate suites"
mix test \
  test/jido_conversation/cross_repo_contract_fixture_test.exs \
  test/jido_conversation/phase7_cutover_integration_test.exs

echo "[release-readiness] running reliability matrix smoke suites"
mix test \
  test/jido_conversation/runtime/llm_reliability_matrix_test.exs \
  test/jido_conversation/runtime/llm_retry_policy_matrix_test.exs

echo "[release-readiness] passed"
