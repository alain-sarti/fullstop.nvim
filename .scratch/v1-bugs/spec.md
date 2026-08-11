# v1 field bugs

Bugs found using v1 in a real editor, after the v1 checklist closed. Diagnosed via
`/diagnosing-bugs` on 2026-08-11.

## Report

> "The plugin basically does not do anything it is supposed to."

## Diagnosis

Two independent causes, one in the plugin and one in the user's config.

### 1. `locate` anchors to the enclosing block, not the statement

`lua/fullstop/locate.lua` rises to "the child of the tree root". For a statement
nested inside any block — a function body, an `if`, a class method — that walk goes
straight past the statement and lands on the whole enclosing construct. `analyze`
then balances the entire construct's text and `apply` splices the closers at its
last line.

Since virtually every statement in real code is nested, this is the whole report.
Top-level statements work; nothing else does. See issue 01.

Probe, cursor on the nested statement:

```
region.text    = "function outer() {\n  const x = getValue(a, b\n}"
ancestor chain = ERROR -> statement_block -> function_declaration -> program
```

Observed:

```ts
function outer() {
  const x = getValue(a, b
}) } {     ← closers spliced at the end of the whole function

}
```

The code comment on that walk already predicted this — *"a delimiter-based fallback
ladder for multi-line ERROR-tree mis-anchoring is a later ticket, added only if it
stings in practice."*

### 2. The 59-test suite is green throughout

Every fixture in `tests/test_integration.lua` is a top-level statement. Several are
*indented* (`'  const y = bar(1'`), which resembles nesting but has no enclosing
block, so rise-to-root accidentally lands on the right node. Not one test places a
statement inside a real `{ }`. See issue 02.

### 3. Normal-mode mapping shadowed by another plugin

In the reporter's config `<C-j>` resolves to `<Plug>(CompleteStatement)` in insert
mode but to `<Cmd>ZellijNavigateDown<CR>` in normal mode — `zellij-nav.nvim` maps it
via lazy `keys`, re-registering after fullstop's `ft` load. A config-level conflict,
not a plugin defect, but fullstop gives the user no way to notice it. See issue 03.

## Acceptance loop

`loop.sh` in this directory drives a real interactive Neovim (full user config, real
pty via tmux) over `--listen` RPC: set buffer → place cursor → type the real mapped
key → read the buffer back as JSON. Roughly 30s for a full matrix.

```
.scratch/v1-bugs/loop.sh            # default matrix
KEY='<C-CR>' .scratch/v1-bugs/loop.sh
```

It complements `make test` rather than replacing it: `make test` is the CI gate,
`loop.sh` is the "does it work in the editor I actually use" check that would have
caught this batch.

Three environment traps it already handles, all of which cost time to find:

- macOS caps unix socket paths at 104 bytes, so the socket lives at `/tmp/`.
- Neovim needs ~10s to finish loading a full config before it accepts keys; keys
  sent earlier can kill it.
- A stale swapfile parks Neovim at an `E325` prompt where it silently eats all
  input — hence `-n`.
