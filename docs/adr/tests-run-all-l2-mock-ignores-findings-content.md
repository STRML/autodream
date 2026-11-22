# tests-run-all: findings-plumbing tests stop at the findings JSON because the L2 mock ignores its content

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_facet_fields_plumbed`)

## Context

`tests/mock-claude.sh` plays L2 without reading the findings it is given. A report landing therefore says nothing about whether L2 understood the facet fields.

## Decision

`test_facet_fields_plumbed` asserts on the findings JSON that L2 reads (outcome, satisfaction signals, `underlying_goal`, `instructions_given`) and on the report existing. It makes no claim about what L2 did with them. Behavioral quality is judged on real runs.

## Consequences

Do not add assertions about report content here; the mock cannot satisfy them. Read "L2 run completed" as plumbing only.
