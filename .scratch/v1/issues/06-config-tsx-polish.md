# 06 — Config, TSX & polish

**What to build:** Finalise the config surface and ship-readiness. `setup({ semicolons, filetypes })`: `semicolons = false` appends no `;` anywhere and treats a delimiter-balanced statement with no `;` as already-complete → **Advance**; `filetypes` defaults to `{ "typescript", "typescriptreact" }` and the guard **Declines** with a hint on any other filetype. Confirm `.tsx` buffers complete plain TS statements via the buffer parser. Write the README: install snippet, `<Plug>` mapping (global + the `ftplugin/typescript.lua` suggestion), config options, the TSX best-effort caveat, and the v2 gaps list from the spec.

**Blocked by:** 05.

**Status:** ready-for-agent

- [ ] `semicolons = false`: `const x = foo(a, b` → `const x = foo(a, b)` (no `;`); a balanced no-`;` statement → Advance.
- [ ] `filetypes` default includes `typescript` and `typescriptreact`; a plain TS statement in a `.tsx` buffer completes.
- [ ] A filetype not in the list → **Decline** with a `"fullstop: unsupported filetype"` hint, buffer untouched.
- [ ] README documents install, mapping (global + ftplugin), config, TSX best-effort, and v2 gaps.
- [ ] Full `make test` suite passes.
