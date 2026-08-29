# fullstop.nvim

Neovim plugin that finishes the TypeScript statement the cursor is in — Neovim's answer to IntelliJ's "Complete Current Statement".

## Language

**Current statement** (a.k.a. the **located region**):
The full *logical* statement the cursor sits in, from its first token to the end of its text — not the physical line. A statement that wraps across several lines is completed as one whole, closing all delimiters opened anywhere in that span. The cursor only *selects* which statement; it never bounds the completion — firing from anywhere inside a statement completes the whole thing. A construct that owns a body is its **head** plus that body: the current statement is the head when the cursor is in the head, and the body when the cursor is in the body.
_Avoid_: line, current line

**Head**:
The part of a body-owning construct that comes before its body — `if (test)`, `while (a)`, `for (const x of xs)`, `} else`, `catch (e)`, `function f()`, `class C`. A head can span several lines, and it is what a fire completes: the `{ }` block a construct still needs is opened on its head.
_Avoid_: "the if line" (a head is not a line)

**Body slot**:
Where a body-owning construct's body goes, and whether anything fills it yet. An empty slot is what a block gets opened for; a filled slot means the construct needs no block, so the fire terminates or advances instead. Only a body on the head's own line counts as part of the same statement — a body on a later line is a statement of its own, and stays one.

### Completion outcomes

Every fire resolves to exactly one of three outcomes. They replace the spec's single overloaded "safe fallback".

**Complete**:
A delta exists — fullstop inserts the missing delimiters, an opened block, and/or a terminator, then places the cursor.

**Advance**:
Nothing to finish — the statement is already complete, the line is empty, or there's no statement — so fullstop opens a fresh line below and moves on. This is a *success* outcome.

**Decline**:
Fullstop can't safely determine the statement's structure (ambiguous regex `/`, deeply nested `${…}`, or an unterminated string). It changes nothing and shows a hint. Never a silent newline, which would masquerade as success.
_Avoid_: safe fallback (it hid the Advance-vs-Decline distinction)
