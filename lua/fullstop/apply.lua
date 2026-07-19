-- fullstop: the Neovim shell that executes a verdict. Kept dumb — one buffer
-- edit, then cursor + insert mode. The whole change is a single
-- nvim_buf_set_text call, so it is one undo step (no :undojoin needed).

local M = {}

-- Land in insert mode at the end of the cursor's line, from whatever mode we
-- were fired in (startinsert! == `A`). Every issue-01 outcome ends on a fresh,
-- indent-only line, so appending at its end is exactly the target spot.
local function insert_at_line_end(row_1based)
  vim.api.nvim_win_set_cursor(0, { row_1based, 0 })
  vim.cmd('startinsert!')
end

local function line_len(buf, row)
  return #(vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or '')
end

-- Open a fresh line below `row` (0-based) carrying `base` indent, as one edit.
local function open_below(buf, row, base)
  local eol = line_len(buf, row)
  vim.api.nvim_buf_set_text(buf, row, eol, row, eol, { '', base })
  insert_at_line_end(row + 2)
end

function M.apply(buf, cursor, region, verdict)
  if verdict.kind == 'advance' then
    if region then
      open_below(buf, region.end_row, region.indent_context.base)
    else
      local row = cursor[1] - 1
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
      open_below(buf, row, line:match('^%s*'))
    end
    return
  end

  -- verdict.kind == 'complete'. Issue 01 only produces opens_block = false
  -- (cluster A): splice the closers + terminator, then drop a fresh line below,
  -- all in one edit. Block-opening arrives in tickets 04-05.
  local row, col = region.end_row, region.end_col
  vim.api.nvim_buf_set_text(buf, row, col, row, col, { verdict.insert, region.indent_context.base })
  insert_at_line_end(row + 2)
end

return M
