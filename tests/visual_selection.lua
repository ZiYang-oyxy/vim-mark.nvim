vim.opt.runtimepath:prepend(vim.fn.getcwd())

local mark = require("mark")
mark.setup({ keymaps = { preset = "none" }, auto_load = false, auto_save = false })

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(("%s: expected %q, got %q"):format(label, expected, actual), 2)
  end
end

local function reset_buffer(line)
  mark.clear_all()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
end

local function run()
  reset_buffer("abc中文def")
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  vim.cmd("normal! vl")
  mark.mark_word_or_selection({ group = 1 })
  assert_equal(mark._state.patterns[1], "中文", "forward charwise Chinese visual selection")

  reset_buffer("abc中文def")
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  vim.cmd("normal! vh")
  mark.mark_word_or_selection({ group = 1 })
  assert_equal(mark._state.patterns[1], "中文", "backward charwise Chinese visual selection")

  reset_buffer("abcXYZdef")
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  vim.cmd("normal! vll")
  mark.mark_word_or_selection({ group = 1 })
  assert_equal(mark._state.patterns[1], "XYZ", "ascii visual selection")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  print(err)
  vim.cmd("cquit")
end
vim.cmd("qa!")
