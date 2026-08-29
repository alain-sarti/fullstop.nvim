-- Pure-brain tests: analyze(region_text, indent_context) -> tagged verdict.
-- No vim.*, no cursor, no buffer — plain Lua, the red-green-refactor loop.
local analyze = require('fullstop.analyze').analyze

local T = MiniTest.new_set()

-- A tab-indent context; issue 01's analyze ignores it (no blocks yet), but the
-- signature is the contract every later ticket builds on.
local ctx = { unit = '  ', base = '' }

T['closes an open paren and terminates'] = function()
  MiniTest.expect.equality(
    analyze('const x = foo(a, b', ctx),
    { kind = 'complete', insert = ');', opens_block = false }
  )
end

T['balanced but unterminated statement just adds the terminator'] = function()
  MiniTest.expect.equality(
    analyze('const x = 1', ctx),
    { kind = 'complete', insert = ';', opens_block = false }
  )
end

T['an already-terminated statement advances'] = function()
  MiniTest.expect.equality(analyze('const x = 1;', ctx), { kind = 'advance' })
end

T['a trailing terminator with whitespace still advances'] = function()
  MiniTest.expect.equality(analyze('const x = 1;   ', ctx), { kind = 'advance' })
end

T['an empty region advances'] = function()
  MiniTest.expect.equality(analyze('   ', ctx), { kind = 'advance' })
end

-- Issue 02: the balancer closes the whole open stack, innermost first.
T['closes a nested paren stack in order'] = function()
  MiniTest.expect.equality(
    analyze('foo(bar(a, b', ctx),
    { kind = 'complete', insert = '));', opens_block = false }
  )
end

T['closes an open array literal'] = function()
  MiniTest.expect.equality(
    analyze('const arr = [1, 2', ctx),
    { kind = 'complete', insert = '];', opens_block = false }
  )
end

T['closes an object literal in expression position'] = function()
  MiniTest.expect.equality(
    analyze('const o = { a: 1', ctx),
    { kind = 'complete', insert = ' };', opens_block = false }
  )
end

T['closes an object literal nested in a call'] = function()
  MiniTest.expect.equality(
    analyze('foo({ a: 1', ctx),
    { kind = 'complete', insert = ' });', opens_block = false }
  )
end

-- Issue 02: the balancer skips delimiters inside string literals.
T['ignores a closer inside a double-quoted string'] = function()
  MiniTest.expect.equality(
    analyze('foo("a)b"', ctx),
    { kind = 'complete', insert = ');', opens_block = false }
  )
end

-- Issue 02: the balancer skips delimiters inside comments.
T['ignores a closer inside a block comment'] = function()
  MiniTest.expect.equality(
    analyze('foo(a /* ) */', ctx),
    { kind = 'complete', insert = ');', opens_block = false }
  )
end

-- The `)` in the comment doesn't balance the paren; the comment is a trailing
-- one, so (issue 03) it is preserved after the insertion via `tail`.
T['ignores a closer inside a line comment'] = function()
  MiniTest.expect.equality(
    analyze('foo(a // )', ctx),
    { kind = 'complete', insert = ');', opens_block = false, tail = ' // )' }
  )
end

-- Issue 02: template-literal text is skipped like a string...
T['ignores a closer inside template-literal text'] = function()
  MiniTest.expect.equality(
    analyze('foo(`a)b`', ctx),
    { kind = 'complete', insert = ');', opens_block = false }
  )
end

-- ...but code inside ${...} is still counted, so an open delimiter there is closed.
T['counts an open delimiter inside a template interpolation'] = function()
  MiniTest.expect.equality(
    analyze('`${foo(a', ctx),
    { kind = 'complete', insert = ')}`;', opens_block = false }
  )
end

-- Issue 03: the decline gate. When the lexer can't be sure of the structure it
-- returns Decline (buffer untouched, a hint), never a guessed close.

-- A `/` where a regex could begin (after `=`, an opener, an operator, ...) is
-- ambiguous with division, and a regex body's ( [ { would poison the balancer.
T['declines an ambiguous regex literal'] = function()
  MiniTest.expect.equality(
    analyze('const r = /a(b/', ctx),
    { kind = 'decline', reason = 'ambiguous regex or division' }
  )
