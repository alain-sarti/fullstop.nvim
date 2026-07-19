# fullstop.nvim — Design (v1)

Date: 2026-07-16. Refined via a grilling + domain-modeling session the same day;
this file supersedes the original design note that lived in the vault.

## Goal

Bring IntelliJ's **Complete Current Statement** (Cmd+Shift+Enter) to Neovim for
TypeScript: on a keypress, semantically finish the statement the cursor is in and
drop onto a fresh line / into the new block. This is the most-missed IntelliJ
feature from the JetBrains → Neovim switch.

Named for the British full stop — the mark that ends a statement.

## Core model

Three ideas the rest of the spec leans on. See `CONTEXT.md` for the canonical glossary.

- **Current statement** — the full *logical* statement the cursor sits in, from its
  first token to the end of its text, **not** the physical line. A statement that wraps
  across lines is completed as one whole. The **cursor only *selects* which statement;
  it never *bounds* the completion** — firing from anywhere inside a statement completes
  the whole thing. (Intent: "I added a call inside an existing line, finish the line, I
  don't care where my cursor is.")
- **Three outcomes** — every fire resolves to exactly one:
  - **Complete** — a delta exists → insert missing delimiters / an opened block / a
    terminator, then place the cursor.
  - **Advance** — nothing to finish (already complete, empty line, or no statement) →
    open a fresh line below. A *success* outcome.
  - **Decline** — can't safely determine structure → change nothing, show a
    `vim.notify` hint. **Never** a silent newline (that would masquerade as success).
- **Purely additive** — fullstop only ever *inserts*; it never deletes or rewrites
  existing characters (see `docs/adr/0001-purely-additive-completion.md`). Worst case is
  a useless insertion that reverts in one `u` — never destroyed code.

## Scope

**In (v1):**

- Languages: **`typescript` and `typescriptreact`** (default `filetypes`). TSX is
  **best-effort on the TypeScript parts** — plain TS statements complete identically;
  firing *inside* JSX may produce a useless (but, per the additive rule, never
  destructive) result or a Decline. No JSX-specific logic in v1.
- Cursor may be **anywhere inside the statement**, including on a wrapped continuation
  line.
- Completion is driven by two orthogonal axes (below), not a hard A/B/C enum.

**Out (explicit non-goals):**

- JavaScript and every non-TS/TSX language.
- JSX-aware handling (auto-close tags, JSX-context Decline).
- Auto-import, method-chain reflow, completing multiple statements at once.
- Removing/rewriting existing code (obsolete-`;` cleanup, reinterpreting finished
  statements) — deliberately v2, never a silent default.

## Decisions

- **Treesitter locates, rules complete.** An unfinished line does not parse cleanly
  (`if (cond` is an `ERROR` node, not an `if_statement`), so we do not lean on the AST
  for the fix. Treesitter finds *where* the statement is; a small rule set decides *what*
  to insert. Rejected full-AST-dispatch: incomplete input means constant `ERROR`-tree
  spelunking, exactly where treesitter is least stable.
- **`locate` is treesitter-only and thin, for now.** It walks up from the cursor to the
  enclosing statement region and returns it — accepting that error-recovery will
  occasionally mis-anchor on multi-line ERROR trees. A delimiter-based fallback ladder is
  a *later* bug ticket, added only if the whiffs sting in practice. Treesitter is trusted
  for **position only**, never for meaning (every classification and delimiter decision
  happens in `analyze` on raw text).
- **`locate` uses the buffer's own parser** (`vim.treesitter.get_parser(buf)`) so it
  works with the `typescript` *and* `tsx` grammars.
- **Pure brain, thin shells.** All thinking lives in `analyze`, which never calls
  `vim.*` and does not know where the cursor is — so it is unit-testable as plain Lua.
  `locate` and `apply` stay dumb.
- **`analyze` is cursor-free.** The cursor is entirely `locate`'s business (region
  selection). By the time `analyze` runs there is one region, and nothing in the brain
  needs to know the cursor's position within it.
- **No forced keybind.** Expose `<Plug>(CompleteStatement)`; the user maps their own.
  Works in insert mode (primary) and normal mode.
