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

  -- verdict.kind == 'complete', opens_block = false (cluster A): splice the
  -- closers + terminator, then drop a fresh line below, all in one edit.
  -- Block-opening arrives in tickets 04-05.
  --
  -- A trailing comment (verdict.tail) is re-emitted after the insertion, so the
  -- closers/`;` land before it and it survives. tail sits at the end of the end
  -- line, so its byte length is exactly how far back from end_col to splice.
  --
  -- This spans the comment's bytes, but re-emits them verbatim (tail is a literal
  -- suffix of the region), so ADR-0001 ("never eat your code") holds: the comment
  -- is preserved exactly. Spanning it is what keeps the whole edit one undo step.
  local row, col = region.end_row, region.end_col
  local tail = verdict.tail or ''
  vim.api.nvim_buf_set_text(
    buf,
    row,
    col - #tail,
    row,
    col,
    { verdict.insert .. tail, region.indent_context.base }
  )
  insert_at_line_end(row + 2)
end

return M
