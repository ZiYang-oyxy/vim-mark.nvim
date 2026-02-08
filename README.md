# vim-mark.nvim (Lua-first Neovim fork)

`vim-mark.nvim` is a **Lua-first Neovim fork** and continuation of `vim-mark`.

It preserves the classic multi-word highlighting workflow while adding a cleaner Lua API, Neovim user-commands, and LazyVim-friendly defaults.

[![asciicast](https://asciinema.org/a/783151.svg)](https://asciinema.org/a/783151)

- Original maintainer line: Ingo Karkat (based on Yuheng Xie’s original work)
- Current maintained repository: `ZiYang-oyxy/vim-mark.nvim`
- Current runtime: `plugin/mark.lua` + `lua/mark/*`
- Legacy Vimscript runtime (`plugin/mark.vim`, `autoload/mark*.vim`) has been removed

## Requirements

- Neovim `>= 0.9`

## Install

### lazy.nvim / LazyVim

```lua
{
  "ZiYang-oyxy/vim-mark.nvim",
  opts = {
    mark_only = true,
    keymaps = { preset = "lazyvim" }, -- "lazyvim" | "legacy" | "none"
  },
}
```

For local development, use a `dir` source:

```lua
{
  dir = "/path/to/vim-mark.nvim",
  name = "vim-mark.nvim",
  main = "mark",
}
```

### Manual setup

If you need custom behavior, call setup explicitly:

```lua
require("mark").setup({
  auto_load = false,
  auto_save = true,
  palette = "original",
  mark_only = true,
})
```

## Upstream defaults vs personal workflow

`vim-mark.nvim` should keep broadly compatible defaults in-plugin, and let heavily opinionated key behavior live in user config.

- Good candidates for plugin defaults: portable options (`auto_save`, `auto_load`, palette behavior, list UI mode) and conservative key presets (`lazyvim`, `legacy`, `none`)
- Better kept in personal config: remapping high-frequency native keys (`n` / `N`), punctuation keys (`!`, `@`), and custom `<leader>` semantics
- Recommended approach: keep plugin spec focused on `opts`, and put your custom mappings in `lua/config/keymaps.lua`

### LazyVim custom keymap profile (plugin opts + keymaps.lua)

Below is a mark-first workflow profile where plugin config stays minimal and all keymaps are managed in `lua/config/keymaps.lua`.

```lua
-- lua/plugins/mark.lua
{
  "ZiYang-oyxy/vim-mark.nvim",
  main = "mark",
  lazy = false,
  opts = {
    search_global_progress = true,
    mark_only = true,
    keymaps = { preset = "none" },
    auto_save = true,
    auto_load = false,
    ui = {
      enhanced_picker = false,
      float_list = true,
    },
  },
}
```

```lua
-- lua/config/keymaps.lua
local keymap = vim.keymap.set
local function mark_module()
  return require("mark")
end

keymap({ "n", "x" }, "!", function()
  mark_module().mark_word_or_selection({ group = vim.v.count })
end, { desc = "Mark: Toggle word or selection", silent = true })
keymap("n", "<leader><cr>", function()
  mark_module().clear_all()
end, { desc = "Mark: Clear all", silent = true })
keymap("n", "n", function()
  mark_module().search_any_mark(false, vim.v.count1)
end, { desc = "Mark: Next any match", silent = true })
keymap("n", "N", function()
  mark_module().search_any_mark(true, vim.v.count1)
end, { desc = "Mark: Prev any match", silent = true })
keymap("n", "*", function()
  mark_module().search_word_or_selection_mark(false, vim.v.count1)
end, { desc = "Mark: Next word/selection mark", silent = true })
keymap("n", "#", function()
  mark_module().search_word_or_selection_mark(true, vim.v.count1)
end, { desc = "Mark: Prev word/selection mark", silent = true })
keymap("n", "@", function()
  mark_module().search_current_mark(true, vim.v.count1)
end, { desc = "Mark: Prev current match", silent = true })
keymap("n", "<leader>`", function()
  mark_module().list()
end, { desc = "Mark: List all", silent = true, nowait = true })
```

Note: this profile intentionally overrides native `n` / `N` search navigation. If you prefer Vim-native search semantics, keep those keys unmapped in your `keymaps.lua`.

This profile is meant for fully custom mappings, so it explicitly uses `keymaps = { preset = "none" }`.

## Features

- Multi-group word/regex highlighting across windows
- Mark-aware `*` / `#` search, with optional mark-only takeover
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
- `*`, `#` mark-aware search (see `mark_only` below for takeover mode)

Use `keymaps.preset = "legacy"` for classic mappings, or `"none"` to manage mappings yourself.

Set `mark_only = true` to keep `*` / `#` in mark flow:
- resolve pattern from current mark / word (same source logic as `mark_word_or_selection`)
- ensure the pattern is marked without toggle side effects
- run directional jump (`*` forward, `#` backward) with `[count]` semantics

`/` takeover is handled via cmdline events, so search preview / recording still works even if your `/` keymap is customized.
After pressing `<CR>`, native `hlsearch` highlighting is cleared automatically so mark highlights take over cleanly.

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
  search_global_progress = false,
  mark_only = false,
  keymaps = { preset = "lazyvim" },
  ui = {
    enhanced_picker = false,
    float_list = false,
  },
  legacy_commands = true,
})
```

Search message progress:

- Successful searches show a two-line progress block for the current group, e.g.:

  ```
  138,333 / 138,835
  ███████████████████████████▉ 99.64%
  ```

- Set `search_global_progress = true` to append a labeled global block:

  ```
  Group   138,333 / 138,835
  ███████████████████████████▉ 99.64%
  Global  392,000 / 499,800
  █████████████████████▊       78.44%
  ```

- To enable global progress in your Neovim config:

  ```lua
  require("mark").setup({
    search_global_progress = true,
  })
  ```

- Progress messages use highlight group `MarkSearchProgress` (bold by default)

List UI behavior:

- `:Marks` / `<leader>ml` uses `vim.ui.select` by default
- Picker entries show only the pattern text (empty groups show `<empty>`)
- Set `ui.float_list = true` to use the floating list window with `Grp / Pattern / Count` columns

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
