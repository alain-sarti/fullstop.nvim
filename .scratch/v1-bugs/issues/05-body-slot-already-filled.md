# 05 — A construct whose body slot is already filled still gets a `{ }` opened

**What to build:** The concept `analyze` is missing. Its three classifiers —
`opens_block` (`analyze.lua:203`), `is_decl_head` (`:243`) and `arrow_opens_block`
(`:265`) — ask *"does this text start with a block keyword?"* and use the answer for
*"does this construct still need a body?"*. Those diverge the moment the construct's
**body slot** is already filled, and `apply` then splices at `region.end_col` — the end
of the **body**, not of the head.

Reported as: *"if I add an if statement (like `if(test)`) the line that gets a `{}`
block is the next statement, not the if line."* That is one of seven shapes; the same
root cause mangles code that works today.

**Blocked by:** —

**Status:** done

## Repro

`if (test)` followed by a statement is *valid* TypeScript — the next statement **is**
the body. So treesitter is right and `locate` is right per ADR-0002: the innermost
statement under `program` is the `if_statement`, spanning rows 0..1.

```lua
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'if (test)', 'foo();' })
require('fullstop.locate').locate(0, { 1, 8 })
--> region.text = "if (test)\nfoo();", rows 0..1
```

```ts
if (test)        if (test)
foo();      →    foo(); {

                 }
```

## Behaviour

Fire on the head line unless noted. Every "today" column below was verified end to end.

| in | today | wanted |
| --- | --- | --- |
| `if (test)` ⏎ `foo();` | `foo(); {` … | `if (test) {` ⏎ `  ▌` ⏎ `}` ⏎ `foo();` |
| `if (test)` ⏎ `foo();` *(fire on the body)* | `foo(); {` … | `foo();` ⏎ `▌` — Advance |
| `if (test) foo();` | `if (test) foo(); {` … | Advance |
| `while (a) foo();` / `for (…) foo();` | `foo(); {` … | Advance |
| `} else foo();` | `foo(); {` … | Advance |
| `if (!a) return` | `return {` … | `if (!a) return;` |
| `if (!user) throw new Error('nope'` | `) {` … | `if (!user) throw new Error('nope');` |
| `if (a) x = { b: 1 }` | `} {` … | `if (a) x = { b: 1 };` |
| `if (a) {` ⏎ `  x;` ⏎ `}` | `} {` … | Advance |
| `if (a) { foo();` | `} {` … | `if (a) { foo(); }` |
| `function f() {…}` / `export function f() {…}` | `} {` … | Advance |
| `class C {…}` / `switch (v) {…}` / `try {…} catch {…}` | `} {` … | Advance |
| `const f = function () {…}` / `const C = class {…}` | `} {` ⏎ `};` | `};` |
| `if (cond` · `if (cond) {` · `function f({ a })` · `const f = () => {…}` · `do {…} while (a)` | correct | **unchanged** |

## Design

Decided in a `/grilling` session (2026-08-18), from probes of the real trees.

### `locate` reports the body slot (ADR-0003)

ADR-0002's *"treesitter trusted for position only"* clause is retired: the naive prefix
check **was** the bug, and replacing it with a cleverer text heuristic invites the same
bug again — `function f({ a })` is balanced and ends with `}` yet has no body, which is
what a coarse text rule gets wrong. The grammar answers the question exactly.

`locate` adds one field, `region.body`, a tri-state plus an honest unknown:

