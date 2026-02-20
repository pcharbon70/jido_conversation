# Contract Evolution Test Matrix

## Scope completed

- Added cross-namespace compatibility coverage for the phase-2 contract boundary.
- Added explicit assertions for v1 payload key stability per stream namespace.
- Added negative coverage for unsupported contract majors across all stream namespaces.

## Validation coverage

- Added `test/jido_conversation/signal/contract_evolution_test.exs`:
  - validates canonical v1 payload acceptance for:
    - `conv.in.*`
    - `conv.applied.*`
    - `conv.effect.*`
    - `conv.out.*`
    - `conv.audit.*`
  - validates string-key payload compatibility for all namespaces
  - validates missing-key rejection per namespace
  - validates unsupported major rejection (`contract_major: 2`) per namespace
  - validates precedence behavior when both top-level and extension contract major are set

## Quality gates

- `mix format --check-formatted`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`
