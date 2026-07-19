-- Isolated, reproducible test bootstrap for fullstop.nvim.
-- Resets the runtimepath to the bare Neovim runtime, then adds exactly:
--   * the plugin under test,
--   * mini.nvim (provides mini.test),
--   * the treesitter parsers from the standard Neovim data dir (typescript, tsx).
-- so nothing from the developer's own config can leak into the suite.

vim.cmd('set runtimepath=$VIMRUNTIME')

local root = vim.fn.getcwd()

-- Plugin under test + its plugin/ mappings (needed for the <Plug> integration test,
-- which --noplugin would otherwise skip).
vim.opt.runtimepath:append(root)

-- mini.nvim (mini.test).
vim.opt.runtimepath:append(root .. '/deps/mini.nvim')

-- Treesitter parsers: prefer the repo-local build (`make parsers`), then fall
-- back to the developer's standard Neovim data dir.
vim.opt.runtimepath:append(root .. '/deps/parsers')
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/site')

-- Map the TS/TSX filetypes to their grammars so `get_parser` resolves them.
pcall(vim.treesitter.language.register, 'typescript', 'typescript')
pcall(vim.treesitter.language.register, 'tsx', 'typescriptreact')

require('mini.test').setup()

vim.cmd('runtime plugin/fullstop.lua')
