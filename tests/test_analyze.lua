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

return T
