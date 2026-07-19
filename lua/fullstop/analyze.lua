-- fullstop: the pure brain. Zero vim.*, cursor-free, string-only, so it is
-- unit-testable as plain Lua.
--
--   analyze(region_text, indent_context) -> tagged verdict
--     { kind = 'complete', insert = <string>, opens_block = false, tail = <string?> }
--     { kind = 'advance' }
--     { kind = 'decline', reason = <string> }
--
-- Cluster A: balance the open ( [ { stack (literal-aware, ticket 02), append a
-- ';' terminator, and — ticket 03 — bail out to Decline whenever the lex is
-- ambiguous, and splice before a trailing comment so it survives. Block-opening
-- (opens_block = true) lands in tickets 04-05.

local M = {}

local OPENERS = { ['('] = ')', ['['] = ']', ['{'] = '}' }

local function rstrip(s)
  return (s:gsub('%s+$', ''))
end

-- A `/` in code begins a regex literal (rather than a division operator) when
-- the previous significant character can't end an expression. Division we can
-- lex like any operator, but a regex body's ( [ { are literal text that would
-- poison the balancer — so a regex-context `/` is a Decline (see lex).
local function is_expr_end(ch)
  if ch == nil then
    return false
  end
  if ch:match('[%w_$]') then -- identifier or number
    return true
  end
  return ch == ')' or ch == ']' or ch == '}' or ch == "'" or ch == '"' or ch == '`'
end

-- Back up over a run of spaces/tabs ending just before `idx`, returning the
-- index of the first whitespace char (or `idx` when none precedes it). Used to
-- fold a trailing comment's leading indentation into the preserved tail.
local function ws_start(text, idx)
  local j = idx - 1
  while j >= 1 and text:sub(j, j):match('[ \t]') do
    j = j - 1
  end
  return j + 1
end

-- Literal-aware lexer over the region text. Tracks a stack of open ( [ { (plus
-- template literals and their ${...} interpolations), skipping delimiters inside
-- strings and comments while still counting code inside ${...}. Returns:
--   { ok = true, closers = <string>, tail = <string?> }
--     closers: the missing closers, innermost first, or '' if balanced.
--     tail:    a trailing line comment (with its leading whitespace) to preserve
--              before the insertion, or nil.
--   { ok = false, reason = <string> }
--     when the structure is ambiguous/unsafe: a regex-vs-division `/`, template
--     nesting past depth 1, or an unterminated string.
--
-- Each stack frame records the closer it needs and the mode to resume when it
-- closes, so a `}` closing a ${...} correctly drops back into template text
-- (not code) and a template's closing backtick is emitted like any other closer.
local function lex(text)
  local stack = {} -- frames { close, resume }, bottom -> top
  -- mode: 'code' | 'sq' | 'dq' | 'line' (//) | 'block' (/* */) | 'tmpl' (`...`)
  local mode = 'code'
  local tmpl_depth = 0 -- open template literals; > 1 means nesting past depth 1
  local prev = nil -- last significant code char, for regex-vs-division
  local comment_at = nil -- start of a trailing // comment's leading whitespace
  local i, n = 1, #text
  while i <= n do
    local c = text:sub(i, i)
    local nxt = text:sub(i + 1, i + 1)
    local top = stack[#stack]
    if mode == 'code' then
      if c == "'" then
        mode = 'sq'
        prev = c
      elseif c == '"' then
        mode = 'dq'
        prev = c
      elseif c == '`' then
        tmpl_depth = tmpl_depth + 1
        if tmpl_depth > 1 then
          return { ok = false, reason = 'nested template literal' }
        end
        stack[#stack + 1] = { close = '`', resume = 'code' }
        mode = 'tmpl'
        prev = c
      elseif c == '/' and nxt == '/' then
        comment_at = ws_start(text, i)
        mode = 'line'
        i = i + 1
      elseif c == '/' and nxt == '*' then
        mode = 'block'
        i = i + 1
      elseif c == '/' then
        -- Lone slash: division (safe, lex on) or a regex literal (Decline).
        if not is_expr_end(prev) then
          return { ok = false, reason = 'ambiguous regex or division' }
        end
        prev = c
      elseif OPENERS[c] then
        -- Object/array/call opener. Object braces render spaced ({ a: 1 });
        -- ( and [ stay tight. Block braces are ticket 04, not seen here.
        stack[#stack + 1] = { close = OPENERS[c], resume = 'code', spaced = c == '{' }
        prev = c
      elseif top and top.close == c then
        -- c matches the closer on top of the stack; pop and resume its context.
        stack[#stack] = nil
        mode = top.resume
        prev = c
      elseif not c:match('%s') then
        prev = c
      end
    elseif mode == 'sq' or mode == 'dq' then
      if c == '\\' then
        i = i + 1 -- skip the escaped character
      elseif (mode == 'sq' and c == "'") or (mode == 'dq' and c == '"') then
        mode = 'code'
        prev = c
      end
    elseif mode == 'tmpl' then
      if c == '\\' then
        i = i + 1 -- skip the escaped character
      elseif c == '`' then
        stack[#stack] = nil -- pop the template frame
        tmpl_depth = tmpl_depth - 1
        mode = 'code'
        prev = c
      elseif c == '$' and nxt == '{' then
        -- Interpolation: count its code, then resume template text on the `}`.
        stack[#stack + 1] = { close = '}', resume = 'tmpl' }
        mode = 'code'
        i = i + 1
      end
    elseif mode == 'line' then
      if c == '\n' then
        mode = 'code'
        comment_at = nil -- that comment ended; it wasn't the trailing one
      end
    elseif mode == 'block' then
      if c == '*' and nxt == '/' then
        mode = 'code'
        i = i + 1
      end
    end
    i = i + 1
  end

  if mode == 'sq' or mode == 'dq' then
    return { ok = false, reason = 'unterminated string' }
  end

  local out = {}
  for j = #stack, 1, -1 do
    local f = stack[j]
    out[#out + 1] = (f.spaced and ' ' or '') .. f.close
  end
  -- A // comment we ended inside is the statement's trailing comment; fold in
  -- its leading whitespace so the insertion lands right after the code.
  local tail = (mode == 'line' and comment_at) and text:sub(comment_at) or nil
  return { ok = true, closers = table.concat(out), tail = tail }
end

-- indent_context is unused until blocks (ticket 04); it is part of the contract
-- from day one for block-body indentation.
function M.analyze(region_text, _indent_context)
  if rstrip(region_text) == '' then
    return { kind = 'advance' }
  end

  local res = lex(region_text)
  if not res.ok then
    return { kind = 'decline', reason = res.reason }
  end

  -- Code tail excludes any trailing comment, so the terminator check reads the
  -- last real code character — not a `;` buried behind a comment, nor one at
  -- delimiter depth > 0 (which leaves closers non-empty).
  local code = res.tail and region_text:sub(1, #region_text - #res.tail) or region_text
  code = rstrip(code)
  if code == '' then
    return { kind = 'advance' }
  end

  local already_terminated = res.closers == '' and code:sub(-1) == ';'
  if already_terminated then
    return { kind = 'advance' }
  end

  return { kind = 'complete', insert = res.closers .. ';', opens_block = false, tail = res.tail }
end

return M
