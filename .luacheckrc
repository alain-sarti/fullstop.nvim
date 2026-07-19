-- Luacheck configuration for fullstop.nvim.
-- Division of labour: stylua owns formatting and line width; luacheck owns
-- correctness (unused locals/args, shadowing, undefined globals).

std = 'luajit'
-- vim is read-write: plugins assign vim.g.* / vim.b.* (e.g. the load guard).
globals = { 'vim' }

-- stylua wraps code; leave line-length (and long comment lines) to it.
max_line_length = false

exclude_files = { 'deps' }

-- Tests drive a child Neovim where mini.test injects MiniTest as a global.
files['tests/'] = {
  read_globals = { 'MiniTest' },
}
