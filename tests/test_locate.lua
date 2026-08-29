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

-- Issue 05: the body slot `locate` resolves from the grammar (ADR-0003) — the
-- fourth thing it tells `analyze`, and the only shape information analyze gets.
local function body_for(lines, cursor)
  local r = region_for(lines, cursor)
  return r and r.body
end

-- The position contract plus the slot, for the cases where the two interact.
local function shape_and_slot(lines, cursor)
  local r = region_for(lines, cursor)
  local s = shape(r)
  s.body = r.body
  return s
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

-- Issue 05: what the grammar says about the construct's body slot. `analyze`'s
-- keyword classifiers cannot answer this — `if (test) foo();` and `if (test)` both
-- start with `if` — so `locate` reads it off the tree instead.
local SLOTS = {
  -- Filled by an unbraced statement on the head's own line.
  { 'a same-line if body', { 'if (test) foo();' }, { 1, 4 }, 'statement' },
  { 'a same-line while body', { 'while (a) foo();' }, { 1, 4 }, 'statement' },
  { 'a same-line for body', { 'for (const x of xs) foo();' }, { 1, 4 }, 'statement' },
  { 'a guard-clause return', { 'if (!a) return' }, { 1, 4 }, 'statement' },
  { 'a same-line else body', { 'if (a) {', '} else foo();' }, { 2, 3 }, 'statement' },
  -- The field walk outranks the positional check: the block belongs to an
  -- argument, not to the `if`, so the slot is the whole call statement.
  { 'a body holding an arrow block', { 'if (a) foo(() => { })' }, { 1, 3 }, 'statement' },
  -- Filled by a braced body, closed or not.
  { 'a closed if block', { 'if (a) {', '  foo();', '}' }, { 1, 3 }, 'block' },
  { 'an unclosed if block', { 'if (a) { foo();' }, { 1, 3 }, 'block' },
  { 'a function body', { 'function f() {', '  foo();', '}' }, { 1, 3 }, 'block' },
  { 'a class body', { 'class C {', '  m() {}', '}' }, { 1, 3 }, 'block' },
  { 'a switch body', { 'switch (v) {', '  case 1:', '}' }, { 1, 3 }, 'block' },
  { 'a trailing catch body', { 'try {', '} catch (e) {', '}' }, { 1, 1 }, 'block' },
  -- Wrapper anchors carry no body field of their own; the positional check finds
  -- the block that ends where the statement does.
  { 'an exported function body', { 'export function f() {', '  foo();', '}' }, { 1, 10 }, 'block' },
  { 'an assigned function body', { 'const f = function () {', '}' }, { 1, 10 }, 'block' },
  { 'an assigned class body', { 'const C = class {', '}' }, { 1, 10 }, 'block' },
  { 'an assigned arrow body', { 'const f = () => {', '}' }, { 1, 10 }, 'block' },
  -- Nothing filled: an ordinary statement, and the do-while whose `{ }` is not
  -- the trailing slot (its condition is).
  { 'a complete statement', { 'foo();' }, { 1, 1 }, 'none' },
  { 'a function signature', { 'function f({ a })' }, { 1, 10 }, 'none' },
  { 'a do-while tail', { 'do {', '} while (a)' }, { 1, 1 }, 'none' },
  -- An ERROR anchor has no fields at all, so the grammar cannot say.
  { 'an unfinished condition', { 'if (cond' }, { 1, 4 }, 'unknown' },
  { 'an unfinished guard clause', { "if (!a) throw new Error('nope'" }, { 1, 4 }, 'unknown' },
  { 'an unfinished else-if', { 'if (a) {', '} else if (x' }, { 2, 9 }, 'unknown' },
  { 'an unfinished plain statement', { 'const x = foo(a, b' }, { 1, 10 }, 'unknown' },
}

for _, case in ipairs(SLOTS) do
  T['reports the body slot for ' .. case[1]] = function()
    eq({ case[1], body_for(case[2], case[3]) }, { case[1], case[4] })
  end
end

-- The head cap (issue 05): a body on a later line is not part of the head the
-- user is completing, so the region stops at the head's last code character and
-- the slot reads empty — `analyze` then opens the block on the head itself, and
-- `apply` pushes the orphaned body below the closing `}`.
local CAPS = {
  {
    label = 'an if head',
    lines = { 'if (test)', 'foo();' },
    cursor = { 1, 4 },
    want = {
      text = 'if (test)',
      start_row = 0,
      start_col = 0,
      end_row = 0,
      end_col = 9,
      base = '',
      body = 'none',
    },
  },
  {
    label = 'a nested if head',
    lines = { 'function f() {', '  if (test)', '  foo();', '}' },
    cursor = { 2, 6 },
    want = {
      text = 'if (test)',
      start_row = 1,
      start_col = 2,
      end_row = 1,
      end_col = 11,
      base = '  ',
      body = 'none',
    },
  },
  {
    label = 'a multi-line if head',
    lines = { 'if (', '  test', ')', 'foo();' },
    cursor = { 1, 0 },
    want = {
      text = 'if (\n  test\n)',
      start_row = 0,
      start_col = 0,
      end_row = 2,
      end_col = 1,
      base = '',
      body = 'none',
    },
  },
  {
    label = 'an else head',
    lines = { 'if (a) {', '} else', 'foo();' },
    cursor = { 2, 3 },
    want = {
      text = 'if (a) {\n} else',
      start_row = 0,
      start_col = 0,
      end_row = 1,
      end_col = 6,
      base = '',
      body = 'none',
    },
  },
  {
    label = 'a head separated by a blank line',
    lines = { 'if (test)', '', 'foo();' },
    cursor = { 1, 4 },
    want = {
      text = 'if (test)',
      start_row = 0,
      start_col = 0,
      end_row = 0,
      end_col = 9,
      base = '',
      body = 'none',
    },
  },
  {
    -- The cap lands past the trailing comment, which `analyze` hands back as
    -- `tail` so the ` {` still splices in front of it.
    label = 'a head with a trailing comment',
    lines = { 'if (test) // check', 'foo();' },
    cursor = { 1, 4 },
    want = {
      text = 'if (test) // check',
      start_row = 0,
      start_col = 0,
      end_row = 0,
      end_col = 18,
      base = '',
      body = 'none',
    },
  },
}

for _, case in ipairs(CAPS) do
  T['caps the region at ' .. case.label] = function()
    eq(shape_and_slot(case.lines, case.cursor), case.want)
  end
end

-- Fired *on* the orphaned body, the body is its own statement (the cursor
-- selects), so `locate` re-anchors onto it instead of capping the head above.
T['a cursor on the body line re-anchors onto the body'] = function()
  eq(shape_and_slot({ 'if (test)', 'foo();' }, { 2, 2 }), {
    text = 'foo();',
    start_row = 1,
    start_col = 0,
    end_row = 1,
    end_col = 6,
    base = '',
    body = 'none',
  })
end

T['a cursor on a nested else body re-anchors onto the body'] = function()
  eq(shape_and_slot({ 'function f() {', '  if (a) {', '  } else', '  foo();', '}' }, { 4, 4 }), {
    text = 'foo();',
    start_row = 3,
    start_col = 2,
    end_row = 3,
    end_col = 8,
    base = '  ',
    body = 'none',
  })
end

return T
