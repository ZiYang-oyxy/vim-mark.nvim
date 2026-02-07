local M = {}

local function is_upper_slot(slot)
  return slot:match("^%u+$") ~= nil
end

function M.default_slot()
  return "marks"
end

function M.variable_name(slot)
  local value = slot
  if value == nil or value == "" then
    value = M.default_slot()
  end
  return ("MARK_%s"):format(value)
end

function M.slot_completion(arg_lead)
  local slots = {}
  local lead = arg_lead or ""
  local escaped_lead = lead:gsub("([^%w])", "%%%1")
  for key, _ in pairs(vim.g) do
    if type(key) == "string" and key:match("^MARK_") and key ~= "MARK_ENABLED" and key ~= "MARK_MARKS" then
      local slot = key:sub(6)
      if lead == "" or slot:find("^" .. escaped_lead) then
        slots[#slots + 1] = slot
      end
    end
  end
  table.sort(slots)
  return slots
end

function M.serialize(state)
  local highest = 0
  for index = state.mark_num, 1, -1 do
    if state.patterns[index] ~= "" or state.names[index] ~= "" then
      highest = index
      break
    end
  end
  if highest == 0 then
    return {}
  end
  local marks = {}
  for index = 1, highest do
    if state.names[index] ~= "" then
      marks[index] = { pattern = state.patterns[index], name = state.names[index] }
    else
      marks[index] = state.patterns[index]
    end
  end
  return marks
end

local function deserialize_mark(mark)
  if type(mark) == "table" then
    return mark.pattern or "", mark.name or ""
  end
  return mark or "", ""
end

function M.apply_loaded(state, marks)
  for index = 1, state.mark_num do
    local mark = marks[index] or ""
    state.patterns[index], state.names[index] = deserialize_mark(mark)
  end
end

function M.save(state, slot)
  local variable = M.variable_name(slot)
  local marks = M.serialize(state)
  vim.g[variable] = marks
  if slot == nil or slot == "" then
    vim.g.MARK_ENABLED = state.enabled and 1 or 0
  end
  if #marks == 0 then
    return 2
  end
  return 1
end

function M.load(state, slot)
  local variable = M.variable_name(slot)
  local marks = vim.g[variable]
  if type(marks) ~= "table" then
    return nil, ("No marks stored under %s%s"):format(
      variable,
      is_upper_slot(slot or "") and "" or ", and persistence not configured"
    )
  end
  M.apply_loaded(state, marks)
  local enabled = vim.g.MARK_ENABLED
  if enabled == nil then
    state.enabled = true
  else
    state.enabled = enabled == 1 or enabled == true
  end
  local count = 0
  for index = 1, state.mark_num do
    if state.patterns[index] ~= "" then
      count = count + 1
    end
  end
  return count
end

return M
