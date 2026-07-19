# fullstop.nvim

Neovim plugin that finishes the TypeScript statement the cursor is in — Neovim's answer to IntelliJ's "Complete Current Statement".

## Language

**Current statement** (a.k.a. the **located region**):
The full *logical* statement the cursor sits in, from its first token to the end of its text — not the physical line. A statement that wraps across several lines is completed as one whole, closing all delimiters opened anywhere in that span. The cursor only *selects* which statement; it never bounds the completion — firing from anywhere inside a statement completes the whole thing.
_Avoid_: line, current line

### Completion outcomes

Every fire resolves to exactly one of three outcomes. They replace the spec's single overloaded "safe fallback".

**Complete**:
A delta exists — fullstop inserts the missing delimiters, an opened block, and/or a terminator, then places the cursor.

**Advance**:
Nothing to finish — the statement is already complete, the line is empty, or there's no statement — so fullstop opens a fresh line below and moves on. This is a *success* outcome.

**Decline**:
Fullstop can't safely determine the statement's structure (ambiguous regex `/`, deeply nested `${…}`, or an unterminated string). It changes nothing and shows a hint. Never a silent newline, which would masquerade as success.
_Avoid_: safe fallback (it hid the Advance-vs-Decline distinction)