end

-- ...but a `/` right after an expression is plain division: lex it and complete.
T['treats a slash after an expression as division, not a decline'] = function()
  MiniTest.expect.equality(
    analyze('const x = a / b', ctx),
    { kind = 'complete', insert = ';', opens_block = false }
  )
end

-- Template interpolation nested past depth 1 (a template inside a `${...}`) is
-- beyond what the balancer safely tracks.
T['declines a template literal nested inside an interpolation'] = function()
  MiniTest.expect.equality(
    analyze('`a${`b', ctx),
    { kind = 'decline', reason = 'nested template literal' }
  )
end

T['declines an unterminated string'] = function()
  MiniTest.expect.equality(
    analyze('const x = "hello', ctx),
    { kind = 'decline', reason = 'unterminated string' }
  )
end

-- Issue 03: terminator placement. Only a `;` at delimiter-depth 0 at the code
-- tail counts as already-terminated.

-- The `;` in a for-header sit at depth 1 (inside the paren), so they never read
-- as "already terminated". Issue 04: `for` is a block head, so this completes by
-- closing the paren and opening a block — the header `;` still don't terminate it.
T['for-header semicolons are not terminators'] = function()
  MiniTest.expect.equality(
    analyze('for (let i = 0; i < n; i++', ctx),
    { kind = 'complete', opens_block = true, insert = ') {', body = '  ', close = '}' }
  )
end

-- Issue 03: closers/`;` splice before a trailing comment so it survives.
T['completes before a trailing line comment'] = function()
  MiniTest.expect.equality(
    analyze('const x = getValue(a // grab it', ctx),
    { kind = 'complete', insert = ');', opens_block = false, tail = ' // grab it' }
  )
end

