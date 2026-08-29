-- Integration tests (Seam B): fire require('fullstop').complete_statement()
-- against a real buffer + treesitter in a child Neovim, asserting the resulting
-- buffer lines, cursor position, and mode. Covers locate -> analyze -> apply,
-- the <Plug> mapping in both modes, and the filetype guard.

local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'tests/minimal_init.lua' })
      -- Map a real key to the <Plug> so we can drive it with type_keys.
      child.lua([[vim.keymap.set({ 'i', 'n' }, '<C-j>', '<Plug>(CompleteStatement)')]])
    end,
    post_once = child.stop,
  },
})

-- Fill the current buffer and place the cursor. Filetype is set last so the
-- FileType event (and treesitter) see the final contents.
local function setup_buffer(ft, lines, cursor)
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  child.api.nvim_win_set_cursor(0, cursor)
  child.lua('vim.bo.filetype = ...', { ft })
end

local function lines()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

-- The nesting matrix (issue 02) ---------------------------------------------
--
-- Issue 01 shipped green because every fixture here was a top-level statement —
-- the one shape where the buggy anchoring rule happened to be right. Some were
-- *indented*, which reads like nesting but, with no enclosing `{ }`, is still
-- top level; that is the false confidence this matrix removes.
--
-- A behaviour is written once, relative to its own statement: `lines` / `want`
-- carry no leading indent, and `cursor` / `want_cursor` are relative to the
-- statement's first line and to that indent. A shape wraps the statement in
-- enclosing lines and prefixes `indent` to each of its lines, so a further shape
-- costs one table entry instead of a copy of every case.

local SHAPES = {
  { label = 'at top level', before = {}, after = {}, indent = '' },
  {
    label = 'inside a function body',
    before = { 'function outer() {' },
    after = { '}' },
    indent = '  ',
  },
  {
    label = 'two blocks deep',
    before = { 'function outer() {', '  if (ready) {' },
    after = { '  }', '}' },
    indent = '    ',
  },
  {
    label = 'inside a class method body',
    before = { 'class C {', '  m() {' },
    after = { '  }', '}' },
    indent = '    ',
  },
}

