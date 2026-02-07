local M = {}

function M.new()
  return {
    mark_num = 0,
    patterns = {},
    names = {},
    cycle = 1,
    last_search = -1,
    enabled = true,
    window_matches = {},
    cascade = {
      location = {},
      position = {},
      group_index = -1,
      is_backward = -1,
      stop_index = -1,
      visited_buffers = {},
    },
  }
end

function M.resize(state, mark_num)
  local old_num = state.mark_num
  if mark_num < old_num then
    for index = mark_num + 1, old_num do
      state.patterns[index] = nil
      state.names[index] = nil
    end
    if state.last_search > mark_num then
      state.last_search = -1
    end
    state.cycle = math.min(state.cycle, math.max(mark_num, 1))
  elseif mark_num > old_num then
    for index = old_num + 1, mark_num do
      state.patterns[index] = ""
      state.names[index] = ""
    end
  end
  state.mark_num = mark_num
end

function M.init_arrays(state, mark_num)
  state.mark_num = 0
  state.patterns = {}
  state.names = {}
  M.resize(state, mark_num)
  state.cycle = 1
  state.last_search = -1
  state.enabled = true
  state.window_matches = {}
end

function M.used_count(state)
  local count = 0
  for index = 1, state.mark_num do
    if state.patterns[index] ~= "" then
      count = count + 1
    end
  end
  return count
end

function M.free_group_index(state)
  for index = 1, state.mark_num do
    if state.patterns[index] == "" then
      return index
    end
  end
  return nil
end

function M.next_used_group_index(state, is_backward, is_wrap_around, start_index, count)
  local max_index = state.mark_num
  if max_index <= 0 then
    return nil
  end

  local remaining = count
  local indices = {}
  if is_backward then
    for index = start_index - 1, 1, -1 do
      indices[#indices + 1] = index
    end
    if is_wrap_around then
      for index = max_index, start_index + 1, -1 do
        indices[#indices + 1] = index
      end
    end
  else
    for index = start_index + 1, max_index do
      indices[#indices + 1] = index
    end
    if is_wrap_around then
      for index = 1, math.max(0, start_index - 1) do
        indices[#indices + 1] = index
      end
    end
  end

  for _, index in ipairs(indices) do
    if index >= 1 and index <= max_index and state.patterns[index] ~= "" then
      remaining = remaining - 1
      if remaining == 0 then
        return index
      end
    end
  end
  return nil
end

return M