- **Single test framework: `mini.test`**, one `make test`, runs headless nvim.
- Ship **public on GitHub**, MIT licensed. Lives at `~/Dev/fullstop.nvim`, pushed via
  the `origin` remote (`git@github.com:alain-sarti/fullstop.nvim.git`).

## Architecture

Pure brain wrapped in thin Neovim shells.

| Module | Responsibility | Depends on |
|---|---|---|
| `analyze` | **Pure Lua, zero `vim.*`, cursor-free.** Input: `analyze(region_text, indent_context)`. Output: a **tagged verdict** (see below). Holds all rules: delimiter balancer, construct classifier, completer. | nothing |
| `locate` | Treesitter shell: from buffer + cursor, using the buffer's parser, walk up to the enclosing statement region → `{ text, start, end, indent_context }`, or `nil` if none. | nvim + treesitter |
| `apply` | Nvim shell: execute a verdict in **one undo block**, set cursor, land in insert mode. | nvim API |
| `init` | Public API + config: `setup(opts)`, `complete_statement()` wiring locate → analyze → apply, filetype guard, `vim.notify` for Decline. | the above |

**Tagged verdict** returned by `analyze`:

```
{ kind = "complete", insert, cursor_pos, opens_block }
{ kind = "advance" }
{ kind = "decline", reason }          -- reason is a plain string for vim.notify
```

`analyze` *decides and explains* but never speaks to Neovim — the hint text is just a
string it hands back.

**Data flow:** keypress → `complete_statement()` → filetype guard → `locate` finds the
region (or `nil`) → `analyze` returns a verdict → `apply`/`init` execute it (splice +
cursor + insert mode, open a line, or notify).

## Behaviour contract

`|` = final cursor, **in insert mode** (fullstop always lands in insert mode, whatever
mode it was fired from — except Decline, which leaves the mode untouched).

### The two axes (replaces the A/B/C enum)

Classification is **structural** — it finds the *governing construct*, not the first
token (`export function foo(`, `const f = () =>`, and `return foo(` all have the keyword
buried). Two orthogonal facts drive the whole edit plan:

1. **`opens_block?`** — does a `{ }` block open?
2. **`terminator`** — `";"` for an assigned expression / plain statement, `∅` for a
   self-terminating declaration.

The `insert` string is one idempotent recipe:

```
insert = close_missing_delimiters(region)           -- only the ) ] } actually open
       + (opens_block ? " {\n<base+unit>\n<base>}" : "")
       + (terminator needed AND not already present ? terminator : "")
```

- `close_missing_delimiters` closes the whole open stack, or nothing if balanced.
- "already present" for the terminator means a `;` at **delimiter-depth 0 at the tail**
  — internal `;` (e.g. a `for(;;)` header) never counts.
- When all three deltas are empty, `insert` is empty → that is the **Advance** case.

The familiar clusters are just points in the 2×2:

- **A — terminate** = no block, `;` terminator.
- **B — control-flow block** = block, no terminator.
- **C — declaration/expression block** = block; terminator `;` iff assigned.

### Classification rules

Reading the region's tokens outside strings/comments, first match wins:

1. **Statement head is a control-flow keyword** → block, no `;` (**B**). Set:
   `if` / `else` / `else if` / `for` (incl. `for…of` / `for…in`) / `while` / `switch` /
   `try` / `catch` / `finally`.
   - **`do…while` guard:** a `while` head immediately preceded by a closing `}` is the
     do-while tail → **terminate (A)**, not a block (`} while (cond)` → `} while (cond);`).
     Every other `while` is B. `do` on its own opens a block.
2. **Region contains a declaration head wanting a body** → block (**C**):
   `function` (incl. `async function`, `function*`) / `class`, as a statement or after an
   `export` / `export default` prefix, *or* a trailing `=>` with no body yet. Terminator
   `;` iff it is the RHS of an assignment (`const f = function`, `const f = () =>`,
   `const C = class`); `∅` for declarations (`function foo`, `class Bar`,
   `export function`).
   - **`=>` rule (three exhaustive cases on what follows the arrow):**
     - followed by **nothing** → open a block, `;` (assigned). `const f = () =>` →
       `const f = () => {␤ | ␤};`
     - followed by an **expression** (`x + 1`, `(`, `foo(`, `[`, …) → **A** (expression
       body, just terminate). Includes `=> (…)` and object returns `=> ({…})`.
     - followed by **`{`** → the brace is already there → close it as a block (below).
