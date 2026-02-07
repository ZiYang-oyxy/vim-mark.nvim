local palettes = require("mark.palettes")

local M = {}

local function copy(value)
  return vim.deepcopy(value)
end

local function to_bool(value, default_value)
  if value == nil then
    return default_value
  end
  return value and true or false
end

local function default_exclusion_predicate()
  return vim.b.nomarks or vim.w.nomarks or vim.t.nomarks
end

M.defaults = {
  history_add = "/@",
  auto_load = false,
  auto_save = true,
  palette = "original",
  palette_count = -1,
  palettes = {},
  direct_group_jump_mapping_num = 9,
  exclude_predicates = { default_exclusion_predicate },
  match_priority = -10,
  ignorecase = nil,
  keymaps = {
    preset = "lazyvim",
  },
  ui = {
    enhanced_picker = false,
    float_list = false,
  },
  legacy_commands = true,
}

local legacy_map = {
  mwHistAdd = "history_add",
  mwAutoLoadMarks = "auto_load",
  mwAutoSaveMarks = "auto_save",
  mwDefaultHighlightingNum = "palette_count",
  mwDefaultHighlightingPalette = "palette",
  mwPalettes = "palettes",
  mwDirectGroupJumpMappingNum = "direct_group_jump_mapping_num",
  mwExclusionPredicates = "exclude_predicates",
  mwMaxMatchPriority = "match_priority",
  mwIgnoreCase = "ignorecase",
}

local function read_legacy_globals(config)
  for legacy_key, config_key in pairs(legacy_map) do
    if vim.g[legacy_key] ~= nil then
      config[config_key] = copy(vim.g[legacy_key])
    end
  end
  if vim.g.mw_no_mappings then
    config.keymaps.preset = "none"
  end
end

local function normalize_history_add(value)
  if type(value) == "table" then
    return (value.search and "/" or "") .. (value.input and "@" or "")
  end
  if type(value) ~= "string" then
    return "/@"
  end
  return value
end

local function normalize_palette_count(value)
  local count = tonumber(value) or -1
  if count == 0 then
    return -1
  end
  return count
end

function M.normalize(opts)
  local config = copy(M.defaults)
  read_legacy_globals(config)
  config = vim.tbl_deep_extend("force", config, opts or {})

  config.auto_load = to_bool(config.auto_load, false)
  config.auto_save = to_bool(config.auto_save, true)
  config.history_add = normalize_history_add(config.history_add)
  config.palette_count = normalize_palette_count(config.palette_count)
  config.direct_group_jump_mapping_num = math.max(0, tonumber(config.direct_group_jump_mapping_num) or 0)
  config.match_priority = tonumber(config.match_priority) or -10
  config.keymaps = config.keymaps or {}
  config.keymaps.preset = config.keymaps.preset or "lazyvim"
  config.ui = vim.tbl_deep_extend("force", copy(M.defaults.ui), config.ui or {})

  if type(config.exclude_predicates) ~= "table" then
    config.exclude_predicates = { config.exclude_predicates }
  end
  if #config.exclude_predicates == 0 then
    config.exclude_predicates = { default_exclusion_predicate }
  end

  if type(config.palettes) ~= "table" then
    config.palettes = {}
  end

  return config
end

function M.resolve_palette(config)
  local palette, err = palettes.resolve(config.palette, config.palettes)
  if not palette then
    vim.notify(("mark.nvim: %s, falling back to original"):format(err), vim.log.levels.WARN)
    palette = palettes.resolve("original", config.palettes)
  end
  local count = (config.palette_count == -1) and #palette or math.max(0, config.palette_count)
  if count > #palette then
    count = #palette
  end
  return palette, count
end

function M.palette_names(config)
  return vim.tbl_keys(palettes.all(config.palettes))
end

return M
