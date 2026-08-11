# 02 — Nested-statement coverage across the integration suite

**What to build:** Close the blind spot that let issue 01 ship green. Every fixture in
`tests/test_integration.lua` is a top-level statement, so the suite only ever exercised
the one shape where the buggy anchoring rule happened to be correct. Sweep the existing
cases so each behaviour is asserted **nested inside a real block** as well as at top
level.

Some current fixtures are indented (`'  const y = bar(1'`, `{ '  if (', '    cond' }`)
and read like nesting, but with no enclosing `{ }` they are still top-level statements —
this is precisely the false confidence to remove.

**Blocked by:** 01.

**Status:** ready-for-agent

## Checklist

- [ ] Every cluster asserted nested inside a function body: terminator (A), control-flow
      block (B), declaration / expression block (C).
- [ ] Nested coverage for the Advance outcome (already-complete statement inside a
      block) and the Decline outcome (unreadable structure inside a block) — both must
      leave the enclosing construct untouched.
- [ ] At least one case nested two levels deep, and one inside a class method body.
- [ ] A multi-line statement nested inside a block completes as one whole.
- [ ] Undo: a nested completion still reverts in a single `u`, with the enclosing
      construct byte-identical to before the fire.
- [ ] The nested cases are table-driven rather than copy-pasted, so a third shape
      (top-level / nested / deeply nested) stays cheap to add.

## Comments

- Scope is the integration suite (Seam B). `tests/test_analyze.lua` operates on raw
  strings and is unaffected — `analyze` never sees nesting, which is exactly why the
  bug was invisible to 37 passing analyze tests.
- The real-editor harness at `.scratch/v1-bugs/loop.sh` is the manual counterpart. It
  drives the reporter's actual config and cannot run in CI, so it is a verification
  tool, not a gate; this ticket is what makes the gate honest.
