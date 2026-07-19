# 03 — Decline gate + terminator & comment correctness

**What to build:** The safety net and the placement rules on top of the balancer. The lexer gains a confidence flag and returns **Decline** (no buffer change, a `vim.notify` hint) whenever it can't be sure — ambiguous regex-vs-division `/`, `${…}` nesting past depth 1, or an unterminated string. The terminator logic treats only a `;` at **delimiter-depth 0 at the statement tail** as "already terminated" (so a `for(;;)` header or an object's inner `;` never triggers a wrong Advance), and closers/`;` splice **before** any trailing comment so it survives.

**Blocked by:** 02.

**Status:** ready-for-agent

- [ ] Ambiguous regex (`const r = /a(b/`) → **Decline**: buffer unchanged, hint shown, no fresh line.
- [ ] Deep `${…}` nesting and unterminated strings → Decline, never a guessed close.
- [ ] `for (let i = 0; i < n; i++` → the header `;` don't count as terminators (handled correctly, not seen as already-terminated).
- [ ] A statement with a depth-0 tail `;` → **Advance** (fresh line below), no double `;`.
- [ ] `const x = getValue(a  // grab it` → `const x = getValue(a); // grab it` (insertion before the comment; comment preserved).
- [ ] Decline and Advance are distinct: **Decline never opens a line.**
- [ ] Table-driven `analyze` tests cover each edge.