local CASES = {
  -- Cluster A (issue 02): balance the delimiters, then terminate.
  {
    label = 'closes an open paren and terminates',
    lines = { 'const x = foo(a, b' },
    cursor = { 1, 10 },
    want = { 'const x = foo(a, b);', '' },
    want_cursor = { 2, 0 },
  },
  -- "The cursor selects, never bounds": a wrapped statement completes as one
  -- whole, and the fresh line follows its head-line indent.
  {
    label = 'completes a wrapped statement as one whole',
    lines = { 'const x = foo(', '  a, b' },
    cursor = { 2, 4 },
    want = { 'const x = foo(', '  a, b);', '' },
    want_cursor = { 3, 0 },
  },
  -- Issue 03: the insertion lands before a trailing comment, which survives.
  {
    label = 'completes before a trailing comment, preserving it',
    lines = { 'const x = getValue(a // grab it' },
    cursor = { 1, 12 },
    want = { 'const x = getValue(a); // grab it', '' },
    want_cursor = { 2, 0 },
  },
  -- Cluster B (issue 04): a control-flow head opens a `{ }` block at the
  -- statement indent.
  {
    label = 'opens a control-flow block',
    lines = { 'if (cond' },
    cursor = { 1, 4 },
    want = { 'if (cond) {', '  ', '}' },
    want_cursor = { 2, 2 },
  },
  -- `base` tracks the head line, not the physical line the block lands on.
  {
    label = 'opens a block for a wrapped head at the head-line indent',
    lines = { 'if (', '  cond' },
    cursor = { 2, 4 },
    want = { 'if (', '  cond) {', '  ', '}' },
    want_cursor = { 3, 2 },
  },
  -- Cluster C (issue 05): a declaration is self-terminating, an assigned arrow
  -- is not.
  {
    label = 'opens a declaration block with no terminator',
    lines = { 'function foo(a' },
    cursor = { 1, 5 },
    want = { 'function foo(a) {', '  ', '}' },
    want_cursor = { 2, 2 },
  },
  {
    label = 'opens an assigned arrow block with a terminated brace',
    lines = { 'const f = () =>' },
    cursor = { 1, 6 },
    want = { 'const f = () => {', '  ', '};' },
    want_cursor = { 2, 2 },
  },
  -- Advance: nothing to finish, so a fresh line below — the enclosing construct
  -- keeps its braces.
  {
    label = 'advances past an already-complete statement',
    lines = { 'const x = 1;' },
    cursor = { 1, 4 },
    want = { 'const x = 1;', '' },
    want_cursor = { 2, 0 },
  },
  -- "Blank", not "empty": every shape prefixes its indent, so the nested runs
  -- fire on an indent-only line. A bare empty line inside a block is the one
  -- nested shape the prefix rule can't express — asserted on its own below.
  {
    label = 'advances on a blank line',
    lines = { '' },
    cursor = { 1, 0 },
    want = { '', '' },
    want_cursor = { 2, 0 },
  },
  -- Issue 05: the body slot. A construct whose body is already there never opens
  -- a block, however block-ish its keyword — and a body on a *later* line is not
  -- part of the head, so the block opens on the head and the body is pushed below
  -- the closing `}` (additive per ADR-0001; the reported bug is the first case).
  {
    label = 'opens the block on the if head, not on the body below it',
    lines = { 'if (test)', 'foo();' },
    cursor = { 1, 4 },
    want = { 'if (test) {', '  ', '}', 'foo();' },
    want_cursor = { 2, 2 },
  },
  {
    label = 'opens the block on a wrapped head above its body',
    lines = { 'if (', '  test', ')', 'foo();' },
    cursor = { 1, 0 },
    want = { 'if (', '  test', ') {', '  ', '}', 'foo();' },
    want_cursor = { 4, 2 },
  },
  {
    label = 'opens the block in front of the head comment',
    lines = { 'if (test) // check', 'foo();' },
    cursor = { 1, 4 },
    want = { 'if (test) { // check', '  ', '}', 'foo();' },
    want_cursor = { 2, 2 },
  },
  -- Fired on the orphaned body instead, the body is its own statement: it is
  -- already complete, so this advances rather than reaching back up to the head.
  {
    label = 'advances when fired on the body below a head',
    lines = { 'if (test)', 'foo();' },
    cursor = { 2, 2 },
    want = { 'if (test)', 'foo();', '' },
    want_cursor = { 3, 0 },
  },
  -- A body on the head's own line: the slot is filled, so terminate or advance.
  {
    label = 'advances on a same-line if body',
    lines = { 'if (test) foo();' },
    cursor = { 1, 4 },
    want = { 'if (test) foo();', '' },
    want_cursor = { 2, 0 },
  },
  {
    label = 'terminates a guard clause instead of opening a block',
    lines = { 'if (!a) return' },
    cursor = { 1, 4 },
    want = { 'if (!a) return;', '' },
    want_cursor = { 2, 0 },
  },
  {
    label = 'advances on a same-line else body',
    lines = { 'if (a) {', '} else foo();' },
    cursor = { 2, 3 },
    want = { 'if (a) {', '} else foo();', '' },
    want_cursor = { 3, 0 },
  },
  -- A braced body: nothing left to add, and no terminator either — the construct
  -- carries its own end. (The *unclosed* brace is asserted outside the matrix: its
  -- `{` swallows the enclosing `}`, which no nested shape survives.)
  {
    label = 'advances on a closed control-flow block',
    lines = { 'if (a) {', '  foo();', '}' },
    cursor = { 1, 3 },
    want = { 'if (a) {', '  foo();', '}', '' },
    want_cursor = { 4, 0 },
  },
  -- ...unless the block belongs to an assigned expression, which still owes the
  -- statement's terminator.
  {
    label = 'terminates a closed assigned function block',
    lines = { 'const f = function () {', '}' },
    cursor = { 1, 10 },
    want = { 'const f = function () {', '};', '' },
    want_cursor = { 3, 0 },
  },
  -- Decline (issue 03): unreadable structure changes nothing and says why —
  -- inside a block too, where a stray splice would have landed on the
  -- enclosing construct.
  {
    label = 'declines on an ambiguous regex',
    lines = { 'const r = /a(b/' },
    cursor = { 1, 11 },
    want = { 'const r = /a(b/' },
    want_cursor = { 1, 11 },
    hints = { 'fullstop: ambiguous regex or division' },
  },
}

