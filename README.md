# mark.nvim (vim-mark Lua migration)

`vim-mark` has been migrated to a **Lua-first Neovim plugin**.

It keeps the classic multi-word highlighting workflow, while adding a cleaner Lua API, Neovim user-commands, and LazyVim-friendly defaults.

- Original maintainer line: Ingo Karkat (based on Yuheng Xie’s original work)
- Current runtime: `plugin/mark.lua` + `lua/mark/*`
- Legacy Vimscript runtime (`plugin/mark.vim`, `autoload/mark*.vim`) has been removed

## Requirements

- Neovim `>= 0.9`

## Install

### lazy.nvim / LazyVim

```lua
{
  "inkarkat/vim-mark",
  opts = {
    keymaps = { preset = "lazyvim" }, -- "lazyvim" | "legacy" | "none"
  },
}
```

### Manual setup

If you need custom behavior, call setup explicitly:

```lua
require("mark").setup({
  auto_load = false,
  auto_save = true,
  palette = "original",
})
```

## Features

- Multi-group word/regex highlighting across windows
- Mark-aware `*` / `#` search with native fallback
- Search preview while typing `/` (records final search as a mark)
- Group jump and cascade search helpers
- Save/load mark slots (`:MarkSave`, `:MarkLoad`)
- Built-in palettes (`original`, `extended`, `maximum`) and custom palettes
- Legacy command/global compatibility (configurable)

## Commands

### Primary commands

- `:MarkAdd[!] [pattern]`
- `:MarkRegex [pattern]`
- `:[N]MarkClear`
- `:MarkClearAll`
- `:MarkToggle`
- `:MarkList`
- `:MarkSave [slot]`
- `:MarkLoad [slot]`
- `:MarkPalette {name}`
- `:[N]MarkName[!] [name]`
- `:MarkNameClear`

### Search/cascade commands

- `:MarkSearchCurrentNext` / `:MarkSearchCurrentPrev`
- `:MarkSearchAnyNext` / `:MarkSearchAnyPrev`
- `:[N]MarkSearchGroupNext` / `:[N]MarkSearchGroupPrev`
- `:MarkSearchNextGroup` / `:MarkSearchPrevGroup`
- `:MarkCascadeStart[!]`
- `:MarkCascadeNext[!]`
- `:MarkCascadePrev[!]`

### Legacy aliases (enabled by default)

- `:Mark` (legacy compatible behavior)
- `:Marks` (list marks via picker by default)

Set `legacy_commands = false` to disable legacy aliases.

## Default keymaps

Default preset is `lazyvim`.

- `<leader>m` mark current word (or visual selection)
- `<leader>M` mark partial word
- `<leader>mr` mark regex (normal/visual)
- `<leader>mn` clear mark under cursor / by count
- `<leader>mc` clear all
- `<leader>mt` toggle marks
- `<leader>ml` list marks (picker by default)
- `<leader>m*`, `<leader>m#` search current mark
- `<leader>m/`, `<leader>m?` search any mark
- `*`, `#` mark-aware search with fallback to native behavior

Use `keymaps.preset = "legacy"` for classic mappings, or `"none"` to manage mappings yourself.

## Configuration

Default options:

```lua
require("mark").setup({
  history_add = "/@",
  auto_load = false,
  auto_save = true,
  palette = "original",
  palette_count = -1,
  palettes = {},
  direct_group_jump_mapping_num = 9,
  exclude_predicates = {
    function()
      return vim.b.nomarks or vim.w.nomarks or vim.t.nomarks
    end,
  },
  match_priority = -10,
  ignorecase = nil,
  keymaps = { preset = "lazyvim" },
  ui = {
    enhanced_picker = false,
    float_list = false,
  },
  legacy_commands = true,
})
```

List UI behavior:

- `:Marks` / `<leader>ml` uses `vim.ui.select` by default
- Mark entries show only the pattern text (empty groups show `<empty>`)
- Set `ui.float_list = true` to use the legacy floating list window

## Persistence

- `:MarkSave [slot]` stores mark definitions in `g:MARK_<slot>`
- `:MarkLoad [slot]` restores from the same slot
- Default slot is `MARKS` (`g:MARK_MARKS`)
- Default load also falls back to `g:MARK_marks` for compatibility
- `auto_save` persists marks on `VimLeavePre`
- `auto_load` restores marks during first setup when data exists
- With `auto_load = false`, `:MarkList` syncs on demand:
  - if marks already exist in memory, they are saved to the default slot
  - if no marks exist in memory, it tries loading from persistent storage

## Palette customization

- Built-in palette names: `original`, `extended`, `maximum`
- You can provide additional palettes via `palettes = { name = { ... } }`
- Switch at runtime with `:MarkPalette <name>`

## Migration notes

See `MIGRATION.md` for a concise Vimscript -> Lua migration guide, including runtime/command/keymap changes.

## Developer notes

Runtime manifest is kept in `mark.manifest`.

Main modules:

- `lua/mark/init.lua`
- `lua/mark/config.lua`
- `lua/mark/state.lua`
- `lua/mark/highlight.lua`
- `lua/mark/persist.lua`
- `lua/mark/cascade.lua`
- `lua/mark/palettes.lua`
- `plugin/mark.lua`

For full `:help` content, refer to `doc/mark.txt`.