| value | meaning |
| --- | --- |
| `'none'` | no body slot filled — open a block (today's behaviour) |
| `'statement'` | filled with an unbraced statement, on the region's last line |
| `'block'` | filled with a block that closes at the region's end |
| `'unknown'` | the anchor is an `ERROR` node; the grammar cannot say |

Resolved from the **trailing** body slot — follow `consequence` → `alternative` →
`else_clause.body`, and `body` → `handler` / `finalizer` — so `} else foo();` keys off
the else's body rather than the if's consequence. Wrapper anchors carry no body field at
all (`const f = function () {…}` anchors to `lexical_declaration`,
`export function f() {…}` to `export_statement`), so a second, positional check catches
them: **does a `statement_block` / `class_body` / `switch_body` end exactly at the
region's end?** That needs no extra field names and is wrapper-agnostic.

### `locate` caps the region at the head

When the trailing slot holds an unbraced statement starting on a **later line**, the head
and its body are two statements:

- cursor in the head → the region ends at the head's end, `body = 'none'` → a block opens
  on the head line and the body lands below the closing `}`.
- cursor in the body → re-anchor to the body node; it is the statement.

The cap is at **the body's start, not the cursor's line**, so a multi-line head
(`if (a &&` ⏎ `  b)` ⏎ `foo();`) still completes as one whole — *"the cursor selects,
never bounds"*.

This changes program semantics: `foo()` stops being conditional. Accepted deliberately —
it is what the report asked for and what IntelliJ does, it is textually additive so
ADR-0001 holds, and it is visible on screen and one `u` away. The alternative (wrap the
existing body, preserving semantics) is a one-line change to the cap if this bites.

### `analyze` takes the slot state as a fourth argument

`analyze(region_text, indent_context, opts, body)`. Omitted / nil reads as `'none'`, so
every existing test stays valid unchanged and `analyze` stays pure Lua on plain strings.
`init.lua`'s call site is the one wiring change.

**Decision order — this is the spec, and the order is load-bearing:**

```
1. lex → Decline on failure
2. block-ish head AND code ends with '{'  → reuse the brace, open the block
3. body == 'unknown'                      → text check → 'statement' or 'none'
4. body ~= 'none'                         → never open a block:
                                              term = ';', but '' when body == 'block'
                                                     and self_terminating(code)
                                              insert = closers .. term
                                              nothing to add → Advance
5. otherwise                              → today's cluster B / C / A
```

`self_terminating(code) := opens_block(code) or is_decl_head(code)` — the existing
predicates, re-read as *"is this construct's own terminator implied?"* rather than *"does
it need a block?"*. That is what makes `if (a) {…}` and `function f() {…}` Advance while
`const f = function () {…}` keeps its `;`.

**Step 2 is where a naive implementation breaks a green test.** `if (cond) {` has a
filled slot per the grammar — treesitter parses the lone `{` as an `expression_statement`
— so without step 2 ordered first, `reuses an already-typed block brace` goes red and the
verdict becomes ` };` instead of a block. The grammar and the wanted behaviour genuinely
disagree there; step 2 is the only thing keeping them apart.

### The `'unknown'` text check

An `ERROR` anchor has no fields, and `'none'` is the wrong default for one common idiom:
`if (!user) throw new Error('nope'` would still open a block. The discriminator is
textual — **the head's condition paren is balanced and there is code after it** — and it
runs *only* for `'unknown'`, so the two mechanisms stay in non-overlapping lanes and
neither can mask the other's bug.

**It must recurse through `else`**: `} else if (x` has code after `else`, but that code is
itself a block head, so the check recurses onto `if (x` and reports `'none'`. Without the
recursion it reads as filled and completes to `);` instead of `) {`.

## Checklist

- [x] Red-first tests at the `analyze` seam: the tri-state × cluster grid, step 2's
      brace reuse, and the `else` recursion in the `'unknown'` text check.
- [x] Red-first tests at the `locate` seam: each `body` value, the head cap (including a
      multi-line head), and the cursor-on-body re-anchor.
- [x] Every row of the Behaviour table completes to the "wanted" column, asserted at the
      integration seam through issue 02's shape × case matrix, so each is covered nested
      as well as top level.
- [x] The five "unchanged" shapes stay unchanged; the full suite stays green.
- [x] `ADR-0003` records the retirement of position-only trust; ADR-0002 gains a pointer
      and keeps its history; `locate.lua` and `analyze.lua` headers point at 0003.
- [x] `CONTEXT.md`: the *current statement* definition is amended for the head/body split,
      and **head** + **body slot** join the Language section. **statement container**
      stays out — TS-language concepts in, treesitter-grammar concepts out. That principle
      settles the ruling issue 01 asked for.
- [x] `.scratch/v1-bugs/loop.sh` grows a case per row and passes.

## Known residuals — document, do not fix

- `catch (e)` ⏎ `foo();` — `ERROR` anchor, so the text check reads "filled" and the
  outcome is Advance. Not the block you would want, but non-mangling, and better than
  today's `foo(); {`.
- `if (test` ⏎ `foo();` — treesitter pulls `foo()` into the condition and calls the `;`
  the consequence. Neither mechanism helps; additive garbage, revertible in one `u`.
- Issue 04's swallowed-brace family is separate and stays open.

## Outcome

184 cases green (`analyze` 46, `locate` 48, integration 90), `luacheck` and
`stylua --check` clean, and the real-editor loop 28/0 with one skip. Three notes on
where the build differed from the plan above:

- **`if (a) { foo();` left the integration matrix.** Nested, this statement's own `{`
  swallows the enclosing `}`, so the tree holds no statement to anchor to and the fire
  Advances — ADR-0002's swallowed-brace residual (issue 04), not a slot failure. It is
  asserted at top level instead, with the reason recorded next to it.
- **`loop.sh`'s `run` gained an optional cursor column.** It could only fire at end of
  line, which for `if (a) {` lands *on* the brace — a cursor in a container, so Advance —
  and for `if (a) { foo();` lands on the inner statement, which the cursor then selects.
  Both are correct, neither is the row being pinned; the column makes the head reachable.
  The `body in open block` row now pins the inner-statement fire deliberately.
- **The normal-mode loop row skips here** — this machine's `<C-j>` is
  `<Cmd>ZellijNavigateDown<CR>` in normal mode, which shadows the plugin's map. The loop
  reports the shadowing map rather than failing; `tests/test_integration.lua` covers the
  normal-mode fire in a child Neovim that owns its own mapping.

## Comments

- Found in a real editor after issues 01/02 closed, and *not* an instance of issue 04:
  every shape here comes from a **clean** tree, so it was reachable the whole time and the
  `}) } {` signature from the original report is still one keystroke away on a complete
  `function` head.
- `switch (x)` and `try` are immune — their grammar demands a `{`, so treesitter never
  absorbs the following statement. The absorbing set is exactly the constructs with a
  single-statement body slot: `if` / `else`, `while`, `for` / `for-in` / `for-of`.