3. **Otherwise** → **A** (balance, add `;`).

### Brace handling (`{`)

`{` is always tracked (needed both for idempotent block-open and to avoid mangling
object literals). An open `{` is a **block** (cursor inside; `;` only if assigned) when it
follows a block-context token — `)` of a control-flow/function head, `=>`,
`else`/`try`/`finally`/`do`, `class …`; otherwise it is an **object/expression literal**
(close `}`, add `;`, cursor below). Object and array literals are completed. **Known gap:**
destructuring LHS `const { a, b` reads as an object → `const { a, b };` (non-destructive,
just not useful).

### Balancer safety gate

The balancer is a hand-rolled lexer tracking a stack of `( [ {`, skipping strings
(`'…'` `"…"`), comments (`// …` `/* … */`), and template literals (`` `…` `` — but code
inside `${…}` is still counted). It carries a **confidence flag** and flips to
low-confidence on anything it can't disambiguate: an ambiguous regex-vs-division `/`,
`${…}` nesting past depth 1, or an unterminated string. **Low confidence ⇒ Decline** —
it refuses to guess a close *and* refuses to add a `;` (both would be mangles). Failure
mode is always "did nothing, said so," never "emitted broken code."

### Worked examples

**B — control-flow blocks** (close head paren if open, open block, no `;`):

```
if (cond               →  if (cond) {
                              |
                           }
for (let i=0; i<n; i++  →  for (let i=0; i<n; i++) {
                              |
                           }
} else if (x            →  } else if (x) {
                              |
                           }
switch (v               →  switch (v) {
                              |
                           }
} while (done           →  } while (done);        ← do-while tail: A, not a block
```

**C — declaration/expression blocks** (block body; `;` only for an assigned expression):

```
function foo(a: string  →  function foo(a: string) {
                              |
                           }                          ← declaration, NO ;
const f = (x) =>        →  const f = (x) => {
                              |
                           };                         ← assigned expr, YES ;
class Bar extends Foo   →  class Bar extends Foo {
                              |
                           }                          ← NO ;
```

**A — terminate** (balance `( [ {`, add `;`, fresh line below at base indent):

```
const x = getValue(a, b  →  const x = getValue(a, b);
                            |
foo(bar(a, b             →  foo(bar(a, b));       ← balancer closes the whole stack
                            |
const arr = [1, 2, 3     →  const arr = [1, 2, 3];
                            |
const o = { a: 1         →  const o = { a: 1 };    ← object literal
                            |
foo({ a: 1               →  foo({ a: 1 });         ← nested }) stack
                            |
const x = getValue(a  // grab it   →   const x = getValue(a); // grab it   ← ; before comment
```

### Cursor, indent & mode

