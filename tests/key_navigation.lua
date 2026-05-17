vim.opt.runtimepath:prepend(vim.fn.getcwd())

local mark = require("mark")
mark.setup({ keymaps = { preset = "none" }, auto_load = false, auto_save = false })

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(("%s: expected %q, got %q"):format(label, expected, actual), 2)
  end
end

local function assert_cursor(row, col, label)
  local cursor = vim.api.nvim_win_get_cursor(0)
  assert_equal(cursor[1], row, label .. " row")
  assert_equal(cursor[2], col, label .. " col")
end

local function reset_buffer(line)
  mark.clear_all()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function define_marks()
  mark.mark_regex({ group = 1, pattern = "foo" })
  mark.mark_regex({ group = 2, pattern = "bar" })
end

local function run()
  reset_buffer("foo bar foo")
  define_marks()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  assert(mark.search_current_mark(false, 1), "same-color forward search should succeed")
  assert_cursor(1, 8, "same-color forward skips other colors")

  reset_buffer("foo baz bar")
  define_marks()
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  assert(mark.search_word_or_selection_mark(false, 1), "all-color forward search should succeed")
  assert_cursor(1, 8, "all-color forward jumps to nearest existing mark")
  assert_equal(mark._state.patterns[3], "", "all-color forward does not add mark for unmatched word")

  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  assert(mark.search_word_or_selection_mark(true, 1), "all-color backward search should succeed")
  assert_cursor(1, 0, "all-color backward jumps to nearest existing mark")
  assert_equal(mark._state.patterns[3], "", "all-color backward does not add mark for unmatched word")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  print(err)
  vim.cmd("cquit")
end
vim.cmd("qa!")
