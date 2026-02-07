local M = {}

local function get_location()
  return {
    tab = vim.api.nvim_tabpage_get_number(0),
    win = vim.api.nvim_get_current_win(),
    buf = vim.api.nvim_get_current_buf(),
  }
end

local function same_location(a, b)
  return a.tab == b.tab and a.win == b.win and a.buf == b.buf
end

local function same_pos(a, b)
  return a[1] == b[1] and a[2] == b[2]
end

local function clear_location_and_position(cascade)
  cascade.location = {}
  cascade.position = {}
end

local function switch_to_next_group(cascade, group_index, is_backward)
  cascade.group_index = group_index
  cascade.is_backward = is_backward
  clear_location_and_position(cascade)
end

local function set_cascade_from_current_mark(cascade, current_mark_fn)
  local _, position, group_index = current_mark_fn()
  cascade.location = get_location()
  cascade.position = position
  cascade.group_index = group_index
end

local function cascade_to_next(cascade, ctx, count, is_stop_before_cascade, is_backward)
  local next_group = ctx.next_used_group_index(is_backward, false, cascade.group_index, 1)
  if not next_group then
    vim.notify(
      ("Cascaded search ended with %s used group"):format(is_backward and "first" or "last"),
      vim.log.levels.WARN
    )
    return false
  end
  cascade.visited_buffers[vim.api.nvim_get_current_buf()] = cascade.group_index
  if is_stop_before_cascade then
    cascade.stop_index = next_group
    vim.notify("Cascaded search reached last match of current group", vim.log.levels.WARN)
    return true
  end
  switch_to_next_group(cascade, next_group, is_backward)
  return M.next(cascade, ctx, count, is_stop_before_cascade, is_backward)
end

function M.start(cascade, ctx, count, is_stop_before_cascade)
  cascade.is_backward = -1
  cascade.stop_index = -1
  cascade.visited_buffers = {}

  set_cascade_from_current_mark(cascade, ctx.current_mark)
  local current_group = cascade.group_index
  if (count == 0 and current_group ~= -1) or (count > 0 and current_group == count) then
    return true
  end

  if not ctx.search_group_mark(count, 1, false, true) then
    if count > 0 then
      return false
    end
    local first_used = ctx.next_used_group_index(false, false, 0, 1)
    if not first_used or not ctx.search_group_mark(first_used, 1, false, true) then
      return false
    end
  end
  set_cascade_from_current_mark(cascade, ctx.current_mark)
  return true
end

function M.next(cascade, ctx, count, is_stop_before_cascade, is_backward)
  if cascade.is_backward == -1 then
    cascade.is_backward = is_backward
  end
  if cascade.group_index == -1 then
    vim.notify("No cascaded search defined", vim.log.levels.ERROR)
    return false
  end

  local location = get_location()
  local current_buf = vim.api.nvim_get_current_buf()
  if cascade.visited_buffers[current_buf] == cascade.group_index and not same_location(cascade.location, location) then
    cascade.location = location
    return cascade_to_next(cascade, ctx, count, false, is_backward)
  end

  if cascade.stop_index ~= -1 then
    if same_location(cascade.location, location) then
      switch_to_next_group(cascade, cascade.stop_index, is_backward)
    else
      clear_location_and_position(cascade)
    end
    cascade.stop_index = -1
  elseif cascade.is_backward ~= is_backward and same_location(cascade.location, location) and same_pos(cascade.position, vim.api.nvim_win_get_cursor(0)) then
    return cascade_to_next(cascade, ctx, count, is_stop_before_cascade, is_backward)
  end

  local save_wrapscan = vim.o.wrapscan
  vim.o.wrapscan = true
  local save_cursor = vim.api.nvim_win_get_cursor(0)
  local ok = ctx.search_group_mark(cascade.group_index, count, is_backward, true)
  if not ok then
    vim.o.wrapscan = save_wrapscan
    return cascade_to_next(cascade, ctx, count, is_stop_before_cascade, is_backward)
  end

  local now = get_location()
  local cursor = vim.api.nvim_win_get_cursor(0)
  if same_location(cascade.location, now) and same_pos(cascade.position, cursor) then
    if cascade.is_backward == is_backward then
      vim.api.nvim_win_set_cursor(0, save_cursor)
      vim.o.wrapscan = save_wrapscan
      return cascade_to_next(cascade, ctx, count, is_stop_before_cascade, is_backward)
    end
    local saved = vim.api.nvim_win_get_cursor(0)
    local _ = ctx.search_group_mark(cascade.group_index, 1, is_backward, true)
    cascade.position = vim.api.nvim_win_get_cursor(0)
    cascade.is_backward = is_backward
    vim.api.nvim_win_set_cursor(0, saved)
    vim.o.wrapscan = save_wrapscan
    return true
  end

  if vim.tbl_isempty(cascade.location) and vim.tbl_isempty(cascade.position) then
    set_cascade_from_current_mark(cascade, ctx.current_mark)
  end

  vim.o.wrapscan = save_wrapscan
  return true
end

return M
