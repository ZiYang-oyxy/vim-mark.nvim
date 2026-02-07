if vim.g.loaded_mark_lua then
  return
end

vim.g.loaded_mark_lua = 1

require("mark").setup()
