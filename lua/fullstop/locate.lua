-- fullstop: the treesitter shell. Given a buffer + cursor, walk up to the
-- enclosing statement region and hand `analyze` plain strings to reason about.
--
-- Treesitter is trusted for POSITION only (the spec's decision): an unfinished
-- line parses as an ERROR node, but that node's range still brackets the
-- statement, which is all locate needs. Every meaning decision happens later in
-- analyze on the raw text.
--
-- locate is deliberately thin: it rises to the statement node — the innermost
-- ancestor whose parent is a statement container (ADR-0002).
--
-- The known residual mis-anchoring is a broken statement whose own delimiters
-- swallow the enclosing block's brace, so the tree holds no statement node to
-- anchor to: an unclosed `{` or `${` eats the `}` below it, and a tail after the
-- block (`} catch`, `} while`, `})`) collapses the whole construct into one
-- ERROR. The anchor is then the construct (or nil when that ERROR is the tree
-- root). A delimiter-based fallback ladder for those is a later ticket; until
-- then ADR-0001 keeps the wrong verdict revertible in a single `u`.

local M = {}

-- Grammar node types that hold statements as direct children. The rise stops at
-- the boundary of one of these, so the anchor is the statement rather than the
-- construct enclosing it. `statement_block` is the braced body of every
-- construct that has one (function, arrow, if, else, for, while, do, try, catch,
-- finally, namespace, bare block); `class_body` holds methods and fields;
-- `switch_body` and its arms hold a switch's statements; `program` is the file.
local STATEMENT_CONTAINERS = {
  program = true,
  statement_block = true,
  class_body = true,
  switch_body = true,
  switch_case = true,
  switch_default = true,
}

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
  parser:parse() -- get_node reads the parsed trees; it never parses for us.

  -- Clamp the column onto an actual character so get_node never runs past EOL.
  local cursor_line = get_line(buf, row)
  local col = math.min(cursor[2], math.max(#cursor_line - 1, 0))

  -- Rise to the statement: the last node below the innermost container on the
  -- way up. Stopping at the child of the tree root instead would climb past a
  -- nested statement onto the whole function / if / class enclosing it.
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col } })
  local statement = nil
  while node ~= nil and not STATEMENT_CONTAINERS[node:type()] do
    statement = node
    node = node:parent()
  end
  if statement == nil then
    -- The container is the smallest node at the cursor, so the cursor sits
    -- between statements (a blank body line, a brace) and there is nothing to
    -- complete. The tree root is a container, which covers an empty buffer.
    return nil
  end
  if node == nil then
    -- Rose clear out of the tree without meeting a container: the node lived in
    -- a different (injected) tree, so don't trust the anchor.
    return nil
  end

  local srow, scol, erow, _ = statement:range()

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
