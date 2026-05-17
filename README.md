# vim-mark.nvim (Lua-first Neovim fork)

`vim-mark.nvim` is a Neovim plugin for multi-word / regex mark highlighting and mark-aware navigation, designed as a Lua-first continuation of the original Vim plugin ([inkarkat/vim-mark](https://github.com/inkarkat/vim-mark)).

[![asciicast](https://asciinema.org/a/783151.svg)](https://asciinema.org/a/783151)

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
    ui = {
      search_progress_display = "statusline", -- "message" | "statusline"
    },
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

Search progress display is mutually exclusive:

- `ui.search_progress_display = "message"`: show progress in message area
- `ui.search_progress_display = "statusline"`: show progress in statusline

When running inside LazyVim and this option is not explicitly set, default mode is `statusline` (auto-injected into `lualine_x`).

### Manual setup

If you need custom behavior, call setup explicitly:

```lua
require("mark").setup({
  auto_load = true,
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

### LazyVim custom keymap profile (single-file with `keys =`)

Below is a mark-first workflow profile where everything (opts and keymaps) lives in one plugin spec, using lazy.nvim's `keys =` field. This keeps the spec self-contained and avoids accidental overrides from other parts of your config.

`should_skip_mark_mapping` is an optional fallback so the `!` mapping does not hijack non-file buffers (dashboards, scratch, etc.).

```lua
-- lua/plugins/mark.lua
local function should_skip_mark_mapping()
  return vim.bo.filetype == "snacks_dashboard" or vim.bo.buftype == "nofile"
end

local function feed_default_key(lhs)
  local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
  vim.api.nvim_feedkeys(keys, "n", true)
end

return {
  {
    "ZiYang-oyxy/vim-mark.nvim",
    main = "mark",
    lazy = false,
    opts = {
      search_global_progress = true,
      mark_only = true,
      auto_save = true,
      auto_load = true,
      ui = {
        enhanced_picker = false,
        float_list = true,
      },
      keymaps = { preset = "none" },
    },
    keys = {
      {
        "!",
        function()
          if should_skip_mark_mapping() then
            feed_default_key("!")
            return
          end
          require("mark").mark_word_or_selection({ group = vim.v.count })
        end,
        mode = { "n", "x" },
        desc = "Mark: Toggle word or selection",
        silent = true,
      },
      {
        "n",
        function() require("mark").search_current_mark(false, vim.v.count1) end,
        desc = "Mark: Next same-color match",
        silent = true,
      },
      {
        "N",
        function() require("mark").search_current_mark(true, vim.v.count1) end,
        desc = "Mark: Prev same-color match",
        silent = true,
      },
      {
        "#",
        function() require("mark").search_word_or_selection_mark(false, vim.v.count1) end,
        desc = "Mark: Next any-color match",
        silent = true,
      },
      {
        "@",
        function() require("mark").search_word_or_selection_mark(true, vim.v.count1) end,
        desc = "Mark: Prev any-color match",
        silent = true,
      },
      {
        "<leader><cr>",
        function() require("mark").clear_all() end,
        desc = "Mark: Clear all",
        silent = true,
      },
      {
        "<leader>`",
        function() require("mark").list() end,
        desc = "Mark: List all",
        silent = true,
        nowait = true,
      },
    },
  },
}
```

Notes:
- This profile intentionally overrides native `n` / `N` search navigation. If you prefer Vim-native search, drop those two entries from `keys`.
- `#` / `@` use `search_word_or_selection_mark` (not `search_any_mark`) so that the landed mark color is recorded, allowing subsequent `n` / `N` to stay locked on that color.
- `keymaps = { preset = "none" }` disables every built-in mapping; the `keys =` table is the sole source of truth.

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

Set `mark_only = true` to keep `*`, `#`, `@`, `n`, and `N` in mark flow:

- search existing marks only, without adding a new mark from the word under cursor
- run any-color jumps with `*` / `#` forward and `@` backward
- run same-color jumps with `n` forward and `N` backward
- preserve `[count]` semantics

`/` takeover is handled via cmdline events, so search preview / recording still works even if your `/` keymap is customized.
After pressing `<CR>`, native `hlsearch` highlighting is cleared automatically so mark highlights take over cleanly.

## Configuration

Default options:

```lua
require("mark").setup({
  history_add = "/@",
  auto_load = true,
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
    search_progress_display = "message",
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

- Group/global progress counts are computed from match start positions in the current buffer and include overlapping matches (for example, `alias` + `as` inside `alias`).

- To enable global progress in your Neovim config:

  ```lua
  require("mark").setup({
    search_global_progress = true,
  })
  ```

- Progress messages use highlight group `MarkSearchProgress` (bold by default)

Search progress display mode (message vs statusline):

- Modes are mutually exclusive and controlled by `ui.search_progress_display`:

  ```lua
  require("mark").setup({
    ui = {
      search_progress_display = "message", -- or "statusline"
    },
  })
  ```

- In LazyVim, if you do not set this option explicitly, mark.nvim defaults to `statusline` and auto-injects into `lualine_x`.
- The auto-injected LazyVim `lualine_x` component uses progress-bar + index format (for example `G █████▍░░ 2/3`, or `G █████▍░░ 2/3 A ███▌░░░░ 4/9` when global progress is enabled).

- `require("mark").progressline()` returns a compact one-line progress string for the current buffer.
- Returns `""` until a successful mark search has run in that buffer.
- Uses `G` for current-group progress and `A` for global progress.
- Optional formatting options:
  - `show_counts` (default `false`)
  - `bar_width` (default `8`, clamped to `4..20`)
  - `separator` (default `"  "`)
- Example `statusline`:

  ```vim
  set statusline+=%#MarkSearchProgress#%{luaeval("require('mark').progressline()")}%*
  ```

- Example with options:

  ```vim
  set statusline+=%#MarkSearchProgress#%{luaeval("require('mark').progressline({show_counts=true, bar_width=10, separator=' | '})")}%*
  ```

- Example `winbar`:

  ```vim
  set winbar=%#MarkSearchProgress#%{luaeval("require('mark').progressline()")}%*
  ```

List UI behavior:

- `:Marks` / `<leader>ml` uses `vim.ui.select` by default
- Picker entries show only the pattern text (empty groups show `<empty>`)
- Set `ui.float_list = true` to use the floating list window with `Grp / Pattern / Count` columns (counts include overlapping matches in the current buffer)

## Persistence

- `:MarkSave [slot]` stores mark definitions in `g:MARK_<slot>`
- `:MarkLoad [slot]` restores from the same slot
- Default slot is `MARKS` (`g:MARK_MARKS`)
- Default load also falls back to `g:MARK_marks` for compatibility
- By default, marks are saved on `VimLeavePre` (`auto_save = true`) and restored during first setup (`auto_load = true`)
- Set `auto_load = false` to disable startup restore
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
