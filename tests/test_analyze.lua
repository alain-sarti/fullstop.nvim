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

return T
