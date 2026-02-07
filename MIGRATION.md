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
- `<leader>r`: mark regex
- `<leader>n`: clear current / disable marks
- `<leader>mc`: clear all
- `<leader>mt`: toggle marks
- `<leader>ml`: list marks
- `<leader>m*`, `<leader>m#`: search current mark
- `<leader>m/`, `<leader>m?`: search any mark
- `*`, `#`: mark-aware search with native fallback

Switch to `preset = "legacy"` for classic defaults, or `preset = "none"` to manage mappings yourself.
