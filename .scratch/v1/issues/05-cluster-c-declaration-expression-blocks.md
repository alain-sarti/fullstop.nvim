# 05 — Cluster C: declaration & expression blocks

**What to build:** Declaration and arrow classification, reusing the block infrastructure from ticket 04. Recognise `function` (incl. `async function`, `function*`), `class`, and arrows — through `export` / `export default` prefixes and assignment RHS. The block opens as in B, but the terminator is `;` **iff** the construct is an assigned expression (`const f = function`, `const f = () =>`, `const C = class`) and `∅` for declarations. The `=>` rule decides the arrow: bare `=>` opens a block (`;`), `=> expr` / `=> (…)` is an expression body (terminate, cluster A), `=> {` closes the block.

**Blocked by:** 04.

**Status:** ready-for-agent

- [ ] `function foo(a` → block, no `;`; `export function foo(a` and `export default class Bar` → block, no `;`.
- [ ] `class Bar extends Foo` → block, no `;`.
- [ ] `const f = function(a` → block + `;`; `const C = class` → block + `;`.
- [ ] `const f = () =>` → block + `;`; `const f = (x) => x + 1` → `;` (expression body, no block); `const f = () => (` → terminate.
- [ ] Bare class members (`foo(a` inside a class body) stay a call, not a declaration (documented v2 gap).
- [ ] Table-driven `analyze` tests cover each form and all three `=>` cases.
