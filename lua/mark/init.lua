local config_mod = require("mark.config")
local state_mod = require("mark.state")
local highlight = require("mark.highlight")
local persist = require("mark.persist")
local cascade = require("mark.cascade")

local M = {}

M._state = state_mod.new()
M._config = nil
M._setup_done = false
M._autocmd_group = nil
M._applied_keymaps = {}
M._is_internal_load = false
M._updating_windows = false
M._search_progress_cache = {}
M._search_cmd = {
  active = false,
  source_winid = nil,
  preview_winid = nil,
  preview_match_id = 0,
  last_cmdline = "",
}
local mark_list_ns = vim.api.nvim_create_namespace("mark_list")
local mark_list_winid = nil
local echo_messages_enabled = true

local function echo_message(chunks, history, opts)
  if not echo_messages_enabled then
    return
  end
  vim.api.nvim_echo(chunks, history or false, opts or {})
end

local function state()
  return M._state
end

local function config()
  return M._config
end

local function trim_message(message)
  local max_length = math.max(1, math.floor(vim.o.columns / 2))
  if #message > max_length then
    return message:sub(1, max_length) .. "..."
  end
  return message
end

local function close_mark_list_window()
  if mark_list_winid and vim.api.nvim_win_is_valid(mark_list_winid) then
    pcall(vim.api.nvim_win_close, mark_list_winid, true)
  end
  mark_list_winid = nil
end

local function warn(message)
  vim.notify(("mark.nvim: %s"):format(message), vim.log.levels.WARN)
end

local function report_error(message)
  vim.notify(("mark.nvim: %s"):format(message), vim.log.levels.ERROR)
end

local function define_preview_highlight()
  vim.cmd("highlight default link MarkSearchPreview Search")
end

local function escape_text(text)
  return text:gsub("\\", "\\\\"):gsub("%^", "\\^"):gsub("%$", "\\$"):gsub("%.", "\\."):gsub("%*", "\\*"):gsub("%[", "\\[")
    :gsub("~", "\\~"):gsub("\n", "\\n")
end

local function is_ignore_case(expr)
  local cfg = config()
  local option = cfg.ignorecase
  if option == nil then
    option = vim.o.ignorecase
  end
  return option and not expr:find("\\C")
end

local function with_window_update(fn)
  local previous_state = M._updating_windows
  M._updating_windows = true
  local ok, result1, result2, result3 = pcall(fn)
  M._updating_windows = previous_state
  if not ok then
    report_error(("window update failed: %s"):format(result1))
    return nil
  end
  return result1, result2, result3
end

local function refresh_scope(indices, expr)
  return with_window_update(function()
    return highlight.update_scope(state(), config(), is_ignore_case, indices, expr)
  end)
end

local function refresh_current_window(winid, indices, expr)
  return with_window_update(function()
    return highlight.update_mark(state(), config(), is_ignore_case, winid, indices, expr)
  end)
end

local function normalize_magic(pattern)
  if not pattern or pattern == "" then
    return ""
  end
  return pattern
end

local function is_valid_regex(pattern)
  local ok = pcall(vim.regex, pattern)
  return ok
end

local function clear_search_preview()
  local search_cmd = M._search_cmd
  local winid = search_cmd.preview_winid
  local match_id = search_cmd.preview_match_id or 0
  if winid and match_id > 0 and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_call(winid, function()
      pcall(vim.fn.matchdelete, match_id)
    end)
  end
  search_cmd.preview_winid = nil
  search_cmd.preview_match_id = 0
end

local function reset_search_cmd_state()
  local search_cmd = M._search_cmd
  search_cmd.active = false
  search_cmd.source_winid = nil
  search_cmd.last_cmdline = ""
  clear_search_preview()
end

local function update_search_preview(pattern)
  local search_pattern = pattern or ""
  clear_search_preview()
  if search_pattern == "" then
    return
  end
  if not is_valid_regex(search_pattern) then
    return
  end

  local search_cmd = M._search_cmd
  local winid = search_cmd.source_winid
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    winid = vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(winid) then
      return
    end
    search_cmd.source_winid = winid
  end

  local compiled = (is_ignore_case(search_pattern) and "\\c" or "\\C") .. normalize_magic(search_pattern)
  local priority = config().match_priority + math.max(state().mark_num, 1) + 100
  local match_id = vim.api.nvim_win_call(winid, function()
    local ok, id = pcall(vim.fn.matchadd, "MarkSearchPreview", compiled, priority)
    if ok then
      return id
    end
    return 0
  end)
  if match_id and match_id > 0 then
    search_cmd.preview_winid = winid
    search_cmd.preview_match_id = match_id
  end
end

local function clear_native_search_highlight()
  pcall(vim.cmd, "silent! nohlsearch")
end

local function leave_visual_mode()
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "n", false)
end

local function current_mode_head()
  return vim.fn.mode(1):sub(1, 1)
end

local function is_visual_mode()
  local mode_head = current_mode_head()
  return mode_head == "v" or mode_head == "V" or mode_head == "\22"
end

local function visual_mode_not_supported_warning()
  vim.notify("Visual block mode is not supported for mark.nvim mark.", vim.log.levels.WARN, {
    title = "mark.nvim Visual",
  })
end

