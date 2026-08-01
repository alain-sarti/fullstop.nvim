# 06 — Config, TSX & polish

**What to build:** Finalise the config surface and ship-readiness. `setup({ semicolons, filetypes })`: `semicolons = false` appends no `;` anywhere and treats a delimiter-balanced statement with no `;` as already-complete → **Advance**; `filetypes` defaults to `{ "typescript", "typescriptreact" }` and the guard **Declines** with a hint on any other filetype. Confirm `.tsx` buffers complete plain TS statements via the buffer parser. Write the README: install snippet, `<Plug>` mapping (global + the `ftplugin/typescript.lua` suggestion), config options, the TSX best-effort caveat, and the v2 gaps list from the spec.

**Blocked by:** 05.

**Status:** done

- [x] `semicolons = false`: `const x = foo(a, b` → `const x = foo(a, b)` (no `;`); a balanced no-`;` statement → Advance.
- [x] `filetypes` default includes `typescript` and `typescriptreact`; a plain TS statement in a `.tsx` buffer completes.
- [x] A filetype not in the list → **Decline** with a `"fullstop: unsupported filetype"` hint, buffer untouched.
- [x] README documents install, mapping (global + ftplugin), config, TSX best-effort, and v2 gaps.
- [x] Full `make test` suite passes.

## Comments

- `semicolons` reaches the pure brain as a third `analyze(region_text, indent_context, opts)` argument — `init` hands over `M.config` as plain data, so `analyze` keeps its zero-`vim.*`, cursor-free contract. A single `terminator` local (`';'` or `''`) is the one source every verdict is built from, so cluster A's `;` and cluster C's `};` empty together and block-opening is untouched. `spec.md`'s architecture table was updated to match the new signature.
- The filetype guard and the `.tsx` path were already implemented (issue 01) and merely needed pinning; the new tests assert the exact `"fullstop: unsupported filetype"` hint text, that a narrowed `filetypes` list really does gate a default-supported buffer, and that a component arrow head (`const App = () =>`) completes through the `tsx` grammar.
- Code review caught two README inaccuracies, both fixed: the Outcomes section enumerated Decline's causes as if exhaustive while omitting the filetype guard (which `spec.md` does call a Decline), and the install snippet's `ft = { … }` lazy-loading contradicted the claim that the global mapping "leans on the guard" — with deferred loading the key is simply unmapped until the first TS buffer opens. Worth noting for `/domain-modeling`: `CONTEXT.md` defines Decline narrowly as "can't safely determine the statement's *structure*", which doesn't cover the filetype guard; the README and spec both treat the guard as a Decline, so the glossary entry is the odd one out.