-- Wrap the statement lines in the shape's enclosing block(s), indenting each.
local function nest(shape, statement_lines)
  local out = vim.deepcopy(shape.before)
  for _, line in ipairs(statement_lines) do
    out[#out + 1] = shape.indent .. line
  end
  for _, line in ipairs(shape.after) do
    out[#out + 1] = line
  end
  return out
end

-- The same shift for a (1-based row, 0-based col) position.
local function nest_pos(shape, pos)
  return { #shape.before + pos[1], #shape.indent + pos[2] }
end

-- Collect the hints a fire shows, readable back as `_G.hints`.
local function capture_hints()
  child.lua([[
    _G.hints = {}
    vim.notify = function(msg) table.insert(_G.hints, msg) end
  ]])
end

local function run_case(shape, case)
  local before = nest(shape, case.lines)
  setup_buffer('typescript', before, nest_pos(shape, case.cursor))
  child.lua('vim.bo.expandtab = true vim.bo.shiftwidth = 2')
  capture_hints()
  child.type_keys('i', '<C-j>')

  local after = nest(shape, case.want)
  eq(lines(), after)
  eq(child.api.nvim_win_get_cursor(0), nest_pos(shape, case.want_cursor))
  eq(child.lua_get('_G.hints'), case.hints or {})

  -- One `u` reverts the whole completion, enclosing construct included. A fire
  -- that changed nothing (Decline) has no edit to revert, and `u` would undo the
  -- fixture's own buffer setup instead — its untouched buffer is asserted above.
  if not vim.deep_equal(before, after) then
    child.type_keys('<Esc>', 'u')
    eq(lines(), before)
  end
end

for _, shape in ipairs(SHAPES) do
  for _, case in ipairs(CASES) do
    T[case.label .. ' ' .. shape.label] = function()
      run_case(shape, case)
    end
  end
end

-- The matrix indents every statement line, so its blank-line case is always
-- indent-only. A bare empty line inside a block Advances too: with no statement
-- to anchor, `apply` takes the fresh line's indent from the cursor line, which
-- here is empty — and the enclosing braces stay put.
T['advances on a bare empty line inside a block'] = function()
  setup_buffer('typescript', { 'function outer() {', '', '}' }, { 2, 0 })
  child.type_keys('<C-j>')

  eq(lines(), { 'function outer() {', '', '', '}' })
  eq(child.api.nvim_win_get_cursor(0), { 3, 0 })
  eq(child.fn.mode(), 'i')
end

-- Issue 05: an open block brace closes, with no terminator — the `if` carries its
-- own end. Top level only: nested, this statement's `{` swallows the enclosing
-- `}`, so the tree holds no statement to anchor to and the fire Advances instead
-- (ADR-0002's swallowed-brace residual, whose fallback ladder is issue 04).
T['closes an open block brace without terminating'] = function()
  setup_buffer('typescript', { 'if (a) { foo();' }, { 1, 3 })
  child.type_keys('<C-j>')

  eq(lines(), { 'if (a) { foo(); }', '' })
  eq(child.api.nvim_win_get_cursor(0), { 2, 0 })
  eq(child.fn.mode(), 'i')
end

-- Shape-independent behaviour ------------------------------------------------
-- What the matrix doesn't vary: the mode a fire starts in, buffer options,
-- config, and the filetype guard. These run at top level, since nesting is
-- orthogonal to each of them.

T['a normal-mode fire completes and lands in insert'] = function()
  setup_buffer('typescript', { 'const x = foo(a, b' }, { 1, 10 })
  child.type_keys('<C-j>')

  eq(lines(), { 'const x = foo(a, b);', '' })
  eq(child.fn.mode(), 'i')
end

T['a non-typescript buffer is left untouched (filetype guard)'] = function()
  setup_buffer('lua', { 'local x = foo(a, b' }, { 1, 10 })
  child.type_keys('<C-j>')

  eq(lines(), { 'local x = foo(a, b' })
end

T['a plain TS statement completes in a tsx buffer (buffer parser)'] = function()
  setup_buffer('typescriptreact', { 'const x = foo(a, b' }, { 1, 10 })
  child.type_keys('<C-j>')

  eq(lines(), { 'const x = foo(a, b);', '' })
  eq(child.fn.mode(), 'i')
end

-- Issue 06: the TSX best-effort claim, pinned on the shape it matters for — a
-- component's arrow head. `locate` uses the buffer's own parser, so this runs
-- through the `tsx` grammar, and the TypeScript parts complete identically.
T['a component arrow head opens its block in a tsx buffer'] = function()
  setup_buffer('typescriptreact', { 'const App = () =>' }, { 1, 6 })
  child.lua('vim.bo.expandtab = true vim.bo.shiftwidth = 2')
  child.type_keys('<C-j>')

  eq(lines(), { 'const App = () => {', '  ', '};' })
  eq(child.api.nvim_win_get_cursor(0), { 2, 2 })
  eq(child.fn.mode(), 'i')
end

-- A tab-indented buffer: `unit` resolves to a tab, so the body line is one tab.
T['opens a block in a tab-indented buffer'] = function()
  setup_buffer('typescript', { 'if (cond' }, { 1, 4 })
  child.lua('vim.bo.expandtab = false vim.bo.shiftwidth = 0 vim.bo.tabstop = 4')
  child.type_keys('<C-j>')

  eq(lines(), { 'if (cond) {', '\t', '}' })
  eq(child.api.nvim_win_get_cursor(0), { 2, 1 })
  eq(child.fn.mode(), 'i')
end

-- Idempotent: firing on a head whose `{` is already typed reuses it (no doubled
-- brace), and the whole block reverts with a single undo.
T['reuses an already-typed brace, one undo'] = function()
  setup_buffer('typescript', { 'if (cond) {' }, { 1, 4 })
  child.lua('vim.bo.expandtab = true vim.bo.shiftwidth = 2')
  child.type_keys('i', '<C-j>')

  eq(lines(), { 'if (cond) {', '  ', '}' })
  eq(child.api.nvim_win_get_cursor(0), { 2, 2 })

  child.type_keys('<Esc>', 'u')
  eq(lines(), { 'if (cond) {' })
end

-- The do-while tail `} while (...)` terminates (cluster A), it does not block.
T['a } while tail terminates, not a block'] = function()
  setup_buffer('typescript', { '} while (done' }, { 1, 5 })
  child.type_keys('<C-j>')

  eq(lines(), { '} while (done);', '' })
  eq(child.fn.mode(), 'i')
end

-- Issue 06: `setup({ semicolons = false })` reaches analyze — delimiters still
-- close, but nothing is terminated.
T['semicolons = false closes delimiters and appends no terminator'] = function()
  child.lua([[require('fullstop').setup({ semicolons = false })]])
  setup_buffer('typescript', { 'const x = foo(a, b' }, { 1, 10 })
  child.type_keys('<C-j>')

  eq(lines(), { 'const x = foo(a, b)', '' })
  eq(child.fn.mode(), 'i')
end

-- ...and a balanced statement with no `;` is already complete, so it advances
-- instead of being "finished" with a terminator the project doesn't want.
T['semicolons = false advances on a balanced statement'] = function()
  child.lua([[require('fullstop').setup({ semicolons = false })]])
  setup_buffer('typescript', { 'const x = 1' }, { 1, 4 })
  child.type_keys('<C-j>')

  eq(lines(), { 'const x = 1', '' })
  eq(child.api.nvim_win_get_cursor(0), { 2, 0 })
  eq(child.fn.mode(), 'i')
end

-- The option reaches the block path too: an assigned arrow still opens its
-- block, but the closing brace is a bare `}` rather than `};`.
T['semicolons = false opens a block with an unterminated closing brace'] = function()
  child.lua([[require('fullstop').setup({ semicolons = false })]])
  setup_buffer('typescript', { 'const f = () =>' }, { 1, 6 })
  child.lua('vim.bo.expandtab = true vim.bo.shiftwidth = 2')
  child.type_keys('<C-j>')

  eq(lines(), { 'const f = () => {', '  ', '}' })
  eq(child.api.nvim_win_get_cursor(0), { 2, 2 })
  eq(child.fn.mode(), 'i')
end

-- Issue 06: a filetype outside the configured list Declines — the buffer is
-- untouched (no fake newline) and the hint says why.
T['an unsupported filetype declines with a hint, buffer untouched'] = function()
  setup_buffer('lua', { 'local x = foo(a, b' }, { 1, 10 })
  capture_hints()
  child.type_keys('<C-j>')

  eq(lines(), { 'local x = foo(a, b' })
  eq(child.lua_get('_G.hints'), { 'fullstop: unsupported filetype' })
end

-- `filetypes` is configurable: narrowing it turns a default-supported buffer
-- into a Decline, proving the guard reads config rather than a hardcoded list.
T['a filetype dropped from the configured list declines'] = function()
  child.lua([[require('fullstop').setup({ filetypes = { 'typescript' } })]])
  setup_buffer('typescriptreact', { 'const x = foo(a, b' }, { 1, 10 })
  child.type_keys('<C-j>')

  eq(lines(), { 'const x = foo(a, b' })
end

return T