local function get_current_visual_selection()
  local mode_now = vim.fn.mode(1)
  local visual_type = mode_now:sub(1, 1)
  if visual_type ~= "v" and visual_type ~= "V" and visual_type ~= "\22" then
    visual_type = vim.fn.visualmode()
  end

  if visual_type == "\22" then
    return nil, "block_not_supported"
  end

  local anchor_pos = vim.fn.getpos("v")
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local start_row, start_col = anchor_pos[2] - 1, anchor_pos[3] - 1
  local end_row, end_col = cursor_pos[1] - 1, cursor_pos[2]

  if start_row < 0 or end_row < 0 then
    return ""
  end

  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  if visual_type == "V" then
    start_col = 0
    local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1] or ""
    end_col = #end_line
  else
    end_col = end_col + 1
  end

  local chunks = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  local selection = table.concat(chunks, "\n")
  selection = selection:gsub("[\n\r]", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
  return selection
end

local function get_visual_selection_as_literal_pattern()
  local selection, err = get_current_visual_selection()
  if err then
    return nil, err
  end
  return escape_text(selection)
end

local function get_visual_selection_as_regexp()
  local selection, err = get_current_visual_selection()
  if err then
    return nil, err
  end
  return selection
end

local function get_visual_selection_as_literal_whitespace_indifferent_pattern()
  local selection, err = get_current_visual_selection()
  if err then
    return nil, err
  end
  return escape_text(selection):gsub("%s+", "\\_s\\+")
end

local function with_visual_pattern(pattern_getter, apply_pattern)
  local should_leave_visual = is_visual_mode()
  local pattern, err = pattern_getter()
  if err == "block_not_supported" then
    visual_mode_not_supported_warning()
    if should_leave_visual then
      leave_visual_mode()
    end
    return false, 0
  end

  local ok, mark_group = false, 0
  if pattern and pattern ~= "" then
    ok, mark_group = apply_pattern(pattern)
  end

  if should_leave_visual then
    leave_visual_mode()
  end
  return ok, mark_group
end

local function split_into_alternatives(pattern)
  if pattern == "" then
    return {}
  end
  local alternatives = {}
  local current = {}
  local depth = 0
  local in_char_class = false
  local index = 1
  while index <= #pattern do
    local char = pattern:sub(index, index)
    local next_char = pattern:sub(index + 1, index + 1)
    if in_char_class then
      current[#current + 1] = char
      if char == "\\" and next_char ~= "" then
        current[#current + 1] = next_char
        index = index + 2
      else
        if char == "]" then
          in_char_class = false
        end
        index = index + 1
      end
    elseif char == "[" then
      in_char_class = true
      current[#current + 1] = char
      index = index + 1
    elseif char == "\\" and next_char ~= "" then
      if next_char == "(" then
        depth = depth + 1
        current[#current + 1] = "\\("
        index = index + 2
      elseif next_char == ")" then
        depth = math.max(depth - 1, 0)
        current[#current + 1] = "\\)"
        index = index + 2
      elseif next_char == "|" and depth == 0 then
        alternatives[#alternatives + 1] = table.concat(current)
        current = {}
        index = index + 2
      else
        current[#current + 1] = "\\" .. next_char
        index = index + 2
      end
    else
      current[#current + 1] = char
      index = index + 1
    end
  end
  alternatives[#alternatives + 1] = table.concat(current)
  return alternatives
end

local function projected_match_length(pattern)
  local sanitized = pattern
    :gsub("\\[<>]", "")
    :gsub("\\.", "x")
    :gsub("\\_", "")
    :gsub("\\|", "")
  return #sanitized
end

local function cycle(from_index)
  local st = state()
  local current = from_index or st.cycle
  local new_cycle = current + 1
  if new_cycle > st.mark_num then
    new_cycle = 1
  end
  st.cycle = new_cycle
  return current
end

local function free_group_index()
  return state_mod.free_group_index(state())
end

local function get_next_group_index()
  local free = free_group_index()
  if free then
    return free
  end
  return state().cycle
end

local function get_alternative_count(pattern)
  if pattern == "" then
    return 0
  end
  return #split_into_alternatives(pattern)
end

local function render_name(group_num)
  local name = state().names[group_num]
  return (name and name ~= "") and (":" .. name) or ""
end

local function render_mark(group_num)
  return ("mark-%d%s"):format(group_num, render_name(group_num))
end

local function enrich_search_type(search_type)
  if search_type ~= "mark*" then
    return search_type
  end
  local _, _, index = M.current_mark()
  if index > 0 then
    return ("mark*%d%s"):format(index, render_name(index))
  end
  return search_type
end

local function print_mark_group(next_group_index)
  local st = state()
  local chunks = {}
  for index = 1, st.mark_num do
    local marker = ""
    if st.last_search == index then
      marker = marker .. "/"
    end
    if index == next_group_index then
      marker = marker .. ">"
    end
    local alt_count = get_alternative_count(st.patterns[index])
    local alt_marker = ""
    if alt_count > 0 then
      alt_marker = (alt_count > 1 and tostring(alt_count) or "") .. "*"
    end
    chunks[#chunks + 1] = (" %s%s%2d "):format(marker, alt_marker, index)
  end
  echo_message({ { table.concat(chunks, ""), "Normal" } }, false, {})
end

local function query_group_num()
  local st = state()
  echo_message({ { "Mark?", "Question" } }, false, {})
  local next_group = get_next_group_index()
  print_mark_group(next_group)
  local result = vim.fn.input(("Group [1-%d, default %d]: "):format(st.mark_num, next_group))
  if result == "" then
    return next_group
  end
  local num = tonumber(result)
  if not num then
    return -1
  end
  return math.floor(num)
end

local function save_marks(slot)
  if M._is_internal_load then
    return 1
  end
  return persist.save(state(), slot)
end

local function set_pattern(index, pattern)
  local st = state()
  st.patterns[index] = pattern
  if config().auto_save then
    save_marks()
  end
end

local function mark_enable(enable, suppress_refresh)
  local st = state()
  local normalized = enable and true or false
  if st.enabled == normalized then
    return
  end
  st.enabled = normalized
  if config().auto_save then
    vim.g.MARK_ENABLED = normalized and 1 or 0
  end
  if not suppress_refresh then
    refresh_scope()
  end
end

local function enable_and_mark_scope(indices, expr)
  if state().enabled then
    refresh_scope(indices, expr)
  else
    mark_enable(true, false)
  end
end

local function set_mark(index, regexp, last_search_override)
  local st = state()
  if last_search_override ~= nil and st.last_search == index then
    st.last_search = last_search_override
  end
  set_pattern(index, regexp)
  enable_and_mark_scope({ index }, regexp)
end

local function clear_mark(index)
  set_mark(index, "", -1)
end

local function echo_mark(group_num, regexp)
  local search_type = render_mark(group_num)
  local message = "/" .. regexp
  echo_message({
    { search_type, "SearchSpecialSearchType" },
    { trim_message(message), "Normal" },
  }, false, {})
end

local function echo_mark_cleared(group_num)
  echo_message({
    { render_mark(group_num), "SearchSpecialSearchType" },
    { " cleared", "Normal" },
  }, false, {})
end

local function add_history(pattern)
  local hist = config().history_add
  if hist:find("/", 1, true) then
    pcall(vim.fn.histadd, "/", pattern)
  end
  if hist:find("@", 1, true) then
    pcall(vim.fn.histadd, "@", pattern)
  end
end

local function parse_mark_argument(argument)
  local input = vim.trim(argument or "")
  if input == "" then
    return "", nil
  end
  local pattern_text = input
  local name
  local as_start, _, as_value = input:find("%s+as%s*(.+)$")
  if as_start then
    pattern_text = vim.trim(input:sub(1, as_start - 1))
    name = vim.trim(as_value or "")
  end
  local pattern
  if pattern_text:match("^/.*/$") then
    pattern = pattern_text:sub(2, -2):gsub("\\/", "/")
  else
    local escaped = escape_text(pattern_text)
    if pattern_text:match("^%k+$") then
      pattern = "\\<" .. escaped .. "\\>"
    else
      pattern = escaped
    end
  end
  return normalize_magic(pattern), name
end

local search_messages_enabled = true

local function no_mark_error_message()
  if not search_messages_enabled then
    return
  end
  report_error("No marks defined")
end

local function error_message(search_type, search_pattern, is_backward)
  if not search_messages_enabled then
    return
  end
  if vim.o.wrapscan then
    report_error(("%s not found: %s"):format(search_type, search_pattern))
  else
    report_error(("%s search hit %s without match for: %s"):format(
      search_type,
      is_backward and "TOP" or "BOTTOM",
      search_pattern
    ))
  end
end

local function all_mark_pattern()
  local patterns = {}
  for index = 1, state().mark_num do
    if state().patterns[index] ~= "" then
      patterns[#patterns + 1] = state().patterns[index]
    end
  end
  return table.concat(patterns, "\\|")
end

local function search_progress_cache_for_buffer(bufnr)
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache = M._search_progress_cache[bufnr]
  if cache and cache.changedtick == changedtick then
    return cache
  end
  cache = {
    changedtick = changedtick,
    by_pattern = {},
  }
  M._search_progress_cache[bufnr] = cache
  return cache
end

local function collect_match_positions(pattern)
  if not pattern or pattern == "" then
    return nil
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local compiled_pattern = (is_ignore_case(pattern) and "\\c" or "\\C") .. normalize_magic(pattern)
  local cache = search_progress_cache_for_buffer(bufnr)
  local cached = cache.by_pattern[compiled_pattern]
  if cached then
    return cached
  end

  local ok, result = pcall(vim.fn.matchbufline, bufnr, compiled_pattern, 1, "$")
  if not ok or type(result) ~= "table" then
    return nil
  end

  local positions = {}
  local index_by_position = {}
  for _, match in ipairs(result) do
    local line = tonumber(match.lnum) or 0
    local byteidx = tonumber(match.byteidx) or -1
    if line > 0 and byteidx >= 0 then
      local col = byteidx + 1
      positions[#positions + 1] = { line, col }
      index_by_position[("%d:%d"):format(line, col)] = #positions
    end
  end

  local entry = {
    positions = positions,
    index_by_position = index_by_position,
  }
  cache.by_pattern[compiled_pattern] = entry
  return entry
end

local function position_index(positions, target)
  if not positions or not target or #target ~= 2 then
    return nil
  end
  local key = ("%d:%d"):format(target[1], target[2])
  local mapped_index = positions.index_by_position and positions.index_by_position[key]
  if mapped_index then
    return mapped_index
  end
  if positions.positions then
    for index, position in ipairs(positions.positions) do
      if position[1] == target[1] and position[2] == target[2] then
        return index
      end
    end
  end
  return nil
end

local function search_progress_suffix()
  local group_pattern, group_position = M.current_mark()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_position = group_position
  if type(current_position) ~= "table" or #current_position ~= 2 then
    current_position = { cursor[1], cursor[2] + 1 }
  end

  local group_matches
  if type(group_pattern) == "string" and group_pattern ~= "" then
    group_matches = collect_match_positions(group_pattern)
  end
  local group_current = position_index(group_matches, current_position) or 0
  local group_total = (group_matches and group_matches.positions) and #group_matches.positions or 0
  local cfg = config() or {}
  if not cfg.search_global_progress then
    return ("(%d/%d)"):format(group_current, group_total)
  end

  local global_matches = collect_match_positions(all_mark_pattern())
  local global_current = position_index(global_matches, current_position) or 0
  local global_total = (global_matches and global_matches.positions) and #global_matches.positions or 0
  return ("(%d/%d) (%d/%d)"):format(group_current, group_total, global_current, global_total)
end

local function safe_search_progress_suffix()
  local ok, suffix = pcall(search_progress_suffix)
  if not ok or type(suffix) ~= "string" or suffix == "" then
    local cfg = config() or {}
    return cfg.search_global_progress and "(0/0) (0/0)" or "(0/0)"
  end
  return suffix
end

local function echo_search_progress(progress_suffix)
  if not search_messages_enabled then
    return
  end
  local cfg = config() or {}
  local fallback = cfg.search_global_progress and "(0/0) (0/0)" or "(0/0)"
  local message = (type(progress_suffix) == "string" and progress_suffix ~= "") and progress_suffix or fallback
  echo_message({ { message, "Normal" } }, false, {})
end

local function same_position(a, b)
  return #a == 2 and #b == 2 and a[1] == b[1] and a[2] == b[2]
end

local function search(pattern, count, is_backward, current_mark_position, search_type)
  if pattern == "" then
    no_mark_error_message()
    return false
  end
  local requested_count = math.max(1, math.floor(tonumber(count) or 1))
  local search_pattern = (is_ignore_case(pattern) and "\\c" or "\\C") .. pattern
  local remaining = requested_count
  local is_wrapped = false
  local is_match = false
  local line = 0
  local col = 0
  local safety_limit = math.max(1000, requested_count * 32)
  local iterations = 0
  while remaining > 0 do
    iterations = iterations + 1
    if iterations > safety_limit then
      if search_messages_enabled then
        report_error(("Search aborted after %d iterations (non-progress loop guard)"):format(iterations))
      end
      return false
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local prev_line, prev_col = cursor[1], cursor[2] + 1
    local pos = vim.fn.searchpos(search_pattern, is_backward and "b" or "")
    line, col = pos[1], pos[2]
    if is_backward and line > 0 and same_position({ line, col }, current_mark_position) and remaining == requested_count then
      if is_match then
        is_wrapped = true
        break
      end
      is_match = true
    elseif line > 0 then
      is_match = true
      remaining = remaining - 1
      if not is_backward and (prev_line > line or (prev_line == line and prev_col >= col)) then
        is_wrapped = true
      elseif is_backward and (prev_line < line or (prev_line == line and prev_col <= col)) then
        is_wrapped = true
      end
    else
      break
    end
  end

  local is_stuck_at_current_mark = line > 0 and same_position({ line, col }, current_mark_position) and requested_count == 1
  if line > 0 and not is_stuck_at_current_mark then
    vim.cmd([[normal! zv]])
    mark_enable(true, false)
    echo_search_progress(safe_search_progress_suffix())
    return true
  end

  if is_match then
    -- Keep the cursor at the last examined position; this is simpler and avoids
    -- edge cases with jump / view restoration in headless and embedded UIs.
  end
  mark_enable(true, false)
  if line > 0 and is_stuck_at_current_mark and is_wrapped then
    echo_search_progress(safe_search_progress_suffix())
    return true
  end
  error_message(search_type, pattern, is_backward)
  return false
end

local function any_mark_pattern()
  return all_mark_pattern()
end

local function do_mark(group_num, regexp, name, opts)
  local st = state()
  if st.mark_num <= 0 then
    report_error("No mark highlightings defined")
    return false, 0
  end

  local group = group_num or 0
  local pattern_supplied = opts and opts.pattern_supplied or false
  local interactive = opts and opts.interactive ~= false
  if group > st.mark_num then
    if not interactive then
      report_error(("Only %d mark highlight groups"):format(st.mark_num))
      return false, 0
    end
    group = query_group_num()
    if group < 1 or group > st.mark_num then
      return false, 0
    end
  end

  local pattern = regexp or ""
  if pattern == "" then
    if group == 0 then
      if pattern_supplied then
        report_error("Do not pass empty pattern to disable all marks")
        return false, 0
      end
      mark_enable(false, false)
      echo_message({ { "All marks disabled", "Normal" } }, false, {})
      return true, 0
    end
    clear_mark(group)
    if name ~= nil then
      st.names[group] = name
    end
    echo_mark_cleared(group)
    return true, 0
  end

  if group == 0 then
    for index = 1, st.mark_num do
      if pattern == st.patterns[index] then
        clear_mark(index)
        if name ~= nil then
          st.names[index] = name
        end
        echo_mark_cleared(index)
        return true, 0
      end
    end
  else
    local existing = st.patterns[group]
    if existing ~= "" then
      local alternatives = split_into_alternatives(existing)
      local found_index = nil
      for index, alternative in ipairs(alternatives) do
        if alternative == pattern then
          found_index = index
          break
        end
      end
      if found_index then
        table.remove(alternatives, found_index)
        pattern = table.concat(alternatives, "\\|")
        if pattern == "" then
          clear_mark(group)
          if name ~= nil then
            st.names[group] = name
          end
          echo_mark_cleared(group)
          return true, 0
        end
      else
        alternatives[#alternatives + 1] = pattern
        table.sort(alternatives, function(a, b)
          return projected_match_length(a) > projected_match_length(b)
        end)
        pattern = table.concat(alternatives, "\\|")
      end
    end
  end

  add_history(pattern)

  local index
  if group == 0 then
    local free = free_group_index()
    if free then
      cycle(free)
      index = free
      set_mark(index, pattern, nil)
    else
      index = cycle()
      set_mark(index, pattern, -1)
    end
  else
    index = group
    set_mark(index, pattern, index)
  end

  if name ~= nil then
    st.names[index] = name
  end
  echo_mark(index, pattern)
  return true, index
end

local function do_mark_and_set_current(group_num, regexp, name, opts)
  if regexp and regexp ~= "" and not is_valid_regex(regexp) then
    report_error(("Invalid regular expression: %s"):format(regexp))
    return false, 0
  end
  local ok, mark_group = do_mark(group_num, regexp, name, opts)
  if ok and mark_group > 0 then
    state().last_search = mark_group
  end
  return ok, mark_group
end

function M.current_mark()
  local st = state()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local col0 = cursor[2]

  local function find_covering_match(pattern)
    local start_col = 0
    local line_len = #line
    while start_col <= line_len do
      local result = vim.fn.matchstrpos(line, pattern, start_col)
      local match_start = tonumber(result[2]) or -1
      local match_end = tonumber(result[3]) or -1
      if match_start < 0 or match_end < 0 then
        return nil
      end
      if col0 >= match_start and col0 < match_end then
        return match_start + 1
      end
      if match_end > match_start then
        start_col = match_end
      else
        start_col = match_start + 1
      end
    end
    return nil
  end

  for index = st.mark_num, 1, -1 do
    local pattern = st.patterns[index]
    if pattern ~= "" then
      local compiled = (is_ignore_case(pattern) and "\\c" or "\\C") .. normalize_magic(pattern)
      local start_col = find_covering_match(compiled)
      if start_col then
        return pattern, { cursor[1], start_col }, index
      end
    end
  end
  return "", {}, -1
end

function M.mark_word(options)
  local opts = options or {}
  local group_num = opts.group or 0
  local mark_whole_word_only = opts.partial and false or true
  local regexp = (group_num == 0) and M.current_mark() or ""
  if type(regexp) == "table" then
    regexp = regexp[1]
  end
  if regexp == "" then
    local cword = vim.fn.expand("<cword>")
    if cword ~= "" then
      regexp = escape_text(cword)
      if cword:match("^%k+$") and mark_whole_word_only then
        regexp = "\\<" .. regexp .. "\\>"
      end
    end
  end
  if regexp == "" then
    return false, 0
  end
  return do_mark(group_num, regexp, nil, { pattern_supplied = true, interactive = true })
end

function M.mark_word_or_selection(options)
  if is_visual_mode() then
    local opts = options or {}
    return with_visual_pattern(get_visual_selection_as_literal_pattern, function(pattern)
      return do_mark(opts.group or 0, pattern, nil, {
        pattern_supplied = true,
        interactive = true,
      })
    end)
  end
  return M.mark_word(options)
end

function M.mark_visual_literal(options)
  local opts = options or {}
  return with_visual_pattern(get_visual_selection_as_literal_pattern, function(pattern)
    return do_mark(opts.group or 0, pattern, nil, {
      pattern_supplied = true,
      interactive = true,
    })
  end)
end

function M.mark_visual_whitespace_indifferent(options)
  local opts = options or {}
  return with_visual_pattern(get_visual_selection_as_literal_whitespace_indifferent_pattern, function(pattern)
    return do_mark(opts.group or 0, pattern, nil, {
      pattern_supplied = true,
      interactive = true,
    })
  end)
end

function M.mark_visual_regex(options)
  local opts = options or {}
  return with_visual_pattern(get_visual_selection_as_regexp, function(pattern)
    return do_mark_and_set_current(opts.group or 0, normalize_magic(pattern), nil, {
      pattern_supplied = true,
      interactive = true,
    })
  end)
end

function M.mark_regex(options)
  local opts = options or {}
  local group_num = opts.group or 0
  local preset = opts.pattern or ""
  local regexp = preset
  if regexp == "" then
    regexp = vim.fn.input("Input pattern to mark: ", preset)
  end
  if regexp == "" then
    return false, 0
  end
  return do_mark_and_set_current(group_num, normalize_magic(regexp), nil, {
    pattern_supplied = true,
    interactive = true,
  })
end

function M.clear(group_num)
  local group = group_num or 0
  if group > 0 then
    return do_mark(group, "", nil, { pattern_supplied = false, interactive = true })
  end
  local mark_text = M.current_mark()
  if type(mark_text) == "table" then
    mark_text = mark_text[1]
  end
  if mark_text == "" then
    return do_mark(0, nil, nil, { pattern_supplied = false, interactive = true })
  end
  return do_mark(0, mark_text, nil, { pattern_supplied = true, interactive = true })
end

function M.clear_all()
  local st = state()
  local indices = {}
  for index = 1, st.mark_num do
    if st.patterns[index] ~= "" then
      set_pattern(index, "")
      indices[#indices + 1] = index
    end
  end
  st.last_search = -1
  mark_enable(false, true)
  if #indices > 0 then
    refresh_scope(indices, "")
    echo_message({ { ("Cleared all %d marks"):format(#indices), "Normal" } }, false, {})
  else
    echo_message({ { "All marks cleared", "Normal" } }, false, {})
  end
end

function M.toggle()
  if state().enabled then
    mark_enable(false, false)
    echo_message({ { "Disabled marks", "Normal" } }, false, {})
  else
    mark_enable(true, false)
    local count = M.get_count()
    echo_message({ { ("Enabled %smarks"):format(count > 0 and (count .. " ") or ""), "Normal" } }, false, {})
  end
end

function M.search_current_mark(is_backward, count)
  local st = state()
  local result = false
  local mark_text, mark_position, mark_index = M.current_mark()
  local effective_count = count or vim.v.count1
  if mark_text == "" then
    if st.last_search == -1 then
      result = M.search_any_mark(is_backward, effective_count)
      local _, _, current_index = M.current_mark()
      st.last_search = current_index
    else
      result = search(st.patterns[st.last_search], effective_count, is_backward, {}, render_mark(st.last_search))
    end
  else
    local suffix = (mark_index == st.last_search) and "" or "!"
    result = search(mark_text, effective_count, is_backward, mark_position, render_mark(mark_index) .. suffix)
    st.last_search = mark_index
  end
  return result
end

function M.search_group_mark(group_num, count, is_backward, is_set_last_search, interactive)
  local st = state()
  local mark_index
  local mark_text
  local mark_position = {}

  local group = group_num or 0
  if group == 0 then
    if st.last_search == -1 then
      local current_text, current_position, current_index = M.current_mark()
      if current_text == "" then
        return false
      end
      mark_index = current_index
      mark_text = current_text
      mark_position = current_position
    else
      mark_index = st.last_search
      mark_text = st.patterns[mark_index]
    end
  else
    if group > st.mark_num then
      if interactive then
        group = query_group_num()
      else
        report_error(("Only %d mark highlight groups"):format(st.mark_num))
        return false
      end
      if group < 1 or group > st.mark_num then
        return false
      end
    end
    mark_index = group
    mark_text = st.patterns[mark_index]
  end

  local suffix = (mark_index == st.last_search) and "" or "!"
  local result = search(mark_text, count, is_backward, mark_position, render_mark(mark_index) .. suffix)
  if is_set_last_search then
    st.last_search = mark_index
  end
  return result
end

function M.search_next_group(count, is_backward)
  local st = state()
  local group_index
  if st.last_search == -1 then
    local mark_text, _, mark_index = M.current_mark()
    if mark_text == "" then
      group_index = get_next_group_index()
    else
      group_index = mark_index
    end
  else
    group_index = st.last_search
  end

  local next_group = state_mod.next_used_group_index(st, is_backward, true, group_index, count)
  if not next_group then
    report_error(("No %s mark group%s used"):format(
      (count == 1 and "" or tostring(count) .. " ") .. (is_backward and "previous" or "next"),
      count == 1 and "" or "s"
    ))
    return false
  end
  return M.search_group_mark(next_group, 1, is_backward, true, true)
end

function M.search_any_mark(is_backward, count)
  local _, mark_position = M.current_mark()
  local mark_text = any_mark_pattern()
  state().last_search = -1
  return search(mark_text, count or vim.v.count1, is_backward, mark_position, "mark*")
end

function M.search_next(is_backward, search_kind, count)
  local mark_text = M.current_mark()
  if type(mark_text) == "table" then
    mark_text = mark_text[1]
  end
  if mark_text == "" then
    return false
  end
  local effective_count = count or vim.v.count1
  if search_kind == "current" then
    M.search_current_mark(is_backward, effective_count)
  elseif search_kind == "any" then
    M.search_any_mark(is_backward, effective_count)
  else
    if state().last_search == -1 then
      M.search_any_mark(is_backward, effective_count)
    else
      M.search_current_mark(is_backward, effective_count)
    end
  end
  return true
end

function M.to_list()
  return persist.serialize(state())
end

function M.load(slot, silent)
  local loaded_count, err = persist.load(state(), slot)
  if not loaded_count then
    if not silent then
      report_error(err)
    end
    return false
  end
  refresh_scope()
  if not silent then
    if loaded_count == 0 then
      warn(("No persistent marks defined in %s"):format(persist.variable_name(slot)))
    else
      echo_message({
        { ("Loaded %d mark%s%s"):format(
          loaded_count,
          loaded_count == 1 and "" or "s",
          state().enabled and "" or "; marks currently disabled"
        ), "Normal" },
      }, false, {})
    end
  end
  return true
end

function M.save(slot)
  local result = save_marks(slot)
  if result == 2 then
    warn("No marks defined")
  end
  return result ~= 0
end

local function load_default_silently()
  local previous_internal_load = M._is_internal_load
  M._is_internal_load = true
  local ok, loaded = pcall(M.load, nil, true)
  M._is_internal_load = previous_internal_load
  if not ok then
    report_error(loaded)
    return false
  end
  return loaded
end

function M.get_definition_commands(one_liner)
  local marks = M.to_list()
  if #marks == 0 then
    return {}
  end
  local commands = {}
  for index, mark in ipairs(marks) do
    local pattern
    local name
    if type(mark) == "table" then
      pattern = mark.pattern or ""
      name = mark.name or ""
    else
      pattern = mark or ""
      name = ""
    end
    if pattern ~= "" then
      commands[#commands + 1] = ("%dMark! /%s/%s"):format(
        index,
        pattern:gsub("/", "\\/"),
        name ~= "" and (" as " .. name) or ""
      )
    end
  end
  if one_liner then
    local lines = {}
    for _, command in ipairs(commands) do
      lines[#lines + 1] = ("exe %q"):format(command)
    end
    return { table.concat(lines, " | ") }
  end
  return commands
end

function M.yank_definitions(one_liner, register)
  local commands = M.get_definition_commands(one_liner)
  if #commands == 0 then
    report_error("No marks defined")
    return false
  end
  local reg = register or '"'
  vim.fn.setreg(reg, table.concat(commands, "\n"))
  return true
end

function M.set_name(clear_all, group_num, name)
  local st = state()
  if clear_all then
    if group_num ~= 0 then
      report_error("Use either [!] to clear all names, or [N] to name a single group, but not both.")
      return false
    end
    for index = 1, st.mark_num do
      st.names[index] = ""
    end
    return true
  end
  if group_num < 1 or group_num > st.mark_num then
    report_error(("Only %d mark highlight groups"):format(st.mark_num))
    return false
  end
  st.names[group_num] = name or ""
  return true
end

local function collect_list_entries()
  local st = state()
  local entries = {}
  local used_count = 0
  for index = 1, st.mark_num do
    local pattern = st.patterns[index]
    local used = pattern ~= ""
    local match_positions = used and collect_match_positions(pattern) or nil
    local match_count = (match_positions and match_positions.positions) and #match_positions.positions or 0
    entries[#entries + 1] = {
      group = index,
      pattern = pattern,
      text = (pattern ~= "" and pattern or "<empty>"),
      used = used,
      count = match_count,
    }
    if used then
      used_count = used_count + 1
    end
  end
  return entries, false, used_count
end

local function show_mark_list_window()
  local entries, _, used_count = collect_list_entries()
  if #entries == 0 then
    vim.notify("No mark groups configured.", vim.log.levels.INFO, { title = "Mark List" })
    return
  end
  if used_count == 0 then
    vim.notify("No marks defined.", vim.log.levels.INFO, { title = "Mark List" })
  end

  close_mark_list_window()
  local source_win = vim.api.nvim_get_current_win()
  local function pad_right(text, width)
    local padding = math.max(0, width - vim.fn.strdisplaywidth(text))
    return text .. string.rep(" ", padding)
  end
  local function pad_left(text, width)
    local padding = math.max(0, width - vim.fn.strdisplaywidth(text))
    return string.rep(" ", padding) .. text
  end

  local pattern_width = vim.fn.strdisplaywidth("Pattern")
  local count_width = vim.fn.strdisplaywidth("Count")
  for _, entry in ipairs(entries) do
    pattern_width = math.max(pattern_width, vim.fn.strdisplaywidth(entry.text))
    count_width = math.max(count_width, vim.fn.strdisplaywidth(tostring(entry.count)))
  end

  local lines = {
    ("Grp  %s  %s"):format(pad_right("Pattern", pattern_width), pad_left("Count", count_width)),
  }
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = ("%3d  %s  %s"):format(
      entry.group,
      pad_right(entry.text, pattern_width),
      pad_left(tostring(entry.count), count_width)
    )
  end

  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "marklist"
  local height = math.min(#lines, math.floor(vim.o.lines * 0.7))
  mark_list_winid = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2 - 1)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = math.max(20, width),
    height = math.max(2, height),
    border = "rounded",
    style = "minimal",
    title = " Marks ",
    title_pos = "center",
  })
  vim.wo[mark_list_winid].wrap = false
  vim.wo[mark_list_winid].cursorline = true
  if #lines > 1 then
    vim.api.nvim_win_set_cursor(mark_list_winid, { 2, 0 })
  end

  vim.api.nvim_buf_add_highlight(buf, mark_list_ns, "Title", 0, 0, -1)

  for line_index, entry in ipairs(entries) do
    if entry.used then
      local start_col = 5
      local end_col = start_col + #entry.text
      vim.api.nvim_buf_add_highlight(buf, mark_list_ns, ("MarkWord%d"):format(entry.group), line_index, start_col, end_col)
    end
  end

  vim.keymap.set("n", "q", close_mark_list_window, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<esc>", close_mark_list_window, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<cr>", function()
    if not (mark_list_winid and vim.api.nvim_win_is_valid(mark_list_winid)) then
      return
    end
    local cursor = vim.api.nvim_win_get_cursor(mark_list_winid)
    local entry = entries[cursor[1] - 1]
    if not entry then
      return
    end
    close_mark_list_window()
    if not entry.used then
      vim.notify(("Group %d has no pattern."):format(entry.group), vim.log.levels.WARN, { title = "Mark List" })
      return
    end
    if vim.api.nvim_win_is_valid(source_win) then
      pcall(vim.api.nvim_set_current_win, source_win)
    end
    M.search_group_mark(entry.group, 1, false, true, true)
  end, { buffer = buf, nowait = true, silent = true })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "InsertEnter" }, {
    buffer = buf,
    once = true,
    callback = function()
      close_mark_list_window()
    end,
  })
end

local function show_mark_list_picker()
  local entries, _, used_count = collect_list_entries()
  if #entries == 0 then
    vim.notify("No mark groups configured.", vim.log.levels.INFO, { title = "Mark List" })
    return
  end
  if used_count == 0 then
    vim.notify("No marks defined.", vim.log.levels.INFO, { title = "Mark List" })
  end

  vim.ui.select(entries, {
    prompt = "Marks",
    kind = "mark.list",
    format_item = function(entry)
      return entry.text
    end,
  }, function(entry)
    if not entry then
      return
    end
    if not entry.used then
      vim.notify(("Group %d has no pattern."):format(entry.group), vim.log.levels.WARN, { title = "Mark List" })
      return
    end
    M.search_group_mark(entry.group, 1, false, true, true)
  end)
end

local function ensure_marks_before_list()
  if config().auto_load then
    return
  end
  if state_mod.used_count(state()) > 0 then
    save_marks()
    return
  end
  load_default_silently()
end

function M.list()
  ensure_marks_before_list()
  if config().ui.float_list then
    show_mark_list_window()
    return
  end
  show_mark_list_picker()
end

function M.get_group_num()
  return state().mark_num
end

function M.get_count()
  return state_mod.used_count(state())
end

function M.get_pattern(index)
  if index ~= nil then
    return state().patterns[index]
  end
  if state().last_search == -1 then
    return ""
  end
  return state().patterns[state().last_search]
end

function M.is_enabled()
  return state().enabled
end

function M.any_mark_pattern()
  return any_mark_pattern()
end

function M.get_mark_number(pattern, is_literal, is_consider_alternatives)
  local search_pattern
  if is_literal then
    search_pattern = "\\<" .. escape_text(pattern) .. "\\>"
  else
    search_pattern = normalize_magic(pattern)
  end
  if search_pattern == "" then
    return 0
  end
  for index = 1, state().mark_num do
    local group_pattern = state().patterns[index]
    if search_pattern == group_pattern then
      return index
    end
    if is_consider_alternatives then
      for _, alternative in ipairs(split_into_alternatives(group_pattern)) do
        if alternative == search_pattern then
          return index
        end
      end
    end
  end
  return 0
end

function M.set_palette(palette_name)
  local cfg = config()
  cfg.palette = palette_name
  local palette, count = config_mod.resolve_palette(cfg)
  local st = state()
  local old_num = st.mark_num
  highlight.define_highlights(palette, count, true)
  if count < old_num then
    highlight.clear_highlights(count + 1, old_num)
  end
  state_mod.resize(st, count)
  refresh_scope()
end

local function palette_complete(_, _, _)
  return config_mod.palette_names(config())
end

local function slot_complete(arg_lead, _, _)
  return persist.slot_completion(arg_lead)
end

local function clear_registered_keymaps()
  local owned_prefix = "mark.nvim:"
  for _, mapping in ipairs(M._applied_keymaps) do
    local current = vim.fn.maparg(mapping.lhs, mapping.mode, false, true)
    local current_desc = type(current) == "table" and current.desc or nil
    if type(current_desc) == "string" and current_desc:sub(1, #owned_prefix) == owned_prefix then
      pcall(vim.keymap.del, mapping.mode, mapping.lhs)
    end
  end
  M._applied_keymaps = {}
end

local function register_keymap(mode, lhs, rhs, opts)
  local map_opts = vim.tbl_extend("force", { desc = ("mark.nvim:%s"):format(lhs) }, opts or {})
  vim.keymap.set(mode, lhs, rhs, map_opts)
  M._applied_keymaps[#M._applied_keymaps + 1] = { mode = mode, lhs = lhs }
end

local function apply_keymaps()
  clear_registered_keymaps()
  local preset = config().keymaps.preset
  if preset == "none" then
    return
  end

  local map_opts = { silent = true, noremap = true }
  if preset == "legacy" then
    register_keymap("n", "<Leader>m", function()
      M.mark_word({ group = vim.v.count })
    end, map_opts)
    register_keymap("n", "<Leader>gm", function()
      M.mark_word({ group = vim.v.count, partial = true })
    end, map_opts)
    register_keymap("x", "<Leader>m", function()
      M.mark_visual_literal({ group = vim.v.count })
    end, map_opts)
    register_keymap("x", "<Leader>M", function()
      M.mark_visual_whitespace_indifferent({ group = vim.v.count })
    end, map_opts)
    register_keymap("n", "<Leader>r", function()
      M.mark_regex({ group = vim.v.count })
    end, map_opts)
    register_keymap("x", "<Leader>r", function()
      M.mark_visual_regex({ group = vim.v.count })
    end, map_opts)
    register_keymap("n", "<Leader>n", function()
      M.clear(vim.v.count)
    end, map_opts)
    register_keymap("n", "<Leader>*", function()
      M.search_current_mark(false, vim.v.count1)
    end, map_opts)
    register_keymap("n", "<Leader>#", function()
      M.search_current_mark(true, vim.v.count1)
    end, map_opts)
    register_keymap("n", "<Leader>/", function()
      M.search_any_mark(false, vim.v.count1)
    end, map_opts)
    register_keymap("n", "<Leader>?", function()
      M.search_any_mark(true, vim.v.count1)
    end, map_opts)
  else
    register_keymap("n", "<leader>m", function()
      M.mark_word({ group = vim.v.count })
    end, map_opts)
    register_keymap("x", "<leader>m", function()
      M.mark_visual_literal({ group = vim.v.count })
    end, map_opts)
    register_keymap("n", "<leader>M", function()
      M.mark_word({ group = vim.v.count, partial = true })
    end, map_opts)
    register_keymap("n", "<leader>mr", function()
      M.mark_regex({ group = vim.v.count })
    end, map_opts)
    register_keymap("x", "<leader>mr", function()
      M.mark_visual_regex({ group = vim.v.count })
    end, map_opts)
    register_keymap("n", "<leader>mn", function()
      M.clear(vim.v.count)
    end, map_opts)
    register_keymap("n", "<leader>mc", M.clear_all, map_opts)
    register_keymap("n", "<leader>mt", M.toggle, map_opts)
    register_keymap("n", "<leader>ml", M.list, map_opts)
    register_keymap("n", "<leader>m/", function()
      M.search_any_mark(false, vim.v.count1)
    end, map_opts)
    register_keymap("n", "<leader>m?", function()
      M.search_any_mark(true, vim.v.count1)
    end, map_opts)
    register_keymap("n", "<leader>m*", function()
      M.search_current_mark(false, vim.v.count1)
    end, map_opts)
    register_keymap("n", "<leader>m#", function()
      M.search_current_mark(true, vim.v.count1)
    end, map_opts)
  end

  register_keymap("n", "*", function()
    if not M.search_next(false, nil, vim.v.count1) then
      return "*"
    end
    return ""
  end, { expr = true, silent = true, noremap = true })
  register_keymap("n", "#", function()
    if not M.search_next(true, nil, vim.v.count1) then
      return "#"
    end
    return ""
  end, { expr = true, silent = true, noremap = true })

  local direct_num = config().direct_group_jump_mapping_num
  for count = 1, direct_num do
    register_keymap("n", ("<k%d>"):format(count), function()
      M.search_group_mark(count, vim.v.count1, false, true, true)
    end, map_opts)
    register_keymap("n", ("<C-k%d>"):format(count), function()
      M.search_group_mark(count, vim.v.count1, true, true, true)
    end, map_opts)
  end
end

local function delete_command_if_exists(name)
  pcall(vim.api.nvim_del_user_command, name)
end

local function set_mark_from_command(group_num, arguments, replace_group)
  local group = group_num or 0
  local args = arguments or ""
  if replace_group and group > 0 then
    do_mark(group, "", nil, { pattern_supplied = false, interactive = false })
  end

  if args == "" then
    return do_mark_and_set_current(group, nil, nil, { pattern_supplied = false, interactive = false })
  end

  local pattern, name = parse_mark_argument(args)
  return do_mark_and_set_current(group, pattern, name, { pattern_supplied = true, interactive = false })
end

local function register_commands()
  local commands = {
    "MarkAdd",
    "MarkRegex",
    "MarkClear",
    "MarkClearAll",
    "MarkToggle",
    "MarkList",
    "MarkSave",
    "MarkLoad",
    "MarkPalette",
    "MarkName",
    "MarkNameClear",
    "MarkYankDefinitions",
    "MarkYankDefinitionsOneLiner",
    "MarkSearchCurrentNext",
    "MarkSearchCurrentPrev",
    "MarkSearchAnyNext",
    "MarkSearchAnyPrev",
    "MarkSearchGroupNext",
    "MarkSearchGroupPrev",
    "MarkSearchNextGroup",
    "MarkSearchPrevGroup",
    "MarkCascadeStart",
    "MarkCascadeNext",
    "MarkCascadePrev",
    "Mark",
    "Marks",
  }
  for _, command in ipairs(commands) do
    delete_command_if_exists(command)
  end

  vim.api.nvim_create_user_command("MarkAdd", function(args)
    local arguments = table.concat(args.fargs, " ")
    if arguments == "" then
      M.mark_word({ group = args.count, partial = false })
      return
    end
    set_mark_from_command(args.count, arguments, args.bang)
  end, {
    bang = true,
    count = 0,
    nargs = "*",
  })

  vim.api.nvim_create_user_command("MarkRegex", function(args)
    local group = args.count
    local pattern = table.concat(args.fargs, " ")
    if pattern == "" then
      M.mark_regex({ group = group })
    else
      do_mark_and_set_current(group, normalize_magic(pattern), nil, {
        pattern_supplied = true,
        interactive = false,
      })
    end
  end, {
    count = 0,
    nargs = "*",
  })

  vim.api.nvim_create_user_command("MarkClear", function(args)
    if #args.fargs > 0 then
      local group = tonumber(args.fargs[1]) or 0
      M.clear(group)
    else
      M.clear(args.count)
    end
  end, {
    count = 0,
    nargs = "?",
  })

  vim.api.nvim_create_user_command("MarkClearAll", function()
    M.clear_all()
  end, {})

  vim.api.nvim_create_user_command("MarkToggle", function()
    M.toggle()
  end, {})

  vim.api.nvim_create_user_command("MarkList", function()
    M.list()
  end, {})

  vim.api.nvim_create_user_command("MarkSave", function(args)
    M.save(args.args ~= "" and args.args or nil)
  end, {
    nargs = "?",
    complete = slot_complete,
  })

  vim.api.nvim_create_user_command("MarkLoad", function(args)
    M.load(args.args ~= "" and args.args or nil, false)
  end, {
    nargs = "?",
    complete = slot_complete,
  })

  vim.api.nvim_create_user_command("MarkPalette", function(args)
    M.set_palette(args.args)
  end, {
    nargs = 1,
    complete = palette_complete,
  })

  vim.api.nvim_create_user_command("MarkName", function(args)
    local clear_all = args.bang
    local group = args.count
    local name = table.concat(args.fargs, " ")
    M.set_name(clear_all, group, name)
  end, {
    bang = true,
    count = 0,
    nargs = "*",
  })

  vim.api.nvim_create_user_command("MarkNameClear", function()
    M.set_name(true, 0, "")
  end, {})

  vim.api.nvim_create_user_command("MarkYankDefinitions", function(args)
    M.yank_definitions(false, args.args ~= "" and args.args or '"')
  end, {
    nargs = "?",
  })

  vim.api.nvim_create_user_command("MarkYankDefinitionsOneLiner", function(args)
    M.yank_definitions(true, args.args ~= "" and args.args or '"')
  end, {
    nargs = "?",
  })

  vim.api.nvim_create_user_command("MarkSearchCurrentNext", function(args)
    M.search_current_mark(false, args.count > 0 and args.count or 1)
  end, { count = 0 })

  vim.api.nvim_create_user_command("MarkSearchCurrentPrev", function(args)
    M.search_current_mark(true, args.count > 0 and args.count or 1)
  end, { count = 0 })

  vim.api.nvim_create_user_command("MarkSearchAnyNext", function(args)
    M.search_any_mark(false, args.count > 0 and args.count or 1)
  end, { count = 0 })

  vim.api.nvim_create_user_command("MarkSearchAnyPrev", function(args)
    M.search_any_mark(true, args.count > 0 and args.count or 1)
  end, { count = 0 })

  vim.api.nvim_create_user_command("MarkSearchGroupNext", function(args)
    local group = args.count
    M.search_group_mark(group, 1, false, true, true)
  end, { count = 0 })

  vim.api.nvim_create_user_command("MarkSearchGroupPrev", function(args)
    local group = args.count
    M.search_group_mark(group, 1, true, true, true)
  end, { count = 0 })

  vim.api.nvim_create_user_command("MarkSearchNextGroup", function(args)
    M.search_next_group(args.count > 0 and args.count or 1, false)
  end, { count = 0 })

  vim.api.nvim_create_user_command("MarkSearchPrevGroup", function(args)
    M.search_next_group(args.count > 0 and args.count or 1, true)
  end, { count = 0 })

  vim.api.nvim_create_user_command("MarkCascadeStart", function(args)
    M.search_cascade_start(args.count, not args.bang)
  end, { count = 0, bang = true })

  vim.api.nvim_create_user_command("MarkCascadeNext", function(args)
    M.search_cascade_next(args.count > 0 and args.count or 1, not args.bang, false)
  end, { count = 0, bang = true })

  vim.api.nvim_create_user_command("MarkCascadePrev", function(args)
    M.search_cascade_next(args.count > 0 and args.count or 1, not args.bang, true)
  end, { count = 0, bang = true })

  if config().legacy_commands then
    vim.api.nvim_create_user_command("Mark", function(args)
      set_mark_from_command(args.count, table.concat(args.fargs, " "), args.bang)
    end, {
      bang = true,
      count = 0,
      nargs = "*",
    })
    vim.api.nvim_create_user_command("Marks", function()
      M.list()
    end, {})
  end
end

local function register_autocmds()
  if M._autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, M._autocmd_group)
  end
  M._autocmd_group = vim.api.nvim_create_augroup("MarkLua", { clear = true })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = M._autocmd_group,
    callback = function(args)
      if M._updating_windows then
        return
      end
      local winid = vim.api.nvim_get_current_win()
      if args.event == "WinEnter" and state().window_matches[winid] then
        return
      end
      refresh_current_window(winid)
    end,
  })

  vim.api.nvim_create_autocmd("TabEnter", {
    group = M._autocmd_group,
    callback = function()
      if M._updating_windows then
        return
      end
      refresh_scope()
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = M._autocmd_group,
    pattern = "/",
    callback = function()
      local search_cmd = M._search_cmd
      search_cmd.active = true
      search_cmd.last_cmdline = ""
      search_cmd.source_winid = vim.api.nvim_get_current_win()
      clear_search_preview()
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineChanged", {
    group = M._autocmd_group,
    pattern = "/",
    callback = function()
      local search_cmd = M._search_cmd
      if not search_cmd.active then
        return
      end
      local cmdline = vim.fn.getcmdline()
      search_cmd.last_cmdline = cmdline
      update_search_preview(cmdline)
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = M._autocmd_group,
    pattern = "/",
    callback = function()
      local search_cmd = M._search_cmd
      local was_active = search_cmd.active
      local final_pattern = vim.fn.getcmdline()
      if final_pattern == "" then
        final_pattern = search_cmd.last_cmdline or ""
      end
      local event = vim.v.event or {}
      local aborted = event.abort == true or event.abort == 1
      reset_search_cmd_state()

      if not was_active or aborted then
        return
      end
      if final_pattern == "" or not is_valid_regex(final_pattern) then
        return
      end
      vim.schedule(function()
        if not M._setup_done then
          return
        end
        do_mark_and_set_current(0, normalize_magic(final_pattern), nil, {
          pattern_supplied = true,
          interactive = false,
        })
        clear_native_search_highlight()
      end)
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = M._autocmd_group,
    callback = function()
      local palette, count = config_mod.resolve_palette(config())
      highlight.define_highlights(palette, count, false)
      define_preview_highlight()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = M._autocmd_group,
    callback = function()
      if config().auto_save then
        save_marks()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = M._autocmd_group,
    callback = function(args)
      M._search_progress_cache[args.buf] = nil
    end,
  })
end

local function set_cascade_context()
  local st = state()
  st._cascade_ctx = {
    current_mark = function()
      return M.current_mark()
    end,
    search_group_mark = function(group_num, count, is_backward, is_set_last_search)
      return M.search_group_mark(group_num, count, is_backward, is_set_last_search, true)
    end,
    next_used_group_index = function(is_backward, is_wrap_around, start_index, count)
      return state_mod.next_used_group_index(st, is_backward, is_wrap_around, start_index, count)
    end,
  }
end

function M.search_cascade_start(count, is_stop_before_cascade)
  local cascade_state = state().cascade
  return cascade.start(cascade_state, state()._cascade_ctx, count or 0, is_stop_before_cascade and true or false)
end

function M.search_cascade_next(count, is_stop_before_cascade, is_backward)
  local cascade_state = state().cascade
  return cascade.next(
    cascade_state,
    state()._cascade_ctx,
    count or 1,
    is_stop_before_cascade and true or false,
    is_backward and true or false
  )
end

local function initialize_state_and_palette(reinitialize)
  local cfg = config()
  local st = state()
  local palette, count = config_mod.resolve_palette(cfg)
  local old_num = st.mark_num
  highlight.define_highlights(palette, count, reinitialize)
  define_preview_highlight()
  if not M._setup_done then
    state_mod.init_arrays(st, count)
  else
    state_mod.resize(st, count)
  end
  if count < old_num then
    highlight.clear_highlights(count + 1, old_num)
  end
end

function M.setup(opts)
  M._config = config_mod.normalize(opts)
  M._search_progress_cache = {}
  reset_search_cmd_state()
  vim.g.loaded_mark = 1
  initialize_state_and_palette(M._setup_done)
  register_commands()
  apply_keymaps()
  register_autocmds()
  set_cascade_context()

  local loaded = false
  if config().auto_load and not M._setup_done and persist.has_data(nil) then
    loaded = load_default_silently()
  end

  if not loaded then
    refresh_scope()
  end

  M._setup_done = true
  return M
end

return M
