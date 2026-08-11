-- Locate tests (Seam A): call `locate` against a real buffer + treesitter and
-- assert the region it hands `analyze` — the statement the cursor sits in, never
-- the construct that encloses it (issue 01). Runs in-process on a scratch
-- buffer: `locate` takes its cursor as an argument, so no window is involved.

local eq = MiniTest.expect.equality
local locate = require('fullstop.locate')

local T = MiniTest.new_set()

-- Locate from `cursor` (1-based row, 0-based col) in a throwaway buffer holding
-- `lines`. `bo` overrides its indent options; filetype is set last so the
-- FileType event (and treesitter) see the final contents.
local function region_for(lines, cursor, bo)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for option, value in pairs(bo or {}) do
    vim.bo[buf][option] = value
  end
  vim.bo[buf].filetype = 'typescript'

  local region = locate.locate(buf, cursor)
  vim.api.nvim_buf_delete(buf, { force = true })
  return region
end

-- The whole region contract in one table: the text `analyze` reasons about, the
-- rows/cols `apply` splices at, and the indent the block/fresh line lands on.
local function shape(region)
  return {
    text = region.text,
    start_row = region.start_row,
    start_col = region.start_col,
    end_row = region.end_row,
    end_col = region.end_col,
    base = region.indent_context.base,
  }
end

T['a top-level statement anchors to itself'] = function()
  local r = region_for({ 'const x = foo(a, b' }, { 1, 10 })
  eq(shape(r), {
    text = 'const x = foo(a, b',
    start_row = 0,
    start_col = 0,
    end_row = 0,
    end_col = 18,
    base = '',
  })
end

T['an indented top-level statement keeps its own indent as base'] = function()
  local r = region_for({ '  const y = bar(1' }, { 1, 8 })
  eq(shape(r), {
    text = 'const y = bar(1',
    start_row = 0,
    start_col = 2,
    end_row = 0,
    end_col = 17,
    base = '  ',
  })
end

-- The issue-01 repro and its siblings: one statement inside a real `{ }`. Every
-- fixture's enclosing construct is complete, so rise-to-root landed on it and
-- handed `analyze` the whole thing.
local NESTED = {
  {
    label = 'a function body',
    lines = { 'function outer() {', '  const x = getValue(a, b', '}' },
    cursor = { 2, 24 },
    want = {
      text = 'const x = getValue(a, b',
      start_row = 1,
      start_col = 2,
      end_row = 1,
      end_col = 25,
      base = '  ',
    },
  },
  {
    label = 'an arrow body',
    lines = { 'const f = () => {', '  const y = bar(1, 2', '}' },
    cursor = { 2, 10 },
    want = {
      text = 'const y = bar(1, 2',
      start_row = 1,
      start_col = 2,
      end_row = 1,
      end_col = 20,
      base = '  ',
    },
  },
  {
    label = 'an if body',
    lines = { 'if (cond) {', '  const x = foo(a', '}' },
    cursor = { 2, 10 },
    want = {
      text = 'const x = foo(a',
      start_row = 1,
      start_col = 2,
      end_row = 1,
      end_col = 17,
      base = '  ',
    },
  },
  {
    label = 'a for body',
    lines = { 'for (const a of b) {', '  const x = foo(a', '}' },
    cursor = { 2, 10 },
    want = {
      text = 'const x = foo(a',
      start_row = 1,
      start_col = 2,
      end_row = 1,
      end_col = 17,
      base = '  ',
    },
  },
  {
    label = 'a while body',
    lines = { 'while (a) {', '  const x = foo(a', '}' },
    cursor = { 2, 10 },
    want = {
      text = 'const x = foo(a',
      start_row = 1,
      start_col = 2,
      end_row = 1,
      end_col = 17,
      base = '  ',
    },
  },
  {
    label = 'a class method body',
    lines = { 'class C {', '  m() {', '    const v = call(x', '  }', '}' },
    cursor = { 3, 14 },
    want = {
      text = 'const v = call(x',
      start_row = 2,
      start_col = 4,
      end_row = 2,
      end_col = 20,
      base = '    ',
    },
  },
  {
    label = 'a switch body',
    lines = { 'switch (a) {', '  case 1:', '    const z = baz(q', '}' },
    cursor = { 3, 14 },
    want = {
      text = 'const z = baz(q',
      start_row = 2,
      start_col = 4,
      end_row = 2,
      end_col = 19,
      base = '    ',
    },
  },
  {
    label = 'two blocks deep',
    lines = { 'function o() {', '  if (a) {', '    const z = baz(q', '  }', '}' },
    cursor = { 3, 14 },
    want = {
      text = 'const z = baz(q',
      start_row = 2,
      start_col = 4,
      end_row = 2,
      end_col = 19,
      base = '    ',
    },
  },
}

for _, case in ipairs(NESTED) do
  T['anchors to the statement nested inside ' .. case.label] = function()
    eq(shape(region_for(case.lines, case.cursor)), case.want)
  end
end

-- "The cursor selects, never bounds" (CONTEXT.md) holds inside a block too: the
-- region spans the whole wrapped statement, and `base` tracks its head line.
T['a multi-line nested statement is one whole region'] = function()
  local r = region_for({ 'function o() {', '  const x = foo(', '    a, b', '}' }, { 3, 6 })
  eq(shape(r), {
    text = 'const x = foo(\n    a, b',
    start_row = 1,
    start_col = 2,
    end_row = 2,
    end_col = 8,
    base = '  ',
  })
end

-- A statement inside a `case` arm anchors to the statement, not to the arm.
T['a statement inside a switch case anchors to the statement'] = function()
  local r = region_for({ 'switch (a) {', '  case 1:', '    log(x);', '    break;', '}' }, { 3, 4 })
  eq(shape(r), {
    text = 'log(x);',
    start_row = 2,
    start_col = 4,
    end_row = 2,
    end_col = 11,
    base = '    ',
  })
end

-- No statement at the cursor: the position sits in a container, between
-- statements. Nil is the Advance signal — never the enclosing construct.
T['a blank line inside a block has no statement'] = function()
  eq(region_for({ 'function o() {', '  ', '}' }, { 2, 0 }), nil)
end

T['a blank buffer has no statement'] = function()
  eq(region_for({ '' }, { 1, 0 }), nil)
end

-- `unit` is the other half of the indent contract, and `locate` is its only
-- producer: one indent level, read from the buffer's own options.
T['the indent unit follows the buffer indent options'] = function()
  local spaces = region_for({ 'const x = foo(a' }, { 1, 10 }, { expandtab = true, shiftwidth = 3 })
  eq(spaces.indent_context.unit, '   ')

  local tabs = region_for({ 'const x = foo(a' }, { 1, 10 }, { expandtab = false })
  eq(tabs.indent_context.unit, '\t')
end

-- Known residual, recorded in ADR-0002: when the broken statement's own
-- delimiters swallow the enclosing brace, the tree holds no statement node under
-- a container and the anchor is the whole construct. Pinned as it behaves today,
-- NOT as desired — the fallback-ladder ticket is what flips these.
T['an unclosed brace swallows the enclosing brace, anchoring the construct'] = function()
  local r = region_for({ 'function o() {', '  const p = fn({ a: 1', '}' }, { 2, 18 })
  eq(r.text, 'function o() {\n  const p = fn({ a: 1\n}')
end

T['a tail after the block collapses the construct into one anchor'] = function()
  local r = region_for({ 'try {', '  const x = foo(a', '} catch (e) {}' }, { 2, 16 })
  eq(r.text, 'try {\n  const x = foo(a\n} catch (e) {}')
end

return T
