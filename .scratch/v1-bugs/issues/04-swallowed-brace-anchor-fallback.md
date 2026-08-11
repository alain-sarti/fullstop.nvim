# 04 — Anchor fallback when a broken statement swallows the enclosing brace

**What to build:** The delimiter-based fallback ladder `locate`'s header has now predicted
twice. Issue 01 fixed the *rise rule* — a nested statement anchors to itself as long as
the tree holds a statement node under a statement container (ADR-0002). This ticket
covers the shapes where it doesn't: when the broken statement's own delimiters swallow
the enclosing block's brace, treesitter produces no such node, and the anchor falls back
to the whole construct.

Two triggers, both verified end to end at the `locate` seam:

- **An unclosed `{` or `${` eats the `}` below it.** The object node then spans the body
  line *and* the enclosing brace line, and its parent is a root-level `ERROR`.
- **A tail after the block** (`} catch`, `} while`, `})`) collapses the construct into one
  `ERROR` (or a nested `ERROR` under one), so no `statement_block` is formed at all.

**Blocked by:** —

**Status:** ready-for-agent

## Repro

Each fires on the nested statement (`expandtab`, `shiftwidth = 2`). Actual output today:

```ts
function o() {              function o() {
  const p = fn({ a: 1, b: 2   →   const p = fn({ a: 1, b: 2
}                             |  }) } {
                              |
                              }
```

| Fixture (cursor on the nested statement) | Actual | Wanted |
| --- | --- | --- |
| `function o() {` / `  const p = fn({ a: 1, b: 2` / `}` | `}) } {` spliced after the function's brace | `  const p = fn({ a: 1, b: 2 });` |
| `function o() {` / `  const p = { a: 1` / `}` | the function's `}` becomes `};`, its body line lost | `  const p = { a: 1 };` |
| `function o() {` / ``  const t = `x${a`` / `}` | `` }` } { `` after the brace | `` const t = `x${a}`; `` |
| `try {` / `  const x = foo(a` / `} catch (e) {}` | `} catch (e) {}) } {` | `  const x = foo(a);` |
| `do {` / `  const x = foo(a` / `} while (b)` | `} while (b)) };` | `  const x = foo(a);` |
| `useEffect(() => {` / `  const x = foo(a` / `})` | Advance (fresh line, nothing closed) | `  const x = foo(a);` |

The last row differs in kind: that `ERROR` is the tree *root*, so `locate` returns nil and
the outcome is a harmless Advance rather than a mangled buffer. Everything above it is
additive garbage — revertible in one `u` per ADR-0001, but garbage.

`tests/test_locate.lua` already pins rows 1 and 4 as characterization tests, labelled as
today's behaviour rather than desired. They are what this ticket flips.

## Checklist

- [ ] A ranking rule for anchor candidates inside a swallowing `ERROR` — decided against
      the alternatives (rebalance from the cursor line outwards? trust the cursor row's
      own delimiters? cap the region at the enclosing brace row?) and recorded in
      `docs/adr/`, since this is the second load-bearing anchoring decision.
- [ ] Treesitter stays trusted for **position only** — no meaning decisions leak out of
      `analyze` (ADR-0001, ADR-0002).
- [ ] Every row of the table above completes to the "Wanted" column.
- [ ] The two characterization tests in `tests/test_locate.lua` are rewritten to assert
      the statement, and the "known residual" notes in `locate.lua`'s header and
      ADR-0002 are updated or removed.
- [ ] Top-level and cleanly-nested behaviour is unchanged: the full suite stays green.
- [ ] `.scratch/v1-bugs/loop.sh` grows a case per trigger and passes.

## Comments

- Found by `/code-review` on the issue-01 fix (2026-08-11): the Spec axis probed shapes
  outside issue 01's checklist and caught that its `}) } {` signature — the one from the
  original bug report — was still reachable. Issue 01 disclosed the family in ADR-0002
  rather than widening its own scope.
- `object`-literal callbacks are the common real-world case (`useEffect(() => {`,
  `items.map((x) => {`, `fn({ … })`), so this is closer to the reporter's "does not do
  anything it is supposed to" than the row count suggests.
