# 01 — `locate` anchors to the enclosing block, not the statement

**What to build:** Correct the node the `locate` walk stops at, so a statement nested
inside a block anchors to the statement itself rather than to the whole enclosing
construct. Today `lua/fullstop/locate.lua:57-60` rises while `node:parent() ~= root`,
which for nested code climbs past `statement_block` up to `function_declaration` /
`class_declaration`. The region handed to `analyze` is then the entire construct, and
`apply` splices closers at its last line — mangling the buffer for essentially all
real code.

The rise must stop at the **outermost node whose parent is a statement container**
(`program`, `statement_block`, `class_body`, and the block-bearing bodies of `if` /
`for` / `while` / `switch`), not at the child of the root. Top-level statements are
the special case where those two rules coincide — which is why the whole existing
suite passes.

Treesitter is still trusted for **position only** (ADR-0001 and the module header
stand): the anchor may be an `ERROR` node, and every meaning decision stays in
`analyze` on raw text.

**Blocked by:** —

**Status:** done

## Repro

`.scratch/v1-bugs/loop.sh` — the `nested call-args` case. Or, at the `locate` seam:

```lua
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'function outer() {', '  const x = getValue(a, b', '}' })
require('fullstop.locate').locate(0, { 2, 24 })
```

Actual — the region is the whole function:

```
region.text    = "function outer() {\n  const x = getValue(a, b\n}"
region rows    = 0..2
ancestor chain = ERROR -> statement_block -> function_declaration -> program
```

Expected — the region is the nested statement, rows `1..1`, text
`"  const x = getValue(a, b"` (or the statement without its leading indent, whichever
the `start_col` contract already implies).

End to end:

```ts
function outer() {          function outer() {
  const x = getValue(a, b     →   const x = getValue(a, b);
}                             |
                            }
```

Currently produces `}) } {` on a line of its own after the closing brace.

## Checklist

- [x] A failing test at the `locate` seam asserts the region for a statement nested
      one level inside a function body — added and watched red before the fix.
- [x] The rise stops at the statement container boundary; top-level behaviour is
      unchanged (the existing 59 tests stay green).
- [x] Nested inside: a function body, an arrow body, an `if` body, a `for` / `while`
      body, and a class method body.
- [x] Nested two levels deep (`function` → `if` → statement) anchors to the innermost
      statement, not to either enclosing block.
- [x] A multi-line statement nested inside a block still completes as one whole
      (the "cursor selects, never bounds" rule from `CONTEXT.md`).
- [x] The indent context is taken from the nested statement's own line, so the block
      and fresh line land at the statement's indent, not the construct's.
- [x] `.scratch/v1-bugs/loop.sh` passes every nested case.
- [x] The `locate.lua` header comment is updated — it currently documents the
      rise-to-root rule and predicts this exact failure.

## Comments

- The module header already flagged the risk: *"a delimiter-based fallback ladder for
  multi-line ERROR-tree mis-anchoring is a later ticket, added only if it stings in
  practice."* It stings; this is that ticket.
- Worth checking whether the fix wants an ADR. The anchoring rule is the load-bearing
  decision in `locate`, and `ERROR` nodes can bracket unpredictably when a broken
  statement swallows its siblings — if the implementation ends up choosing between
  materially different rules, record it under `docs/adr/`.
- It did: `docs/adr/0002-anchor-at-statement-container-boundary.md`. The container list
  is a whitelist of *statement holders* (`program`, `statement_block`, `class_body`,
  `switch_body`, `switch_case`, `switch_default`) rather than of block-ish nodes —
  `object`, `interface_body` and `arguments` are deliberately out, so a statement
  wrapping an object literal still anchors to the whole statement. A probe of the real
  trees confirmed every nested shape in the checklist puts its `ERROR` (or its valid
  statement node) directly under one of those six.
- One behaviour beyond the checklist came out of the same rule, and it was a mangling
  case too: a cursor that lands *on* a container (a blank line in a function body, a
  brace line) now has no statement → Advance. The old `node == root` guard was exactly
  this rule for top level; generalising it costs one condition. Before, firing on a
  blank line inside a function anchored to the whole function and spliced `} {` after
  its closing brace.
- Known residual, recorded in ADR-0002 and the module header rather than fixed here, and
  now filed as **issue 04**: a broken statement whose own delimiters swallow the
  enclosing block's brace leaves no statement node to anchor to. An unclosed `{` or `${`
  eats the `}` below it; a tail after the block (`} catch`, `} while`, `})`) collapses the
  construct into one `ERROR`. The anchor is then the construct — the original report's
  `}) } {` signature — or nil (→ Advance) when that `ERROR` is the tree root, which is
  what `useEffect(() => {` does. `tests/test_locate.lua` pins two of those shapes as
  characterization tests, labelled as today's behaviour rather than desired.
- Term watch for `/domain-modeling`: *statement container* is now load-bearing across
  `locate`, ADR-0002 and the tests, and isn't in `CONTEXT.md`'s Language section. Left out
  deliberately — it names a treesitter grammar boundary, not a user-facing domain concept,
  and the glossary so far holds only the latter. Worth a ruling.
- Verification: `tests/test_locate.lua` is new (14 cases at seam A — 11 of them red
  before the fix, for the right reason: the region was the whole construct). Full suite
  73 green, `luacheck` and `stylua --check` clean. `loop.sh` in a real interactive
  Neovim: every nested case passes; the one failure is `call-args (normal)`, whose
  readiness line reads `normal=<Cmd>ZellijNavigateDown<CR>` — issue 03, not this one.
  Note that the harness loads fullstop from the lazy clone, so testing the working tree
  needs `--cmd` `package.preload` for the four `fullstop*` modules; a plain
  `set rtp^=` loses to lazy's own rtp insertion.
- The integration-suite sweep stays with issue 02 — this ticket's tests deliberately sit
  at the `locate` seam so the two don't overlap.
- `/code-review` (both axes) then tightened the change: the rise and the "cursor sits on a
  container" guard collapsed into one loop with a single predicate (`statement` tracks the
  last node below the innermost container, so the two nil paths stay distinct in
  comments); the tests moved to ordered `ipairs` fixtures with named-field assertions,
  delete their scratch buffers, and now cover `indent_context.unit` (`locate` is its only
  producer). ADR-0002 lost a mis-citation — position-only trust is the spec's decision,
  not ADR-0001 — and its injected-tree argument now says what actually holds it up (no
  grammar injected into a TS/TSX buffer roots at `program`), not that no grammar anywhere
  does.
