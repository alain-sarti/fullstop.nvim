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
-- Issue 05 gives it one job beyond position: it reports the construct's **body
-- slot** (ADR-0003), because "does this text start with a block keyword?" — all
-- `analyze` can ask — is not "does this construct still need a body?". The slot is
-- read from the grammar's own body fields, so it is structure, not a heuristic:
--   'none'      nothing fills it (or there is no slot at all) → analyze may open one
--   'statement' an unbraced body on the head's own line       → never open a block
--   'block'     a `{ }` body, closed or not                   → never open a block
--   'unknown'   an ERROR anchor has no fields to read         → analyze reads text
-- A body on a *later* line is not part of the head being completed, so the region
-- is capped at the head's last code character and the slot reads 'none' — the block
-- opens on the head and `apply` pushes the orphaned body below the closing `}`.
-- Fired on that body instead, the body is its own statement and locate re-anchors.
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

local function rstrip(s)
  return (s:gsub('%s+$', ''))
end

-- Node types whose presence means the body slot holds a real `{ }` block.
local BLOCK_BODIES = {
  statement_block = true,
  class_body = true,
  switch_body = true,
}

-- Grammar fields that hold a construct's body, trailing-first: a `try`'s finally
-- outranks its catch outranks its own block, an `if`'s else outranks its
-- consequence. Only the child that *ends where the statement ends* counts as the
-- trailing slot, which is what keeps a do-while's `{ }` — followed by its
-- condition — from reading as the slot the user is filling.
local BODY_FIELDS = { 'finalizer', 'handler', 'alternative', 'body', 'consequence' }

-- Clauses that hold their body one level down: `else foo();`, `catch (e) { }`.
local BODY_CLAUSES = { else_clause = true, catch_clause = true, finally_clause = true }

local function ends_at(node, erow, ecol)
  local _, _, row, col = node:range()
  return row == erow and col == ecol
end

-- The last named child ending exactly where `node` does, or nil.
local function trailing_child(node)
  local count = node:named_child_count()
  if count == 0 then
    return nil
  end
  local last = node:named_child(count - 1)
  local _, _, erow, ecol = node:range()
  return last and ends_at(last, erow, ecol) and last or nil
end

-- The construct's trailing body node, from the grammar's own fields.
local function body_slot(node)
  local _, _, erow, ecol = node:range()
  for _, field in ipairs(BODY_FIELDS) do
    local kid = node:field(field)[1]
    if kid and ends_at(kid, erow, ecol) then
      return BODY_CLAUSES[kid:type()] and trailing_child(kid) or kid
    end
  end
  return nil
end

-- Does a `{ }` block end exactly where the statement does? The fallback for
-- wrapper anchors that carry no body field of their own — `export_statement`,
-- `lexical_declaration` — whose block hangs off a nested declaration. Consulted
-- only when the field walk found nothing, so a block belonging to something else
-- (`if (a) foo(() => { })`) never outranks the real slot.
local function has_trailing_block(node)
  local cur = node
  while cur do
    if BLOCK_BODIES[cur:type()] then
      return true
    end
    cur = trailing_child(cur)
  end
  return false
end

-- The head's last code character, strictly before the body's start and never
-- above the statement's own first line. This is the cap's splice point, so it
-- deliberately includes a trailing comment — `analyze` hands that back as `tail`
-- and the insertion lands in front of it.
local function head_end(buf, srow, brow, bcol)
  local prefix = rstrip(get_line(buf, brow):sub(1, bcol))
  if #prefix > 0 then
    return brow, #prefix
  end
  for row = brow - 1, srow, -1 do
    local line = rstrip(get_line(buf, row))
    if #line > 0 then
      return row, #line
    end
  end
  return brow, bcol
end

-- Resolve the body slot, and with it the two positional consequences it forces:
-- re-anchor when the cursor already sits on an orphaned body, cap the region at
-- the head when it does not. Returns the (possibly re-anchored) statement, the
-- slot, and the cap position — nil unless the region must stop above the body.
local function resolve_slot(buf, statement, cursor_row)
  while true do
    if statement:type() == 'ERROR' then
      return statement, 'unknown', nil -- no fields to read; analyze reads the text
    end
    local slot = body_slot(statement)
    if slot == nil then
      return statement, has_trailing_block(statement) and 'block' or 'none', nil
    end
    if BLOCK_BODIES[slot:type()] then
      return statement, 'block', nil
    end
    local srow = statement:range()
    local brow, bcol = slot:range()
    local hrow, hcol = head_end(buf, srow, brow, bcol)
    if hrow == brow then
      return statement, 'statement', nil -- the body shares the head's line
    end
    if cursor_row >= brow then
      statement = slot -- the cursor selects: the body is a statement of its own
    else
      return statement, 'none', { row = hrow, col = hcol }
    end
  end
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

  local body, cap
  statement, body, cap = resolve_slot(buf, statement, row)

  local srow, scol, erow, _ = statement:range()

  -- Splice point = just past the last non-whitespace character on the end line,
  -- so a trailing terminator/closer never lands after stray whitespace. A capped
  -- region ends at the head instead, above a body that is none of its business.
  local end_col
  if cap then
    erow, end_col = cap.row, cap.col
  else
    end_col = #rstrip(get_line(buf, erow))
  end

  local text = table.concat(vim.api.nvim_buf_get_text(buf, srow, scol, erow, end_col, {}), '\n')

  local head_line = get_line(buf, srow)

  return {
    text = text,
    body = body,
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
