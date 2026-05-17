vim.opt.runtimepath:prepend(vim.fn.getcwd())

local mark = require("mark")
mark.setup({ mark_only = true, auto_load = false, auto_save = false })

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

local function mapped(keys)
  local mapping = vim.fn.maparg(keys, "n", false, true)
  if type(mapping) ~= "table" or type(mapping.callback) ~= "function" then
    error(("normal mapping for %s is not registered"):format(keys), 2)
  end
  mapping.callback()
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
  reset_buffer("foo bar foo bar")
  define_marks()
  mapped("#")
  assert_cursor(1, 4, "# jumps forward to any color")
  mapped("n")
  assert_cursor(1, 12, "n continues within same color")

  vim.api.nvim_win_set_cursor(0, { 1, 10 })
  mapped("@")
  assert_cursor(1, 4, "@ jumps backward to any color")
  mapped("N")
  assert_cursor(1, 12, "N continues backward within same color")

  reset_buffer("foo XXX bar YYY foo ZZZ bar")
  define_marks()
  mapped("#")
  assert_cursor(1, 8, "# lands on bar")
  vim.api.nvim_win_set_cursor(0, { 1, 13 })
  mapped("n")
  assert_cursor(1, 24, "n stays on bar color after cursor leaves any mark")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  print(err)
  vim.cmd("cquit")
end
vim.cmd("qa!")
