-- fullstop: the treesitter shell. Given a buffer + cursor, walk up to the
-- enclosing statement region and hand `analyze` plain strings to reason about.
--
-- Treesitter is trusted for POSITION only (the spec's decision): an unfinished
-- line parses as an ERROR node, but that node's range still brackets the
-- statement, which is all locate needs. Every meaning decision happens later in
-- analyze on the raw text. locate is deliberately thin — it rises to the
-- statement node (a child of the tree root); a delimiter-based fallback ladder
-- for multi-line ERROR-tree mis-anchoring is a later ticket, added only if it
-- stings in practice.

local M = {}

local function get_line(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
end

-- One indent level, resolved from the buffer's own options. Consumed by block
-- tickets (04+); part of the indent_context contract from day one.
local function indent_unit(buf)
  local bo = vim.bo[buf]
  if not bo.expandtab then
    return '\t'
  end
  local width = bo.shiftwidth
  if width == 0 then
    width = bo.tabstop
  end
  return string.rep(' ', width)
end

-- Returns { text, start_row, start_col, end_row, end_col, indent_context } for the
-- statement the cursor sits in, or nil when there is none (empty line / no
-- statement). Rows and columns are 0-based; end_col is the splice point (just
-- past the last code character), so `apply` can insert there blindly.
function M.locate(buf, cursor)
  local row = cursor[1] - 1

  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return nil
  end
  local root = parser:parse()[1]:root()

  -- Clamp the column onto an actual character so get_node never runs past EOL.
  local cursor_line = get_line(buf, row)
  local col = math.min(cursor[2], math.max(#cursor_line - 1, 0))

  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col } })
  if node == nil or node == root then
    return nil
  end

  -- Rise to the statement node: the child of the tree root.
  while node:parent() ~= nil and node:parent() ~= root do
    node = node:parent()
  end
  if node:parent() == nil then
    -- Node lived in a different (injected) tree; don't trust the anchor.
    return nil
  end

  local srow, scol, erow, _ = node:range()

  -- Splice point = just past the last non-whitespace character on the end line,
  -- so a trailing terminator/closer never lands after stray whitespace.
  local end_col = #(get_line(buf, erow):gsub('%s+$', ''))

  local text = table.concat(vim.api.nvim_buf_get_text(buf, srow, scol, erow, end_col, {}), '\n')

  local head_line = get_line(buf, srow)

  return {
    text = text,
    start_row = srow,
    start_col = scol,
    end_row = erow,
    end_col = end_col,
    indent_context = {
      unit = indent_unit(buf),
      base = head_line:match('^%s*'),
    },
  }
end

return M
