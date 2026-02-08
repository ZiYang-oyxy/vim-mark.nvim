# Migration Guide (Vimscript -> Lua)

This project has moved to a **Lua-only Neovim implementation**.

## Runtime changes

- Removed: `plugin/mark.vim`
- Removed: `autoload/mark*.vim`
- Added: `plugin/mark.lua`
- Added: `lua/mark/*`
- Removed dependency: `ingo-library.vim`

## Setup

```lua
require("mark").setup({
  mark_only = true,
  keymaps = { preset = "lazyvim" }, -- "lazyvim" | "legacy" | "none"
  auto_load = false,
  auto_save = true,
  palette = "original",
})
```

## Command mapping

| Legacy | Lua/Neovim |
|---|---|
| `:Mark` | `:MarkAdd` (legacy alias `:Mark` still available by default) |
| `:Marks` | `:MarkList` (legacy alias `:Marks` still available by default) |
| `:MarkClear` (clear all) | `:MarkClearAll` |
| `:MarkLoad` / `:MarkSave` | `:MarkLoad` / `:MarkSave` |
| `:MarkPalette` | `:MarkPalette` |
| `:MarkName` | `:MarkName` |

## Keymaps

Default is `preset = "lazyvim"`:

- `<leader>m`: mark word
- `<leader>M`: mark partial word
- `<leader>mr`: mark regex
- `<leader>mn`: clear current / disable marks
- `<leader>mc`: clear all
- `<leader>mt`: toggle marks
- `<leader>ml`: list marks
- `<leader>m*`, `<leader>m#`: search current mark
- `<leader>m/`, `<leader>m?`: search any mark
- `*`, `#`: mark-aware search with native fallback

Optional: set `mark_only = true` to keep `*` / `#` in mark flow. If no marks
exist, one native `*` / `#` search is performed and `@/` is recorded as a mark.

Switch to `preset = "legacy"` for classic defaults, or `preset = "none"` to manage mappings yourself.

## Persistence compatibility

- Default save/load slot is now `MARKS` (`g:MARK_MARKS`) for cross-session compatibility.
- Default load without `{slot}` also checks `g:MARK_marks` as a fallback.
- If `auto_load = false`, running `:MarkList` performs lazy sync:
  - with existing in-memory marks, current marks overwrite persisted marks
  - with no in-memory marks, persisted marks are loaded before listing
