# Design Standards

Language-agnostic architectural baseline.

- Separate business decisions, application coordination, and delivery details.
  Keep domain rules independent of framework, transport, and persistence choices.
- Use explicit boundaries and adapters where external details need isolation;
  dependencies should point toward the rules they serve.
- Make contracts, ownership, and meaningful state transitions explicit.
- Prefer composition and cohesive units. Introduce layers or interfaces for real
  boundaries, not to reproduce an architectural diagram.
- Keep correctness-critical decisions deterministic; treat external engines,
  including model-backed services, as replaceable infrastructure.
