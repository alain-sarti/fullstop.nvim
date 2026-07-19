-- Expose <Plug>(CompleteStatement) for insert + normal mode; the user maps their
-- own key to it. <Cmd> runs the function without leaving insert mode; a
-- normal-mode fire lands in insert via apply.
if vim.g.loaded_fullstop then
  return
end
vim.g.loaded_fullstop = true

vim.keymap.set(
  { 'i', 'n' },
  '<Plug>(CompleteStatement)',
  '<Cmd>lua require("fullstop").complete_statement()<CR>',
  { silent = true, desc = 'fullstop: complete current statement' }
)
