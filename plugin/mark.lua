if vim.g.loaded_mark_lua then
  return
end

vim.g.loaded_mark_lua = 1

local function should_skip_autosetup_for_lazy()
  local ok, lazy_config = pcall(require, "lazy.core.config")
  if not ok or type(lazy_config) ~= "table" then
    return false
  end
  local plugins = lazy_config.plugins
  if type(plugins) ~= "table" then
    return false
  end

  local plugin = plugins["mark.nvim"] or plugins["inkarkat/vim-mark"]
  if type(plugin) ~= "table" then
    return false
  end

  return plugin.opts ~= nil or plugin.config ~= nil
end

if not should_skip_autosetup_for_lazy() then
  require("mark").setup()
end
