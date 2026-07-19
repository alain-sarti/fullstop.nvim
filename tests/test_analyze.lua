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

T['ignores a closer inside a line comment'] = function()
  MiniTest.expect.equality(
    analyze('foo(a // )', ctx),
    { kind = 'complete', insert = ');', opens_block = false }
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

return T
