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

**Status:** done

## Checklist

- [x] Every cluster asserted nested inside a function body: terminator (A), control-flow
      block (B), declaration / expression block (C).
- [x] Nested coverage for the Advance outcome (already-complete statement inside a
      block) and the Decline outcome (unreadable structure inside a block) — both must
      leave the enclosing construct untouched.
- [x] At least one case nested two levels deep, and one inside a class method body.
- [x] A multi-line statement nested inside a block completes as one whole.
- [x] Undo: a nested completion still reverts in a single `u`, with the enclosing
      construct byte-identical to before the fire.
- [x] The nested cases are table-driven rather than copy-pasted, so a third shape
      (top-level / nested / deeply nested) stays cheap to add.

## Comments

- Scope is the integration suite (Seam B). `tests/test_analyze.lua` operates on raw
  strings and is unaffected — `analyze` never sees nesting, which is exactly why the
  bug was invisible to 37 passing analyze tests.
- The real-editor harness at `.scratch/v1-bugs/loop.sh` is the manual counterpart. It
  drives the reporter's actual config and cannot run in CI, so it is a verification
  tool, not a gate; this ticket is what makes the gate honest.
- Built as a **shape × case matrix**: four shapes (top level, a function body, two blocks
  deep, a class method body) × ten cases (clusters A/B/C, a wrapped statement, a wrapped
  block head, a trailing comment, both Advance flavours, Decline) = 40 generated cases. A
  case is written once, relative to its own statement — `lines`/`want` carry no leading
  indent and the positions are relative to the statement's first line — and the shape
  prefixes its `indent` and wraps the enclosing lines. A fifth shape is one table entry.
- Every case fires from insert mode and then asserts the whole buffer reverts on a single
  `u`, so "the enclosing construct is byte-identical" is checked on every row rather than
  in one dedicated undo test. The exception is Decline: it never edits, so there is no
  plugin change to revert and `u` would undo the fixture's own `nvim_buf_set_lines`
  instead. The runner skips the undo step when the fire changed nothing.
- Honesty check: with `locate.lua` reverted to the pre-issue-01 rise-to-root rule, 28 of
  the 31 nested cases go red and all 10 top-level cases stay green — the blind spot was
  real and is now covered. The 3 that stay green are the nested Decline cases, and
  correctly so: Decline touches no buffer, so mis-anchoring can't change its outcome.
- Both *indented* fixtures the ticket names are gone. `'  const y = bar(1'` (fresh-line
  indent) is subsumed by any nested cluster-A row; `{ '  if (', '    cond' }` became a
  matrix case of its own — a wrapped **block** head, which is a different behaviour from
  the wrapped terminator and had no other home.
- Kept top-level-only, deliberately: the mode a fire starts in, buffer indent options,
  `setup()` config and the filetype guard. Nesting is orthogonal to each, and running them
  through the matrix would quadruple their cost for no new information. Two statement
  behaviours also stay there — `reuses an already-typed brace` and the `} while` tail —
  because nesting them lands on the issue-04 residual (an unclosed `{`, or a tail after a
  block, swallows the enclosing brace) rather than on what they assert.
- One nested shape sits outside the matrix: a *bare* empty line inside a block. The matrix
  prefixes each shape's indent, so its blank-line rows are always indent-only. The bare
  line gets its own test — it is the shape that used to splice `} {` after the enclosing
  function's closing brace.
- Verification: 107 cases green (53 in this file, up from 22), `luacheck` and
  `stylua --check` clean.
- `/code-review` (both axes) drove the last round: the wrapped block head and the trailing
  comment moved into the matrix (they were the two statement behaviours still asserted
  only top level), `advances on an empty line` became `on a blank line` because nesting
  makes it indent-only, the cluster comments regained their issue numbers, and the
  `vim.notify` capture became one `capture_hints()` helper. Declined: bundling
  `(shape, case)` into a fixture type and splitting a separate Decline runner — both add
  indirection to a 6-line helper — and asserting `mode() == 'i'` per row, which proves
  nothing when every row fires from insert mode already.
