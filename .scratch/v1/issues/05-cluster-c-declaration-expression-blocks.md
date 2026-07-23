# 05 — Cluster C: declaration & expression blocks

**What to build:** Declaration and arrow classification, reusing the block infrastructure from ticket 04. Recognise `function` (incl. `async function`, `function*`), `class`, and arrows — through `export` / `export default` prefixes and assignment RHS. The block opens as in B, but the terminator is `;` **iff** the construct is an assigned expression (`const f = function`, `const f = () =>`, `const C = class`) and `∅` for declarations. The `=>` rule decides the arrow: bare `=>` opens a block (`;`), `=> expr` / `=> (…)` is an expression body (terminate, cluster A), `=> {` closes the block.

**Blocked by:** 04.

**Status:** done

- [x] `function foo(a` → block, no `;`; `export function foo(a` and `export default class Bar` → block, no `;`.
- [x] `class Bar extends Foo` → block, no `;`.
- [x] `const f = function(a` → block + `;`; `const C = class` → block + `;`.
- [x] `const f = () =>` → block + `;`; `const f = (x) => x + 1` → `;` (expression body, no block); `const f = () => (` → terminate.
- [x] Bare class members (`foo(a` inside a class body) stay a call, not a declaration (documented v2 gap).
- [x] Table-driven `analyze` tests cover each form and all three `=>` cases.

## Comments

- Two non-destructive v1 gaps surfaced in code review and documented in `analyze.lua` (`classify_c`), consistent with ADR-0001 (a wrong verdict reverts in one `u`): (1) the RHS/arrow patterns scan raw code rather than tokens-outside-literals, so a literal `= class`/`=>` inside a string can wrongly open a block (head forms are safe, anchored to `^`); (2) a bare arrow is tagged assigned unconditionally, so a callback arrow (`foo(() =>`) still gets a `;`. Both are out of scope for the v1 checklist (which is the `const f = …` assignment shape). A literal-aware classifier (reusing the ticket-02 lexer's string/comment tracking) would close both and could fold in cluster B's `^`-anchored simplification too — a candidate follow-up ticket.
