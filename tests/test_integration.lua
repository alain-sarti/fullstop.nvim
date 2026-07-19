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

T['completes an open paren from insert mode, one undo'] = function()
  setup_buffer('typescript', { 'const x = foo(a, b' }, { 1, 10 })
  child.type_keys('i', '<C-j>')

  eq(lines(), { 'const x = foo(a, b);', '' })
  eq(child.api.nvim_win_get_cursor(0), { 2, 0 })
  eq(child.fn.mode(), 'i')

  -- The whole completion reverts with a single `u`.
  child.type_keys('<Esc>', 'u')
  eq(lines(), { 'const x = foo(a, b' })
end

T['a normal-mode fire completes and lands in insert'] = function()
  setup_buffer('typescript', { 'const x = foo(a, b' }, { 1, 10 })
  child.type_keys('<C-j>')

  eq(lines(), { 'const x = foo(a, b);', '' })
  eq(child.fn.mode(), 'i')
end

T['preserves the head-line indentation on the fresh line'] = function()
  setup_buffer('typescript', { '  const y = bar(1' }, { 1, 8 })
  child.type_keys('<C-j>')

  eq(lines(), { '  const y = bar(1);', '  ' })
  eq(child.api.nvim_win_get_cursor(0), { 2, 2 })
end

T['an already-complete line advances (fresh line below)'] = function()
  setup_buffer('typescript', { 'const x = 1;' }, { 1, 4 })
  child.type_keys('<C-j>')

  eq(lines(), { 'const x = 1;', '' })
  eq(child.fn.mode(), 'i')
end

T['an empty line advances'] = function()
  setup_buffer('typescript', { '' }, { 1, 0 })
  child.type_keys('<C-j>')

  eq(lines(), { '', '' })
  eq(child.api.nvim_win_get_cursor(0), { 2, 0 })
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

-- Issue 03: an ambiguous regex declines — buffer untouched, a hint shown, no
-- fresh line. Capture vim.notify to prove the hint fires.
T['an ambiguous regex declines: buffer unchanged, hint shown, no fresh line'] = function()
  setup_buffer('typescript', { 'const r = /a(b/' }, { 1, 11 })
  child.lua([[
    _G.hints = {}
    vim.notify = function(msg) table.insert(_G.hints, msg) end
  ]])
  child.type_keys('<C-j>')

  eq(lines(), { 'const r = /a(b/' })
  eq(child.lua_get('_G.hints'), { 'fullstop: ambiguous regex or division' })
end

-- Issue 03: the insertion lands before a trailing comment, which survives.
T['completes before a trailing comment, preserving it'] = function()
  setup_buffer('typescript', { 'const x = getValue(a // grab it' }, { 1, 12 })
  child.type_keys('<C-j>')

  eq(lines(), { 'const x = getValue(a); // grab it', '' })
  eq(child.fn.mode(), 'i')
end

return T
