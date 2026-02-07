local M = {}

local function to_highlight_cmd(group_name, spec, is_override)
  local parts = {}
  for key, value in pairs(spec) do
    parts[#parts + 1] = ("%s=%s"):format(key, value)
  end
  table.sort(parts)
  local prefix = is_override and "highlight" or "highlight default"
  return ("%s %s %s"):format(prefix, group_name, table.concat(parts, " "))
end

function M.define_highlights(palette, count, is_override)
  for index = 1, count do
    vim.cmd(to_highlight_cmd(("MarkWord%d"):format(index), palette[index], is_override))
  end
  vim.cmd("highlight default link SearchSpecialSearchType MoreMsg")
  return count
end

function M.clear_highlights(from_index, to_index)
  if from_index > to_index then
    return
  end
  for index = from_index, to_index do
    vim.cmd(("highlight clear MarkWord%d"):format(index))
  end
end

local function evaluate_predicate_in_window(winid, predicate)
  return vim.api.nvim_win_call(winid, function()
    if type(predicate) == "function" then
      local ok, result = pcall(predicate)
      return ok and result
    end
    if type(predicate) == "string" and predicate ~= "" then
      local ok, result = pcall(vim.fn.eval, predicate)
      return ok and (result == 1 or result == true)
    end
    return false
  end)
end

local function is_excluded(winid, predicates)
  for _, predicate in ipairs(predicates or {}) do
    if evaluate_predicate_in_window(winid, predicate) then
      return true
    end
  end
  return false
end

local function ensure_window_matches(state, winid)
  local matches = state.window_matches[winid]
  if not matches then
    matches = {}
    state.window_matches[winid] = matches
  end
  if #matches > state.mark_num then
    for index = state.mark_num + 1, #matches do
      local id = matches[index]
      if id and id > 0 and vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_call(winid, function()
          pcall(vim.fn.matchdelete, id)
        end)
      end
      matches[index] = nil
    end
  end
  for index = 1, state.mark_num do
    matches[index] = matches[index] or 0
  end
  return matches
end

local function delete_match(winid, matches, index)
  local id = matches[index]
  if id and id > 0 and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_call(winid, function()
      pcall(vim.fn.matchdelete, id)
    end)
  end
  matches[index] = 0
end

local function set_match(winid, matches, index, expr, state, config, is_ignore_case_fn)
  local pattern = (is_ignore_case_fn(expr) and "\\c" or "\\C") .. expr
  local priority = config.match_priority - state.mark_num + index
  local id = vim.api.nvim_win_call(winid, function()
    local ok, match_id = pcall(vim.fn.matchadd, ("MarkWord%d"):format(index), pattern, priority)
    if ok then
      return match_id
    end
    return 0
  end)
  matches[index] = id or 0
end

function M.update_mark(state, config, is_ignore_case_fn, winid, indices, expr)
  if not vim.api.nvim_win_is_valid(winid) then
    state.window_matches[winid] = nil
    return
  end
  local matches = ensure_window_matches(state, winid)
  if is_excluded(winid, config.exclude_predicates) then
    for index = 1, state.mark_num do
      delete_match(winid, matches, index)
    end
    return
  end

  if indices and #indices > 0 then
    for _, index in ipairs(indices) do
      delete_match(winid, matches, index)
    end
    if expr and expr ~= "" and state.enabled then
      set_match(winid, matches, indices[1], expr, state, config, is_ignore_case_fn)
    end
    return
  end

  for index = 1, state.mark_num do
    delete_match(winid, matches, index)
    local pattern = state.patterns[index]
    if state.enabled and pattern and pattern ~= "" then
      set_match(winid, matches, index, pattern, state, config, is_ignore_case_fn)
    end
  end
end

function M.update_scope(state, config, is_ignore_case_fn, indices, expr)
  local active_wins = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    active_wins[winid] = true
    M.update_mark(state, config, is_ignore_case_fn, winid, indices, expr)
  end
  for winid in pairs(state.window_matches) do
    if not active_wins[winid] then
      state.window_matches[winid] = nil
    end
  end
end

return M