- **Indent** is passed into `analyze` as `indent_context = { unit, base }` (`analyze`
  stays string-only; a shell resolves `expandtab`/`shiftwidth`/`tabstop`). `unit` is one
  indent level (`"  "` or `"\t"`); **`base` is the leading whitespace of the statement's
  *head* line** (not the cursor's line), so wrapped continuations don't drag the
  closer/fresh-line indent with them.
  - Opened a block → new line **inside** at `base .. unit`; closing `}` at `base`.
  - Terminated (A) / Advance → new line **below** at `base`.
- **Splice point** = the last code character at delimiter-depth 0; trailing whitespace
  and `// …` / `/* … */` stay put after the insertion.
- **Mode:** fullstop always lands in **insert mode** at the cursor spot, whether fired
  from insert or normal mode (matches IntelliJ / muscle memory). **Decline** is the sole
  exception — it leaves the mode and buffer untouched.

## Config

```lua
require('fullstop').setup({
  semicolons = true,                              -- false ⇒ never append ; (ASI / semi:false projects);
                                                  --   then a balanced statement with no ; is already complete → Advance
  filetypes  = { "typescript", "typescriptreact" },
})
```

- Firing in a buffer whose filetype isn't listed → **Decline** with a
  `"fullstop: unsupported filetype"` hint. README suggests mapping
  `<Plug>(CompleteStatement)` in `ftplugin/typescript.lua` so the guard is only a
  backstop.

## Wiring

```vim
inoremap <Plug>(CompleteStatement) <Cmd>lua require('fullstop').complete_statement()<CR>
nnoremap <Plug>(CompleteStatement) <Cmd>lua require('fullstop').complete_statement()<CR>
```

`<Cmd>` runs the function without leaving insert mode; a normal-mode fire lands in insert
via the function. The whole change is a single `nvim_buf_set_text` → **one undo step**;
no `:undojoin` needed.

## Tricky bits (flagged, not hidden)

1. **The delimiter balancer must skip delimiters inside strings/comments/templates** and
   **Decline** on genuine ambiguity (regex `/`, deep `${…}`, unterminated string) rather
   than mangle — see the safety gate above.
2. **Arrow-vs-block** — bare `=>` wants a block (C, `;`); `=> x + 1` / `=> (…)` is a
   complete expression body → A. The rule most in need of a pinning test.
3. **`} while` disambiguation** — the one place the same keyword (`while`) means opposite
   things depending on a leading `}`. Pin it with a test.

## Layout

```
fullstop.nvim/
  lua/fullstop/
    init.lua      -- setup(), complete_statement(), filetype guard, notify
    analyze.lua   -- pure brain: classifier · balancer · completer (returns verdict)
    locate.lua    -- treesitter region finder (buffer's parser)
    apply.lua     -- execute verdict: buffer edit · cursor · enter insert
  plugin/fullstop.lua  -- defines <Plug>(CompleteStatement) for insert + normal
  tests/               -- mini.test specs
  Makefile · README.md · LICENSE (MIT)
```

## Testing

- **`analyze` (bulk of tests)** — table-driven, pure Lua: `region_text + indent_context
  → expected verdict`. Cursor-free, so no offset column to reason about. Pins the
  arrow-vs-block, `} while`, brace block-vs-object, and balancer-Decline edge cases. The
  red-green-refactor loop.
- **`locate` + `apply`** — smaller integration set against a real buffer + treesitter,
  in both `typescript` and `tsx` buffers.
- One framework (`mini.test`), one `make test`, headless nvim (~100ms startup keeps the
  loop snappy). Split pure-core tests to `busted` later only if that loop ever drags.

## Validation

- Fire mid-statement (cursor not at line end, or on a wrapped continuation line) → whole
  statement still completes.
- Each construct produces the exact output above, cursor in the right place, in one undo
  step, landing in insert mode.
- `=> x + 1` terminates with `;`; bare `=>` opens a block; `} while (x)` terminates —
  all correct.
- Ambiguous regex / deep template / unterminated string → **Decline** with a hint, buffer
  untouched (no fake newline).
- Already-complete line / empty line → **Advance** (fresh line below).
- Trailing comment preserved; `for(;;)` header `;` not mistaken for a terminator.
- Tabs and spaces buffers both indent correctly; `base` tracks the head line.
- `semicolons = false` → no `;` appended; balanced-no-`;` statement is already complete.
- Non-listed filetype → Decline hint. TS statements in a `.tsx` buffer complete.

## v2 gaps (documented, not built)

- Class members — methods / `get` / `set` / `constructor` (need class-body context, which
  collides with treesitter-for-position).
- `interface` / `type` / `enum` / `namespace` block-openers.
- Dot-repeat (`.`) — needs repeat plumbing for an insert-mode-ending command.
- JSX-aware Decline (recognise JSX context in `.tsx` and bow out instead of best-effort).
- Auto-detecting semicolon style from the buffer / `.prettierrc`.
- `filetypes` beyond TS/TSX (JS, etc.) once the rules are validated there.
- `locate` delimiter-based fallback ladder for multi-line ERROR-tree mis-anchoring.
- Obsolete-`;` removal / reinterpreting finished statements (`if (cond);` → block).
