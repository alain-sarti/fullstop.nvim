# 02 — Balancer: full delimiter stack + literals

**What to build:** Replace the skeleton's simple paren-closing with the real balancer — a hand-rolled lexer that tracks a stack of `(` `[` `{`, correctly skipping strings, line/block comments, and template literals (while still counting code inside `${…}`), and closes the entire open stack in one pass. Object and array literals in expression position are terminated. This makes fullstop correct on nested and mixed delimiters, not just a single paren. Braces here are expression-context only (object literals); block-opening arrives in ticket 04.

**Blocked by:** 01.

**Status:** ready-for-agent

- [ ] `foo(bar(a, b` → `foo(bar(a, b));` (whole stack closed in order).
- [ ] `const arr = [1, 2` → `const arr = [1, 2];`.
- [ ] `const o = { a: 1` → `const o = { a: 1 };` and `foo({ a: 1` → `foo({ a: 1 });`.
- [ ] Delimiters inside strings/comments are not counted: `foo("a)b"` and `foo(a /* ) */` balance correctly.
- [ ] Code inside `${…}` **is** counted: `` `${foo(a `` closes the inner `(`.
- [ ] Covered by table-driven `analyze` tests (`region_text + indent_context → verdict`).
