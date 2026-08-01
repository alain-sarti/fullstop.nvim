# fullstop.nvim

Finish the TypeScript statement your cursor is in — Neovim's answer to IntelliJ's
**Complete Current Statement** (Cmd+Shift+Enter). Named for the British full stop,
the mark that ends a statement.

Fire it anywhere inside an unfinished statement and fullstop closes the open
delimiters, opens the block or adds the terminator, and drops you into insert mode
on the right line — in one undo.

```ts
const x = getValue(a, b   →   const x = getValue(a, b);
                              |

if (cond                  →   if (cond) {
                                  |
                              }

function foo(a: string    →   function foo(a: string) {
                                  |
                              }

const f = (x) =>          →   const f = (x) => {
                                  |
                              };
```

The cursor only *selects* which statement — it never bounds the completion. Firing
from the middle of a statement, or from a wrapped continuation line, still completes
the whole thing.

## Outcomes

Every fire resolves to exactly one of three outcomes:

| Outcome | When | What happens |
|---|---|---|
| **Complete** | There's a delta | Insert the missing delimiters / block / terminator, place the cursor |
| **Advance** | Nothing to finish — already complete, empty line, no statement | Open a fresh line below. A *success*, not a no-op |
| **Decline** | The structure can't be read safely, or the filetype isn't configured | Change nothing, show a `vim.notify` hint |

Decline fires when the lexer can't read the statement's structure — an ambiguous
regex-vs-division `/`, `${…}` nesting past depth 1, or an unterminated string — and
in a buffer whose filetype isn't in `filetypes`. It is never a silent newline
masquerading as success.

fullstop is **purely additive** — it only ever inserts, never deletes or rewrites
(see [ADR-0001](docs/adr/0001-purely-additive-completion.md)). The worst case is a
useless insertion that reverts in one `u`, never destroyed code.

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

The mapping works in insert mode (primary) and normal mode; either way you land in
insert mode at the completion point.

Requires the `typescript` and `tsx` treesitter parsers.

### Mapping per filetype

The snippet above maps the key globally once the plugin has loaded, leaning on the
built-in guard to Decline in other buffers. Note that `ft =` defers loading until you
first open a TS buffer — until then the key is simply unmapped.

To scope the key to TS buffers properly, and keep it free elsewhere in every session,
map it in `ftplugin/typescript.lua` (and `ftplugin/typescriptreact.lua`) instead. The
guard is then only a backstop:

```lua
-- ~/.config/nvim/ftplugin/typescript.lua
vim.keymap.set({ 'i', 'n' }, '<C-CR>', '<Plug>(CompleteStatement)', { buffer = true })
```

## Config

```lua
require('fullstop').setup({
  filetypes  = { 'typescript', 'typescriptreact' },
  semicolons = true,
})
```

**`filetypes`** — buffers fullstop acts in. Anything else Declines with a
`fullstop: unsupported filetype` hint and leaves the buffer untouched.

**`semicolons`** — set `false` for ASI / `semi: false` projects. No `;` is appended
anywhere: `const x = foo(a, b` → `const x = foo(a, b)`, and an assigned expression's
closing brace is `}` rather than `};`. Delimiters still close and blocks still open;
with no terminator to add, a balanced statement counts as already complete and
Advances.

## TSX support

`.tsx` is **best-effort on the TypeScript parts**. `locate` uses the buffer's own
parser, so plain TS statements in a `typescriptreact` buffer — including component
arrow heads like `const App = () =>` — complete exactly as they do in `.ts`.

There is **no JSX-specific logic** in v1. Firing *inside* JSX may produce a useless
result or a Decline; because fullstop is purely additive, it will never mangle your
markup, and a useless insertion reverts in one `u`.

## Not in v1

Documented gaps, deliberately unbuilt:

- **Class members** — methods, `get` / `set`, `constructor` (needs class-body context,
  which collides with treesitter-for-position). A bare `foo(a` inside a class body
  completes as a call.
- **`interface` / `type` / `enum` / `namespace`** block-openers.
- **Destructuring LHS** — `const { a, b` reads as an object literal → `const { a, b };`
  (non-destructive, just not useful).
- **Dot-repeat** (`.`) — needs repeat plumbing for a command that ends in insert mode.
- **JSX-aware Decline** — recognising JSX context in `.tsx` and bowing out, instead of
  best-effort.
- **Auto-detecting semicolon style** from the buffer or `.prettierrc`.
- **Filetypes beyond TS/TSX** (JavaScript, etc.) once the rules are validated there.
- **`locate` fallback ladder** — a delimiter-based fallback for multi-line ERROR-tree
  mis-anchoring, added only if the whiffs sting in practice.
- **Removing or rewriting existing code** — obsolete-`;` cleanup, reinterpreting
  finished statements (`if (cond);` → block). Never a silent default.

## Develop

```sh
make check       # everything: lint + format-check + tests
make test        # full mini.test suite, headless
make test-file FILE=tests/test_analyze.lua
make lint        # luacheck (correctness)
make format      # stylua, in place (formatting)
make parsers     # compile the typescript/tsx parsers into deps/
```

Linting needs `luacheck` and `stylua` (`brew install luacheck stylua`). `make`
clones its test dependency (mini.nvim) into `deps/` on first run.

Tests need the `typescript`/`tsx` treesitter parsers: they're used from your
standard Neovim data dir if present, otherwise run `make parsers` once to build
them into `deps/` (needs a C compiler). CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml))
always builds them this way, so the suite is reproducible on a bare machine.

MIT licensed.
