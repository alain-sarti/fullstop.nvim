# 03 — A shadowed mapping is indistinguishable from a broken plugin

**What to build:** Give the user a way to find out that another plugin owns their key.
fullstop maps `<Plug>(CompleteStatement)` for insert and normal mode and asks the user
to bind it themselves; nothing detects that the binding was later overwritten. When it
is, fullstop is simply silent — the same symptom as a plugin that does not work.

Observed in the reporter's config, with `vim.keymap.set({ 'i', 'n' }, '<C-j>', ...)`
in a lazy.nvim `config` block:

```
insert: <Plug>(CompleteStatement)
normal: <Cmd>ZellijNavigateDown<CR>
```

`zellij-nav.nvim` declares `<c-j>` through a lazy `keys` spec, so lazy re-registers the
mapping after fullstop's `ft`-triggered `config` has run. Half the advertised binding
was dead with no hint of why.

This is a config conflict rather than a plugin defect — the README's "Mapping per
filetype" section already gives the fix (`ftplugin/`, buffer-local, which outranks the
global map). What is missing is any way to *diagnose* it.

**Blocked by:** —

**Status:** ready-for-agent

## Checklist

- [ ] README documents the failure mode: a key bound in a lazy `config` block can be
      overwritten by any plugin that declares the same key via `keys`, and the symptom
      is silence in one mode only.
- [ ] README names the one-line check — `:verbose imap <key>` / `:verbose nmap <key>`
      shows what actually owns the key and which file set it.
- [ ] The "Mapping per filetype" section states plainly that the `ftplugin/` route is
      the robust one *because* buffer-local mappings outrank global ones, not merely to
      keep the key free elsewhere.
- [ ] Decide whether a `:checkhealth fullstop` reporting the resolved mapping per mode
      is worth its weight, or whether documentation is enough. If it ships, it reports
      what each mode resolves to and warns when that is not `<Plug>(CompleteStatement)`.

## Comments

- Independent of issues 01 and 02 — insert mode fired correctly throughout, including
  with blink.cmp's completion menu open, which was tested explicitly.
- No plugin-side change is required for the reporter to be unblocked; they can rebind
  or move the map into `ftplugin/typescript.lua`. The value here is that the next
  person does not spend the same hour.
