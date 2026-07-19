-- fullstop: the pure brain. Zero vim.*, cursor-free, string-only, so it is
-- unit-testable as plain Lua.
--
--   analyze(region_text, indent_context) -> tagged verdict
--     { kind = 'complete', insert = <string>, opens_block = false }
--     { kind = 'advance' }
--     { kind = 'decline', reason = <string> }
--
-- Issue 01 is the walking skeleton: it handles cluster A only — close a simple
-- open ( [ { stack and append a ';' terminator. The string/comment/template-aware
-- balancer replaces `missing_closers` in ticket 02, the decline gate lands in
-- ticket 03, and block-opening (opens_block = true) in tickets 04-05.

local M = {}

local OPENERS = { ['('] = ')', ['['] = ']', ['{'] = '}' }

-- Naive delimiter balancer: the closers needed to balance the open stack, in the
-- order they must be emitted, or '' if already balanced. Deliberately simple —
-- no string/comment/template awareness yet (that is ticket 02).
local function missing_closers(text)
  local stack = {}
  for i = 1, #text do
    local c = text:sub(i, i)
    local close = OPENERS[c]
    if close then
      stack[#stack + 1] = close
    elseif stack[#stack] == c then
      -- c matches the closer on top of the stack (the stack holds only closers).
      stack[#stack] = nil
    end
  end
  local out = {}
  for i = #stack, 1, -1 do
    out[#out + 1] = stack[i]
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
