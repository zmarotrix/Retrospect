-- Item tooltips: who holds it and where; who can learn a recipe; which alt needs it for a quest.
-- Quest tooltips: who has done it, who is on it. Everything comes from what the characters had when
-- last seen and from NorgannonDB's relations.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI
local C = UI.C

local Tips = {}
R.Tips = Tips
local Kit, Store, Index = R.Kit, R.Store, R.Index

local MAX_LINES = 6   -- holders listed before "and N more"
local STALE = 14 * 86400

local function accent()
  local a = UI.Accent("retrospect")
  return a[1], a[2], a[3]
end

---What's held of an item, as lines: a heading, then one line per holder.
function Tips.HoldingLines(id)
  local holdings, total = Index:Holdings(id)
  local lines = {}
  if #holdings == 0 then return lines, 0 end
  for i, h in ipairs(holdings) do
    if i > MAX_LINES then
      lines[#lines + 1] = string.format("and %d more", #holdings - MAX_LINES)
      break
    end
    local name = h.holder.c and Kit.Name(h.holder.c) or h.holder.label
    local where = R.Items.PlaceText(h.e):gsub(" %d+$", "")
    -- one place reads "bank"; several read "bank 7, bags 2"
    local places = 0
    for _ in pairs(h.e.places) do places = places + 1 end
    if places > 1 then where = R.Items.PlaceText(h.e) end
    local line = h.holder.c and string.format("%s %d (%s)", name, h.e.total, where) or string.format("%s %d", name, h.e.total)
    local c = h.holder.c
    if c and h.e.places.bank and c.bank and R.Now() - c.bank.seen > STALE then
      line = line .. UI.Code(Kit.UNKNOWN) .. " seen " .. R.Today.Ago(c.bank.seen) .. "|r"
    end
    lines[#lines + 1] = line
  end
  return lines, total
end

---Who can learn the recipe an item teaches.
local function learnerLines(id, lines)
  for _, l in ipairs(R.Items.Learners(id)) do
    if l.state == "can" then
      lines[#lines + 1] = string.format("%s can learn this (%d)", Kit.Name(l.c), l.rank or 0)
    elseif l.state == "known" then
      lines[#lines + 1] = string.format("%s %sknows this|r", Kit.Name(l.c), UI.Code(C.faint))
    elseif l.state == "low" then
      lines[#lines + 1] = string.format("%s %sneeds skill %d, has %d|r", Kit.Name(l.c), UI.Code(C.faint), l.need or 0, l.rank or 0)
    end
  end
end

---Which characters need the item for a quest in their log, and how many more.
local function questLines(id, lines)
  local info = Core.DB:ItemInfo(id)
  if not (info and info.objective and #info.objective > 0) then return end
  local name = string.lower(Store:ItemName(id))
  for _, entry in ipairs(Store:List()) do
    for _, questId in ipairs(info.objective) do
      local log = Store:QuestInLog(entry.key, questId)
      if log and log.complete ~= true then
        -- the objective that names this item, for how many it still takes
        local more
        for _, o in ipairs(log.objectives or {}) do
          if o.type == "item" and o.name and string.lower(o.name) == name and o.required then
            more = math.max(0, o.required - (o.current or 0))
            if more > 0 then
              lines[#lines + 1] = string.format("%s needs %d more for a quest (%d/%d)", Kit.Name(entry.c), more, o.current or 0, o.required)
            end
          end
        end
        if not more then lines[#lines + 1] = string.format("%s needs this for a quest", Kit.Name(entry.c)) end
        break
      end
    end
  end
end

---Adds Retrospect's lines to an item tooltip. Returns how many lines were added.
function Tips:AddItem(tt, id)
  local db = R.db
  if not db then return 0 end
  local lines, total = {}, 0
  if db.tooltips then lines, total = Tips.HoldingLines(id) end
  local needs = {}
  if db.tooltipNeeds then
    learnerLines(id, needs)
    questLines(id, needs)
  end
  if #lines == 0 and #needs == 0 then return 0 end
  local r, g, b = accent()
  if total > 0 then
    local holders = #Index:Holdings(id)
    tt:AddLine(string.format("Retrospect: %d on %d %s", total, holders, holders == 1 and "character" or "characters"), r, g, b)
  else
    tt:AddLine("Retrospect: none held", r, g, b)
  end
  for _, line in ipairs(lines) do tt:AddLine(line, 1, 1, 1) end
  for _, line in ipairs(needs) do tt:AddLine(line, 1, 1, 1) end
  return 1 + #lines + #needs
end

---Adds who has done a quest and who is on it to a quest tooltip.
function Tips:AddQuest(tt, id)
  if not (R.db and R.db.tooltipNeeds) then return 0 end
  local lines = {}
  for _, entry in ipairs(Store:List()) do
    local cell = R.Compare.QuestCell(entry.key, { id })
    if cell and cell.text == "Done" then
      lines[#lines + 1] = Kit.Name(entry.c) .. " done"
    elseif cell and cell.text == "On it" then
      lines[#lines + 1] = Kit.Name(entry.c) .. " on it" .. (cell.small and (" (" .. cell.small .. ")") or "")
    end
  end
  if #lines == 0 then return 0 end
  local r, g, b = accent()
  tt:AddLine("Retrospect", r, g, b)
  for _, line in ipairs(lines) do tt:AddLine(line, 1, 1, 1) end
  return #lines + 1
end

local function public(t) return type(t) == "table" and not Core.IsSecret(t) end

local function onItem(tt, data)
  if not public(data) then return end
  local id = data.id
  if type(id) == "number" and not Core.IsSecret(id) and Tips:AddItem(tt, id) > 0 then tt:Show() end
end

local function onQuest(tt, data)
  if not public(data) then return end
  local id = data.id
  if type(id) == "number" and not Core.IsSecret(id) and Tips:AddQuest(tt, id) > 0 then tt:Show() end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  local T = Enum.TooltipDataType
  if T.Item then TooltipDataProcessor.AddTooltipPostCall(T.Item, onItem) end
  if T.Quest then TooltipDataProcessor.AddTooltipPostCall(T.Quest, onQuest) end
end
Tips.OnItem, Tips.OnQuest = onItem, onQuest
