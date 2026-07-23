-- fullstop: the pure brain. Zero vim.*, cursor-free, string-only, so it is
-- unit-testable as plain Lua.
--
--   analyze(region_text, indent_context) -> tagged verdict
--     { kind = 'complete', insert = <string>, opens_block = false, tail = <string?> }
--     { kind = 'complete', opens_block = true, insert = <string>,
--       body = <string>, close = <string>, tail = <string?> }
--     { kind = 'advance' }
--     { kind = 'decline', reason = <string> }
--
-- Cluster A: balance the open ( [ { stack (literal-aware, ticket 02), append a
-- ';' terminator, and — ticket 03 — bail out to Decline whenever the lex is
-- ambiguous, and splice before a trailing comment so it survives.
--
-- Cluster B (ticket 04): a control-flow head opens an idempotent `{ }` block
-- (opens_block = true) instead of terminating — closers then ` {`, the body line
-- at `base + unit` (cursor there) and the closing `}` at `base`, no `;`.
--
-- Cluster C (ticket 05): declaration & expression blocks reuse that same
-- machinery. A `function` / `class` head (bare or behind `export` / `async`) and
-- a bare `=>` arrow open a block; the closing `}` gets a `;` iff the construct is
-- an assigned expression (`const f = function`, `const f = () =>`) and `∅` for a
-- self-terminating declaration. `=> expr` / `=> (` is an expression body → A.

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
--   { ok = true, frames = <list>, tail = <string?> }
--     frames: the open-delimiter stack, bottom -> top, each { close, spaced };
--             empty if balanced. `closers_of` renders it into a closer string.
--     tail:   a trailing line comment (with its leading whitespace) to preserve
--             before the insertion, or nil.
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

  -- Expose the open-frame stack (bottom -> top), not a pre-built closer string,
  -- so analyze can close the whole stack (cluster A) *or* — reusing an
  -- already-typed block brace (cluster B) — close only the frames below the top.
  local frames = {}
  for j = 1, #stack do
    frames[j] = { close = stack[j].close, spaced = stack[j].spaced }
  end
  -- A // comment we ended inside is the statement's trailing comment; fold in
  -- its leading whitespace so the insertion lands right after the code.
  local tail = (mode == 'line' and comment_at) and text:sub(comment_at) or nil
  return { ok = true, frames = frames, tail = tail }
end

-- Missing closers for a frame list, innermost (top) first. Object `{` frames
-- render spaced (` }`); ( and [ stay tight. Shared by cluster A (close the whole
-- stack) and cluster B (close everything below an already-typed block brace).
local function closers_of(frames)
  local out = {}
  for j = #frames, 1, -1 do
    out[#out + 1] = (frames[j].spaced and ' ' or '') .. frames[j].close
  end
  return table.concat(out)
end

-- Control-flow heads (cluster B) that open a `{ }` block body. `else if` and a
-- bare `else` both key off `else`; `do` is deliberately absent — its only tail,
-- `} while (...)`, terminates (handled by the guard in opens_block below).
local BLOCK_KEYWORDS = {
  ['if'] = true,
  ['else'] = true,
  ['for'] = true,
  ['while'] = true,
  ['switch'] = true,
  ['try'] = true,
  ['catch'] = true,
  ['finally'] = true,
}

-- Does `code` begin a control-flow block head? A lookbehind on the leading
-- keyword, past an optional `}` continuation (`} else`, `} catch`, `} finally`).
-- The one guard: `} while (...)` is a do-while tail, so it terminates — it never
-- opens a block. (A multi-line do-while locates as the whole `do {...} while`,
-- whose leading keyword is `do`, so only the single-line `} while` needs this.)
local function opens_block(code)
  local s = code:gsub('^%s*', '')
  local after_brace = s:match('^}%s*(.*)$')
  local had_brace = after_brace ~= nil
  if had_brace then
    s = after_brace
  end
  local kw, after = s:match('^(%a+)(.?)')
  if not kw or not BLOCK_KEYWORDS[kw] then
    return false
  end
  -- kw matched only a prefix of a longer identifier (e.g. `forEach`, `ifx`).
  if after:match('[%w_$]') then
    return false
  end
  if had_brace and kw == 'while' then
    return false -- do-while tail: terminate, don't open a block.
  end
  return true
end

-- Cluster C (ticket 05): declaration & expression blocks. A `function` / `class`
-- head — bare or behind an `export` / `export default` / `async` prefix — opens a
-- block like cluster B. `strip_c_prefix` peels those prefixes so the governing
-- keyword sits at the head; `%f[%W]` pins a whole-word match (`class`, not
-- `classy`; `function*` counts, the `*` being a boundary).
local function strip_c_prefix(code)
  local s = code:gsub('^%s*', '')
  s = s:gsub('^export%s+default%s+', ''):gsub('^export%s+', '')
  return (s:gsub('^async%s+', ''))
end

local function is_decl_head(code)
  local s = strip_c_prefix(code)
  return s:match('^function%f[%W]') ~= nil or s:match('^class%f[%W]') ~= nil
end

-- A `function` / `class` on the RHS of an assignment (`const f = function`,
-- `const C = class`, `x = async function`). These open the same block as a
-- declaration but keep the `;` — the assignment statement still needs it.
local function is_assigned_construct(code)
  return code:match('=%s*function%f[%W]') ~= nil
    or code:match('=%s*async%s+function%f[%W]') ~= nil
    or code:match('=%s*class%f[%W]') ~= nil
end

-- The `=>` rule keys off what follows the LAST arrow. It opens a block only when
-- the arrow has no body yet (bare `=>`) or its `{` is already typed (`=> {`); an
-- expression body (`=> x + 1`, `=> (`, `=> ({…})`) is cluster A — just terminate,
-- so this returns false and analyze falls through. The last arrow wins so a
-- param-list default (`(x = () => 1) =>`) doesn't fool it.
local function arrow_opens_block(code)
  local pos, from = nil, 1
  while true do
    local a = code:find('=>', from, true)
    if not a then
      break
    end
    pos, from = a, a + 2
  end
  if not pos then
    return false
  end
  local after = code:sub(pos + 2):gsub('^%s*', '')
  return after == '' or after == '{'
end

-- Cluster C classifier. Returns { assigned = <bool> } when the region opens a
-- declaration/expression block, or nil when it doesn't (→ cluster A). `assigned`
-- decides the terminator: a declaration is self-terminating (`∅`), an assigned
-- expression keeps its `;`. A block-opening arrow is always an assigned
-- expression in v1 (`const f = () =>`); an expression-body arrow is cluster A.
--
-- Two non-destructive v1 gaps (ADR-0001 makes a wrong verdict revert in one `u`):
--   * The RHS/arrow patterns scan raw code, not tokens-outside-literals, so a
--     literal `= class` / `=>` *inside a string* can wrongly open a block. Head
--     forms (`is_decl_head`) are safe — a statement can't start inside a string.
--   * A bare arrow is tagged assigned unconditionally; a callback arrow that is
--     NOT an assignment RHS (`foo(() =>`) still gets a `;`. v1 arrows are the
--     `const f = …` assignment shape; callbacks are out of scope (best-effort).
local function classify_c(code)
  if is_decl_head(code) then
    return { assigned = false }
  end
  if is_assigned_construct(code) then
    return { assigned = true }
  end
  if arrow_opens_block(code) then
    return { assigned = true }
  end
  return nil
end

-- Build the block-opening verdict. When the block `{` is already typed (code
-- ends with it) we reuse it — closing only the frames below — so firing twice
-- never doubles the brace; otherwise we close the whole stack and add ` {`.
-- The body line is `base + unit` (cursor lands there), the closing `}` at `base`.
-- `assigned` (cluster C) tacks a `;` onto the closing `}` for an assigned
-- expression; cluster B and declarations leave it off (self-terminating).
local function open_block(code, res, ctx, assigned)
  local frames = res.frames
  local head
  if code:sub(-1) == '{' then
    local below = {}
    for j = 1, #frames - 1 do
      below[j] = frames[j]
    end
    head = closers_of(below)
  else
    head = closers_of(frames) .. ' {'
  end
  return {
    kind = 'complete',
    opens_block = true,
    insert = head,
    body = ctx.base .. ctx.unit,
    close = ctx.base .. '}' .. (assigned and ';' or ''),
    tail = res.tail,
  }
end

function M.analyze(region_text, indent_context)
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

  -- Cluster B: a control-flow head opens an idempotent block (no terminator).
  if opens_block(code) then
    return open_block(code, res, indent_context)
  end

  -- Cluster C: a declaration/expression head opens a block; `;` iff assigned.
  local c = classify_c(code)
  if c then
    return open_block(code, res, indent_context, c.assigned)
  end

  local closers = closers_of(res.frames)
  local already_terminated = closers == '' and code:sub(-1) == ';'
  if already_terminated then
    return { kind = 'advance' }
  end

  return { kind = 'complete', insert = closers .. ';', opens_block = false, tail = res.tail }
end

return M
