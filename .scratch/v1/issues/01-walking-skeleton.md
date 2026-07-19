# 01 — Walking skeleton: terminate a statement end-to-end

**What to build:** The complete keypress → completion pipeline for the simplest case, proving every layer works together. Fire `<Plug>(CompleteStatement)` in a TypeScript buffer on an unfinished statement with an open `(`; fullstop closes it, appends `;`, drops a fresh line below, and leaves you typing in insert mode — all as one undo. On an already-complete or empty line it just opens a fresh line below (**Advance**). This ticket stands up the project scaffold and the `mini.test` harness so every later ticket has somewhere to land. See `.scratch/v1/spec.md` for the module contracts and the tagged-verdict shape.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [x] `const x = foo(a, b` + fire → `const x = foo(a, b);`, cursor on a fresh line below at base indent, in insert mode.
- [x] The whole completion reverts with a single `u`.
- [x] An already-terminated line, or an empty line, → **Advance** (fresh line below), lands in insert.
- [x] `<Plug>(CompleteStatement)` fires from both insert and normal mode; a normal-mode fire lands in insert.
- [x] Firing in a non-`typescript` buffer leaves the buffer untouched (filetype guard).
- [x] `analyze` returns a tagged verdict (`complete` / `advance` / `decline`) and calls no `vim.*`; `locate` gets its parser from the buffer, not hardcoded.
- [x] `make test` runs the `mini.test` suite headless and passes.
