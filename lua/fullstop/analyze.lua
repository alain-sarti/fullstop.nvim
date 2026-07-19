-- fullstop: the pure brain. Zero vim.*, cursor-free, string-only, so it is
-- unit-testable as plain Lua.
--
--   analyze(region_text, indent_context) -> tagged verdict
--     { kind = 'complete', insert = <string>, opens_block = false }
--     { kind = 'advance' }
--     { kind = 'decline', reason = <string> }
--
-- Cluster A so far: balance the open ( [ { stack (literal-aware, ticket 02) and
-- append a ';' terminator. The decline gate lands in ticket 03, and
-- block-opening (opens_block = true) in tickets 04-05.

local M = {}

local OPENERS = { ['('] = ')', ['['] = ']', ['{'] = '}' }

-- Delimiter balancer: a hand-rolled lexer that tracks a stack of open ( [ {
-- (plus template literals and their ${...} interpolations), skipping delimiters
-- inside strings, line/block comments, and template text, while still counting
-- code inside ${...}. Returns the closers needed to balance the whole open
-- stack, innermost first, or '' if already balanced.
--
-- Each stack frame records the closer it needs and the mode to resume when it
-- closes, so a `}` closing a ${...} correctly drops back into template text
-- (not code) and a template's closing backtick is emitted like any other closer.
local function missing_closers(text)
  local stack = {} -- frames { close, resume }, bottom -> top
  -- mode: 'code' | 'sq' | 'dq' | 'line' (//) | 'block' (/* */) | 'tmpl' (`...`)
  local mode = 'code'
  local i, n = 1, #text
  while i <= n do
    local c = text:sub(i, i)
    local nxt = text:sub(i + 1, i + 1)
    local top = stack[#stack]
    if mode == 'code' then
      if c == "'" then
        mode = 'sq'
      elseif c == '"' then
        mode = 'dq'
      elseif c == '`' then
        stack[#stack + 1] = { close = '`', resume = 'code' }
        mode = 'tmpl'
      elseif c == '/' and nxt == '/' then
        mode = 'line'
        i = i + 1
      elseif c == '/' and nxt == '*' then
        mode = 'block'
        i = i + 1
      elseif OPENERS[c] then
        -- Object/array/call opener. Object braces render spaced ({ a: 1 });
        -- ( and [ stay tight. Block braces are ticket 04, not seen here.
        stack[#stack + 1] = { close = OPENERS[c], resume = 'code', spaced = c == '{' }
      elseif top and top.close == c then
        -- c matches the closer on top of the stack; pop and resume its context.
        stack[#stack] = nil
        mode = top.resume
      end
    elseif mode == 'sq' or mode == 'dq' then
      if c == '\\' then
        i = i + 1 -- skip the escaped character
      elseif (mode == 'sq' and c == "'") or (mode == 'dq' and c == '"') then
        mode = 'code'
      end
    elseif mode == 'tmpl' then
      if c == '\\' then
        i = i + 1 -- skip the escaped character
      elseif c == '`' then
        stack[#stack] = nil -- pop the template frame
        mode = 'code'
      elseif c == '$' and nxt == '{' then
        -- Interpolation: count its code, then resume template text on the `}`.
        stack[#stack + 1] = { close = '}', resume = 'tmpl' }
        mode = 'code'
        i = i + 1
      end
    elseif mode == 'line' then
      if c == '\n' then
        mode = 'code'
      end
    elseif mode == 'block' then
      if c == '*' and nxt == '/' then
        mode = 'code'
        i = i + 1
      end
    end
    i = i + 1
  end
  local out = {}
  for j = #stack, 1, -1 do
    local f = stack[j]
    out[#out + 1] = (f.spaced and ' ' or '') .. f.close
  end
  return table.concat(out)
end

local function rstrip(s)
  return (s:gsub('%s+$', ''))
end

-- indent_context is unused in issue 01 (no blocks); it is part of the contract
-- ticket 04 leans on for block-body indentation.
function M.analyze(region_text, _indent_context)
  local trimmed = rstrip(region_text)
  if trimmed == '' then
    return { kind = 'advance' }
  end

  local closers = missing_closers(region_text)
  local already_terminated = closers == '' and trimmed:sub(-1) == ';'
  if already_terminated then
    return { kind = 'advance' }
  end

  return { kind = 'complete', insert = closers .. ';', opens_block = false }
end

return M
