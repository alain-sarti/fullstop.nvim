-- fullstop: public API + wiring. setup() config, and complete_statement() which
-- threads locate -> analyze -> apply behind the filetype guard, notifying on
-- Decline (which never touches the buffer).

local analyze = require('fullstop.analyze')
local locate = require('fullstop.locate')
local apply = require('fullstop.apply')

local M = {}

M.config = {
  filetypes = { 'typescript', 'typescriptreact' },
  semicolons = true,
}

function M.setup(opts)
  M.config = vim.tbl_extend('force', M.config, opts or {})
end

local function supported(ft)
  return vim.tbl_contains(M.config.filetypes, ft)
end

function M.complete_statement()
  local buf = vim.api.nvim_get_current_buf()
  if not supported(vim.bo[buf].filetype) then
    vim.notify('fullstop: unsupported filetype', vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local region = locate.locate(buf, cursor)
  local verdict = region and analyze.analyze(region.text, region.indent_context)
    or { kind = 'advance' }

  if verdict.kind == 'decline' then
    vim.notify('fullstop: ' .. verdict.reason, vim.log.levels.WARN)
    return
  end

  apply.apply(buf, cursor, region, verdict)
end

return M