-- Whitespace before the comment is preserved verbatim (spacing is a formatter's
-- job, not fullstop's), so the spec's two-space example keeps its two spaces.
T['preserves the original spacing before a trailing comment'] = function()
  MiniTest.expect.equality(
    analyze('const x = getValue(a  // grab it', ctx),
    { kind = 'complete', insert = ');', opens_block = false, tail = '  // grab it' }
  )
end

-- A statement already terminated at depth 0, with a trailing comment, advances —
-- the comment must not hide the `;` and cause a double terminator.
T['a terminated statement with a trailing comment advances'] = function()
  MiniTest.expect.equality(analyze('const x = 1; // done', ctx), { kind = 'advance' })
end

-- Issue 04, cluster B: a control-flow head opens an idempotent `{ }` block —
-- closers, then ` {`; the body line lands at `base + unit` (cursor there) and the
-- closing `}` at `base`. No trailing `;`.
T['opens a block for an if head, closing its condition'] = function()
  MiniTest.expect.equality(
    analyze('if (cond', ctx),
    { kind = 'complete', opens_block = true, insert = ') {', body = '  ', close = '}' }
  )
end

-- Table-driven coverage of every cluster-B construct. Each head closes its
-- condition (if any) and opens a block: cursor at `base + unit`, `}` at `base`,
-- no `;`. The compared tuples carry the input so a failure names its case.
T['opens a block for each control-flow construct'] = function()
  local block = function(insert)
    return { kind = 'complete', opens_block = true, insert = insert, body = '  ', close = '}' }
  end
  local cases = {
    { 'if (cond', ') {' },
    { 'switch (v', ') {' },
    { 'for (const x of arr', ') {' },
    { 'for (const k in obj', ') {' },
    { 'while (go', ') {' },
    { 'try', ' {' },
    { 'else', ' {' },
    { '} else if (x', ') {' },
    { 'catch (e', ') {' },
    { 'finally', ' {' },
  }
  for _, c in ipairs(cases) do
    MiniTest.expect.equality({ c[1], analyze(c[1], ctx) }, { c[1], block(c[2]) })
  end
end

-- Idempotent: a `{` already typed is reused (block-vs-object lookbehind), so
-- firing twice never doubles the brace — the head-line insert adds nothing.
-- (Contrast the object-literal `{` in `const o = { a: 1` above, which closes to
-- ` };` — the head keyword is what tells block from object.)
T['reuses an already-typed block brace instead of doubling it'] = function()
  MiniTest.expect.equality(
    analyze('if (cond) {', ctx),
    { kind = 'complete', opens_block = true, insert = '', body = '  ', close = '}' }
  )
end

-- The do-while tail `} while (...)` terminates — it is NOT a block head.
T['a } while tail terminates instead of opening a block'] = function()
  MiniTest.expect.equality(
    analyze('} while (done', ctx),
    { kind = 'complete', insert = ');', opens_block = false }
  )
end

-- Issue 05, cluster C: a declaration head opens a block like cluster B, but with
-- NO trailing `;` (a declaration is self-terminating). Reuses open_block, so the
-- body/close geometry matches B; the closing `}` carries no `;`.
T['opens a block for a function declaration, no semicolon'] = function()
  MiniTest.expect.equality(
    analyze('function foo(a', ctx),
    { kind = 'complete', opens_block = true, insert = ') {', body = '  ', close = '}' }
  )
end

-- Table-driven coverage of every cluster-C block form. Each opens a block (cursor
-- at `base + unit`); the closing `}` carries a `;` iff the construct is an
-- assigned expression (`const f = …`), and `∅` for a declaration. `close` is the
-- only axis that varies between the two, so it rides in each row.
T['opens a declaration/expression block for each cluster-C form'] = function()
  local cblock = function(insert, close)
    return { kind = 'complete', opens_block = true, insert = insert, body = '  ', close = close }
  end
  local cases = {
    -- declarations: self-terminating, no `;`
    { 'function foo(a', ') {', '}' },
    { 'async function foo(a', ') {', '}' },
    { 'function* gen(a', ') {', '}' },
    { 'export function foo(a', ') {', '}' },
    { 'export default class Bar', ' {', '}' },
    { 'class Bar extends Foo', ' {', '}' },
    -- assigned expressions: keep the statement's `;`
    { 'const f = function(a', ') {', '};' },
    { 'const f = async function(a', ') {', '};' },
    { 'const C = class', ' {', '};' },
    { 'const f = () =>', ' {', '};' }, -- bare arrow, no body yet
    { 'const f = () => {', '', '};' }, -- `=> {` reuses the typed brace
  }
  for _, c in ipairs(cases) do
    MiniTest.expect.equality({ c[1], analyze(c[1], ctx) }, { c[1], cblock(c[2], c[3]) })
  end
end

-- The other two arms of the `=>` rule: an expression body is cluster A (balance +
-- terminate, no block), whether it's a plain expression, a parenthesised one, or
-- an object return `=> ({…})`.
T['an arrow with an expression body terminates instead of opening a block'] = function()
  local aterm = function(insert)
    return { kind = 'complete', insert = insert, opens_block = false }
  end
  local cases = {
    { 'const f = (x) => x + 1', ';' },
    { 'const f = () => (', ');' },
    { 'const f = () => ({', ' });' },
  }
  for _, c in ipairs(cases) do
    MiniTest.expect.equality({ c[1], analyze(c[1], ctx) }, { c[1], aterm(c[2]) })
  end
end

-- A bare call `foo(a` — e.g. a method inside a class body — is NOT read as a
-- declaration: analyze is context-free, so it completes as a call (`;`), never a
-- block. Documented v2 gap: class members need class-body context we don't have.
T['a bare call stays a call, not a declaration (class-member v2 gap)'] = function()
  MiniTest.expect.equality(
    analyze('foo(a', ctx),
    { kind = 'complete', insert = ');', opens_block = false }
  )
end

-- Issue 06: `semicolons = false` (ASI / `semi: false` projects). analyze takes
-- the config as a third argument and appends no `;` anywhere — it still balances
-- delimiters and still opens blocks, it just never terminates.
local no_semi = { semicolons = false }

T['semicolons = false closes delimiters without a terminator'] = function()
  MiniTest.expect.equality(
    analyze('const x = foo(a, b', ctx, no_semi),
    { kind = 'complete', insert = ')', opens_block = false }
  )
end

-- With no terminator to add, a balanced statement has nothing left to finish —
-- so it reads as already-complete and advances (the criterion that makes the
-- option usable: firing on a finished line still opens a fresh one).
T['semicolons = false advances on a balanced statement with no terminator'] = function()
  MiniTest.expect.equality(analyze('const x = 1', ctx, no_semi), { kind = 'advance' })
end

-- An explicit `;` the user typed is still an already-complete statement.
T['semicolons = false still advances on an explicitly terminated statement'] = function()
  MiniTest.expect.equality(analyze('const x = 1;', ctx, no_semi), { kind = 'advance' })
end

-- The assigned-expression `;` on a cluster-C closing brace is a terminator too,
-- so it goes as well: `};` becomes `}`. Declarations and cluster B are unchanged
-- (they never carried one), and blocks still open.
T['semicolons = false drops the assigned-expression brace terminator'] = function()
  MiniTest.expect.equality(
    analyze('const f = () =>', ctx, no_semi),
    { kind = 'complete', opens_block = true, insert = ' {', body = '  ', close = '}' }
  )
end

T['semicolons = false leaves control-flow blocks unchanged'] = function()
  MiniTest.expect.equality(
    analyze('if (cond', ctx, no_semi),
    { kind = 'complete', opens_block = true, insert = ') {', body = '  ', close = '}' }
  )
end

-- The trailing comment still rides after the closers, with no `;` before it.
T['semicolons = false completes before a trailing comment'] = function()
  MiniTest.expect.equality(
    analyze('const x = getValue(a // grab it', ctx, no_semi),
    { kind = 'complete', insert = ')', opens_block = false, tail = ' // grab it' }
  )
end

-- Decline outranks the option: an unsafe lex is still untouchable.
T['semicolons = false still declines an ambiguous regex'] = function()
  MiniTest.expect.equality(
    analyze('const r = /a(b/', ctx, no_semi),
    { kind = 'decline', reason = 'ambiguous regex or division' }
  )
end

-- Issue 05, the body slot. `analyze` takes the slot state as a fourth argument
-- (`'none'` | `'statement'` | `'block'` | `'unknown'`); nil reads as `'none'`, so
-- every test above is unaffected. A filled slot means the construct already has a
-- body, so no block opens — the prefix keyword no longer decides that on its own.

-- A body slot filled with an unbraced statement: the construct is complete, so the
-- verdict is whatever cluster A makes of the whole text. Already terminated →
-- Advance; missing its `;` → terminate. Never a block.
T['a statement body slot terminates instead of opening a block'] = function()
  local cases = {
    { 'if (test) foo();', { kind = 'advance' } },
    { 'while (a) foo();', { kind = 'advance' } },
    { 'for (const x of y) foo();', { kind = 'advance' } },
    { 'if (a) {\n} else foo();', { kind = 'advance' } },
    { 'if (!a) return', { kind = 'complete', insert = ';', opens_block = false } },
    { 'if (a) x = { b: 1 }', { kind = 'complete', insert = ';', opens_block = false } },
  }
  for _, c in ipairs(cases) do
    MiniTest.expect.equality({ c[1], analyze(c[1], ctx, nil, 'statement') }, { c[1], c[2] })
  end
end

-- A body slot filled with a closed block: the construct is self-terminating when
-- its own keyword implies the terminator (control-flow head or declaration), so it
-- advances. An assigned expression still owes the statement's `;`.
T['a block body slot advances, unless the construct is an assigned expression'] = function()
  local cases = {
    { 'if (a) {\n  x;\n}', { kind = 'advance' } },
    { 'if (a) {\n} else {\n}', { kind = 'advance' } },
    { 'function f() {\n  x;\n}', { kind = 'advance' } },
    { 'export function f() {\n  x;\n}', { kind = 'advance' } },
    { 'class C {\n  m() {}\n}', { kind = 'advance' } },
    { 'switch (v) {\n  case 1: break;\n}', { kind = 'advance' } },
    { 'try {\n} catch (e) {\n}', { kind = 'advance' } },
    {
      'const f = function () {\n  x;\n}',
      { kind = 'complete', insert = ';', opens_block = false },
    },
    { 'const C = class {\n  m() {}\n}', { kind = 'complete', insert = ';', opens_block = false } },
    { 'const f = () => {\n  x;\n}', { kind = 'complete', insert = ';', opens_block = false } },
  }
  for _, c in ipairs(cases) do
    MiniTest.expect.equality({ c[1], analyze(c[1], ctx, nil, 'block') }, { c[1], c[2] })
  end
end

-- A self-terminating construct whose block is still open closes the brace and adds
-- NO terminator — `if (a) { foo();` wants ` }`, not ` } {` and not ` };`.
T['a block body slot still closes an unclosed brace, without a terminator'] = function()
  MiniTest.expect.equality(
    analyze('if (a) { foo();', ctx, nil, 'block'),
    { kind = 'complete', insert = ' }', opens_block = false }
  )
end

-- Step 2 of the decision order, and the one place the grammar and the wanted
-- behaviour genuinely disagree: treesitter parses the lone `{` of `if (cond) {` as
-- a statement filling the consequence, but the brace is the block the user is
-- opening. Reuse outranks the slot, so firing twice still never doubles the brace.
T['an already-typed block brace outranks a filled body slot'] = function()
  local reuse = { kind = 'complete', opens_block = true, insert = '', body = '  ', close = '}' }
  MiniTest.expect.equality(analyze('if (cond) {', ctx, nil, 'statement'), reuse)
  MiniTest.expect.equality(analyze('function f() {', ctx, nil, 'statement'), reuse)
end

-- An ERROR anchor carries no body field, so `locate` says `'unknown'` and analyze
-- falls back to text: is the head's condition balanced with code after it? The
-- guard-clause idiom is the shape that needs this — `'none'` would open a block.
T['an unknown body slot reads the head from text'] = function()
  local cases = {
    -- filled: the condition closed and a body follows
    { "if (!a) throw new Error('nope'", { kind = 'complete', insert = ');', opens_block = false } },
    { 'while (a) foo(', { kind = 'complete', insert = ');', opens_block = false } },
    -- empty: the head itself is still unfinished
    {
      'if (cond',
      { kind = 'complete', opens_block = true, insert = ') {', body = '  ', close = '}' },
    },
    { 'try', { kind = 'complete', opens_block = true, insert = ' {', body = '  ', close = '}' } },
    { 'else', { kind = 'complete', opens_block = true, insert = ' {', body = '  ', close = '}' } },
  }
  for _, c in ipairs(cases) do
    MiniTest.expect.equality({ c[1], analyze(c[1], ctx, nil, 'unknown') }, { c[1], c[2] })
  end
end

-- The text check recurses through `else`: there IS code after the keyword, but it
-- is another block head, so the slot is empty and a block opens. Without the
-- recursion `} else if (x` would complete to `);`.
T['the unknown text check recurses through else'] = function()
  local block = function(insert)
    return { kind = 'complete', opens_block = true, insert = insert, body = '  ', close = '}' }
  end
  MiniTest.expect.equality(analyze('} else if (x', ctx, nil, 'unknown'), block(') {'))
  MiniTest.expect.equality(analyze('} else', ctx, nil, 'unknown'), block(' {'))
  MiniTest.expect.equality(analyze('} else foo();', ctx, nil, 'unknown'), { kind = 'advance' })
end

-- A filled slot on a non-head statement changes nothing: cluster A never consulted
-- the keyword, so the fourth argument is inert there.
T['a filled body slot leaves an ordinary statement alone'] = function()
  MiniTest.expect.equality(
    analyze('const x = foo(a, b', ctx, nil, 'statement'),
    { kind = 'complete', insert = ');', opens_block = false }
  )
end

-- Decline still outranks everything: an unsafe lex is untouchable whatever the slot.
T['a filled body slot still declines an ambiguous regex'] = function()
  MiniTest.expect.equality(
    analyze('const r = /a(b/', ctx, nil, 'block'),
    { kind = 'decline', reason = 'ambiguous regex or division' }
  )
end

-- semicolons = false empties the terminator here too: a statement slot that would
-- have gained a `;` now has nothing left to add, so it advances.
T['semicolons = false advances on a statement body slot with no terminator'] = function()
  MiniTest.expect.equality(
    analyze('if (!a) return', ctx, no_semi, 'statement'),
    { kind = 'advance' }
  )
end

return T
