# fullstop.nvim

Finish the TypeScript statement your cursor is in — Neovim's answer to IntelliJ's
**Complete Current Statement** (Cmd+Shift+Enter). Named for the British full stop,
the mark that ends a statement.

Fire it on an unfinished line and fullstop closes the open delimiters, adds the
terminator, and drops you onto a fresh line — from anywhere inside the statement,
in one undo. On an already-complete or empty line it just opens a fresh line below.

> **Status: early.** The walking skeleton is in place — a statement with an open
> `(` `[` `{` is balanced and terminated (`const x = foo(a, b` → `const x = foo(a, b);`).
> The full delimiter balancer, the safety/decline gate, and block-opening
> (`if`, `function`, `=>`, …) are landing ticket by ticket.

## Install & map

fullstop exposes `<Plug>(CompleteStatement)` and forces no keybind — you map your
own. With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'alain-sarti/fullstop.nvim',
  ft = { 'typescript', 'typescriptreact' },
  config = function()
    require('fullstop').setup({})
    vim.keymap.set({ 'i', 'n' }, '<C-CR>', '<Plug>(CompleteStatement)')
  end,
}
```

Requires the `typescript` and `tsx` treesitter parsers. Mapping it in
`ftplugin/typescript.lua` is neat — the built-in filetype guard is then only a
backstop.

## Config

```lua
require('fullstop').setup({
  filetypes  = { 'typescript', 'typescriptreact' },
  semicolons = true, -- append `;` where a statement wants a terminator
})
```

## Develop

```sh
make test        # full mini.test suite, headless
make test-file FILE=tests/test_analyze.lua
```

`make` clones its test dependency (mini.nvim) into `deps/` on first run. Tests use
the `typescript`/`tsx` parsers from your standard Neovim data dir.

MIT licensed.
