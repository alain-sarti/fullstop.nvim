# 04 — Cluster B: control-flow blocks

**What to build:** Block-opening — the `opens_block` axis. The classifier recognises a control-flow head and opens an **idempotent** `{ }` block: if a `{` is already typed it supplies only the `}` (block-vs-object lookbehind), otherwise it inserts the whole block — landing the cursor inside at `base + unit`, the closing `}` at `base`, and no trailing `;`. Covers `if / else / else if / for (+of/in) / while / switch / try / catch / finally`, with the `} while → terminate` guard so a do-while tail gets a `;` instead of a block. The indent `unit` is resolved from the buffer by a shell and passed into `analyze`.

**Blocked by:** 03.

**Status:** ready-for-agent

- [ ] `if (cond` → `if (cond) {`, cursor inside at `base + unit`, `}` at `base`.
- [ ] `switch (v`, `for (…`, `while (…`, `try`, `} else if (x`, `catch (e`, `finally` each open a block, cursor inside, no `;`.
- [ ] `if (cond) {` (brace already typed) → supplies only `}`, doesn't double the brace.
- [ ] `} while (done` → `} while (done);` (terminate, not a block).
- [ ] Tabs and spaces buffers both indent correctly; `base` tracks the head line on a wrapped statement.
- [ ] Table-driven `analyze` tests cover each construct, the `} while` guard, and block-vs-object.
