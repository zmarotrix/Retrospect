-- The Compare tab: one grid, every character a column. Reputation, professions, attunements and
-- keys, lockouts, and any one quest. The grid's rows come from what the characters have and from
-- NorgannonDB (instance keys and attunements), so nothing here is a hand-kept list.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI
local C = UI.C

local Compare = {}
R.Compare = Compare
local Kit, Store, Index = R.Kit, R.Store, R.Index

local LABEL = 240
local COLUMN = 98
local ROW = 36

local MODES = {
  { key = "rep", label = "Reputation" }, { key = "prof", label = "Professions" }, { key = "att", label = "Attunements & keys" },
  { key = "lock", label = "Lockouts" }, { key = "quest", label = "A quest…" },
}
local NOTES = {
  rep = "Every faction a character has met, best standing first. A blank means that character hadn't met it when last seen.",
  prof = "Recipe counts compare what each character has learned with NorgannonDB's list for that profession.",
  att = "Built from NorgannonDB's instance keys and attunement quests. Done means the quest is complete or the key is held.",
  lock = "Time left counts from the reset time the game gave when you last logged in with that character.",
  quest = "Completed quests are stored per character, from the first time each logs in with Retrospect.",
}

local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local STANDING_BG = {
  { .8, .13, .13, .3 }, { .8, .13, .13, .24 }, { .8, .13, .13, .16 }, { 1, .82, 0, .14 },
  { .25, .75, .25, .16 }, { .25, .75, .25, .26 }, { .25, .75, .63, .3 }, { .25, .78, .86, .36 },
}

local firstColumn = 1
local questQuery, questFocus

function Compare:FocusQuest(id)
  questFocus = id
  questQuery = nil
end

local function standingName(reaction)
  return rawget(_G, "FACTION_STANDING_LABEL" .. tostring(reaction)) or STANDING[reaction] or "?"
end
Compare.StandingName = standingName
Compare.STANDING_BG = STANDING_BG

---"8,950 / 21,000", or nil at the top of the scale.
local function repProgress(r)
  if not (r.value and r.low and r.high) or r.high <= r.low then return nil end
  return Kit.Commas(r.value - r.low) .. " / " .. Kit.Commas(r.high - r.low)
end
Compare.RepProgress = repProgress

-------------------------------------------------------------------------------------------
-- Rows: { group = "..." } or { label, sub, kind, id, cells = { [key] = { text, small, color, bg } } }
-------------------------------------------------------------------------------------------

local function repRows()
  -- every faction anyone has met, with the best standing any character has
  local best = {}
  for _, entry in ipairs(Store:List()) do
    for id, r in pairs(entry.c.reputation and entry.c.reputation.list or {}) do
      if not best[id] or r.value and r.value > best[id] then best[id] = r.value or 0 end
    end
  end
  local groups, order = {}, {}
  for id in pairs(best) do
    local info = R.db.factions[id] or {}
    local group = info.group or "Other"
    if not groups[group] then
      groups[group] = {}
      order[#order + 1] = group
    end
    table.insert(groups[group], id)
  end
  table.sort(order)
  local rows = {}
  for _, group in ipairs(order) do
    rows[#rows + 1] = { group = group }
    table.sort(groups[group], function(a, b)
      if best[a] ~= best[b] then return best[a] > best[b] end
      return tostring((R.db.factions[a] or {}).name) < tostring((R.db.factions[b] or {}).name)
    end)
    for _, id in ipairs(groups[group]) do
      local row = { label = (R.db.factions[id] or {}).name or ("Faction " .. id), kind = "faction", id = id, cells = {} }
      for _, entry in ipairs(Store:List()) do
        local r = entry.c.reputation and entry.c.reputation.list and entry.c.reputation.list[id]
        if r then
          row.cells[entry.key] = { text = standingName(r.reaction), small = repProgress(r), bg = STANDING_BG[r.reaction] }
        end
      end
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function profRows()
  local seen, order = {}, {}
  for _, entry in ipairs(Store:List()) do
    for skill, p in pairs(entry.c.professions and entry.c.professions.skills or {}) do
      if not seen[skill] then
        seen[skill] = p.name or NorgannonDB:L("professions", skill, "name") or ("Skill " .. skill)
        order[#order + 1] = skill
      end
    end
  end
  table.sort(order, function(a, b) return seen[a] < seen[b] end)
  local rows = {}
  for _, skill in ipairs(order) do
    local all = #Core.DB:Recipes(skill)
    local row = { label = seen[skill], kind = "skill", id = skill, cells = {} }
    for _, entry in ipairs(Store:List()) do
      local p = entry.c.professions and entry.c.professions.skills and entry.c.professions.skills[skill]
      if p then
        local set = Store:Recipes(entry.key, skill)
        local small
        if set then
          local n = 0
          for _ in pairs(set) do n = n + 1 end
          small = all > 0 and string.format("%d of %d recipes", n, all) or (n .. " recipes")
        elseif all > 0 then
          small = UI.Code(Kit.UNKNOWN) .. "not opened|r"
        end
        row.cells[entry.key] = { text = tostring(p.rank or "?"), small = small }
      end
    end
    rows[#rows + 1] = row
  end
  return rows
end

---Where a character keeps an item, for a cell: "Has key" in the bags, else the place's name.
local function heldCell(key, ids)
  for _, id in ipairs(ids) do
    local e = Index:Of(key, id)
    if e then
      if e.places.bags or e.places.gear then return { text = "Has key", color = Kit.UP } end
      local place
      for p in pairs(e.places) do place = place or p end
      return { text = Index.PLACE_LABEL[place] or "Held", color = Kit.PART }
    end
  end
end

local function attunementQuests(text)
  if type(text) ~= "string" then return {}, {} end
  -- the record's text starts with the quest's or item's name: "Attunement to the Core (the quest at ...)"
  local name = strtrim(text:match("^(.-)%s*%(") or text)
  return Core.DB:IdsByName("quests", name) or {}, Core.DB:IdsByName("items", name) or {}, name
end

local function attRows()
  local raids, dungeons = {}, {}
  for _, key in ipairs(Core.DB:InstanceKeys()) do
    local inst = Core.DB:Instance(key)
    if #(inst.keys or {}) > 0 or inst.attunement then
      local quests, items, name = attunementQuests(inst.attunement)
      local keys = {}
      for _, id in ipairs(inst.keys or {}) do keys[#keys + 1] = id end
      for _, id in ipairs(items) do keys[#keys + 1] = id end
      local sub = name
      if not sub and keys[1] then sub = Store:ItemName(keys[1]) end
      local row = { label = Core.DB:InstanceName(key) or key, sub = sub, kind = "instance", id = key, cells = {} }
      for _, entry in ipairs(Store:List()) do
        local cell
        for _, q in ipairs(quests) do
          if Store:QuestDone(entry.key, q) then cell = { text = "Done", color = Kit.UP } break end
        end
        cell = cell or heldCell(entry.key, keys)
        if not cell then
          for _, q in ipairs(quests) do
            if Store:QuestInLog(entry.key, q) then cell = { text = "Quest active", color = Kit.PART } break end
          end
        end
        row.cells[entry.key] = cell
      end
      table.insert((inst.size or 5) > 5 and raids or dungeons, row)
    end
  end
  local rows = {}
  if #raids > 0 then
    rows[1] = { group = "Raids" }
    for _, row in ipairs(raids) do rows[#rows + 1] = row end
  end
  if #dungeons > 0 then
    rows[#rows + 1] = { group = "Dungeons" }
    for _, row in ipairs(dungeons) do rows[#rows + 1] = row end
  end
  return rows
end

local function lockRows()
  local byName, order, now = {}, {}, R.Now()
  for _, entry in ipairs(Store:List()) do
    for _, l in ipairs(entry.c.lockouts and entry.c.lockouts.list or {}) do
      if l.reset > now then
        if not byName[l.name] then
          byName[l.name] = { label = l.name, cells = {} }
          order[#order + 1] = l.name
        end
        local killed = l.total and l.total > 0 and string.format("%d / %d", l.killed or 0, l.total) or "Saved"
        byName[l.name].cells[entry.key] = { text = killed, small = R.Today.Span(l.reset - now), color = Kit.PART }
      end
    end
  end
  table.sort(order)
  local rows = {}
  for _, name in ipairs(order) do
    local row = byName[name]
    for _, entry in ipairs(Store:List()) do
      row.cells[entry.key] = row.cells[entry.key] or { text = "free", color = C.faint }
    end
    rows[#rows + 1] = row
  end
  return rows
end

---A cell for one quest on one character.
local function questCell(key, ids)
  for _, id in ipairs(ids) do
    if Store:QuestDone(key, id) then return { text = "Done", color = Kit.UP } end
  end
  for _, id in ipairs(ids) do
    local log = Store:QuestInLog(key, id)
    if log then
      local small = log.need and log.need > 0 and string.format("%d/%d", log.done or 0, log.need) or nil
      return { text = "On it", small = small, color = Kit.PART }
    end
  end
  if Store:QuestDone(key, ids[1]) == nil then return { text = "not read", color = Kit.UNKNOWN } end
  return nil
end
Compare.QuestCell = questCell

local function questRows()
  local groups = {}
  if questFocus then
    local name = Core.DB:Name("quests", questFocus) or ("Quest " .. questFocus)
    groups[1] = { name = name, ids = { questFocus } }
  elseif questQuery and strtrim(questQuery) ~= "" then
    for _, found in ipairs(Core.DB:Search(questQuery, { kinds = { quests = true }, limit = 25 })) do
      groups[#groups + 1] = { name = found.name, ids = found.ids }
    end
  end
  local rows = {}
  for _, g in ipairs(groups) do
    local row = { label = g.name, kind = "quest", id = g.ids[1], cells = {} }
    for _, entry in ipairs(Store:List()) do row.cells[entry.key] = questCell(entry.key, g.ids) end
    rows[#rows + 1] = row
  end
  return rows
end

local BUILDERS = { rep = repRows, prof = profRows, att = attRows, lock = lockRows, quest = questRows }
Compare.BUILDERS = BUILDERS

-------------------------------------------------------------------------------------------
-- The grid
-------------------------------------------------------------------------------------------

local function visibleColumns(frame)
  local w = (frame:GetWidth() or 0) - LABEL - 8
  return math.max(1, math.floor(w / (COLUMN + 2)))
end

local function createRow(row, content)
  row.label = UI.Text(content, "body", 13)
  row.label:SetPoint("LEFT", 6, 0)
  row.label:SetWidth(LABEL - 12)
  row.label:SetWordWrap(true)
  row.cellFrames = {}
end

local function cellOf(row, content, i)
  local cell = row.cellFrames[i]
  if cell then return cell end
  cell = CreateFrame("Frame", nil, content)
  cell:SetPoint("TOPLEFT", LABEL + (i - 1) * (COLUMN + 2), -2)
  cell:SetSize(COLUMN, ROW - 4)
  cell.bg = UI.Tex(cell, "BACKGROUND", 0, { 1, 1, 1, .03 })
  cell.bg:SetAllPoints()
  cell.text = UI.Text(cell, "body", 13)
  cell.text:SetPoint("CENTER", 0, 0)
  cell.text:SetJustifyH("CENTER")
  cell.text:SetWordWrap(false)
  cell.small = UI.Text(cell, "body", 11, C.muted)
  cell.small:SetPoint("BOTTOM", 0, 2)
  cell.small:SetJustifyH("CENTER")
  cell.small:SetWordWrap(false)
  row.cellFrames[i] = cell
  return cell
end

local function headersFor(frame)
  local list = Store:List()
  local n = visibleColumns(frame)
  firstColumn = math.max(1, math.min(firstColumn, math.max(1, #list - n + 1)))
  local shown = {}
  for i = firstColumn, math.min(#list, firstColumn + n - 1) do shown[#shown + 1] = list[i] end
  return shown, #list > n
end

local function fill(frame)
  local mode = R.db.cmp
  if not BUILDERS[mode] then mode = "rep" end
  R.db.cmp = mode
  frame.modes:Select(mode, true)
  frame.note:SetText(NOTES[mode] or "")
  frame.questSearch:SetShown(mode == "quest")
  frame.list:ClearAllPoints()
  frame.head:ClearAllPoints()
  frame.head:SetPoint("TOPLEFT", 0, mode == "quest" and -64 or -30)
  frame.head:SetPoint("TOPRIGHT", 0, mode == "quest" and -64 or -30)
  frame.list:SetPoint("TOPLEFT", frame.head, "BOTTOMLEFT", 0, -2)
  frame.list:SetPoint("BOTTOMRIGHT", 0, 24)

  local shown, more = headersFor(frame)
  frame.columns = shown
  frame.prev:SetShown(more)
  frame.nextc:SetShown(more)
  for i = 1, math.max(#shown, #frame.headButtons) do
    local b = frame.headButtons[i]
    local entry = shown[i]
    if entry then
      if not b then
        b = CreateFrame("Button", nil, frame.head)
        b:SetPoint("TOPLEFT", LABEL + (i - 1) * (COLUMN + 2), 0)
        b:SetSize(COLUMN, 22)
        b.text = UI.Text(b, "title", 13)
        b.text:SetPoint("CENTER")
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(self) R.Window:Select(self.key) end)
        frame.headButtons[i] = b
      end
      b.key = entry.key
      b.text:SetText(Kit.Name(entry.c))
      b:Show()
    elseif b then
      b:Hide()
    end
  end

  local rows = BUILDERS[mode]()
  frame.list:SetData(rows, true)
  frame.emptyText:SetShown(#rows == 0)
  if #rows == 0 then
    local empty = {
      rep = "No reputations read yet.", prof = "No professions read yet.", att = "NorgannonDB lists no keys or attunements.",
      lock = "No character was saved to anything when last seen.", quest = "Type a quest's name above: who has done it, who is on it.",
    }
    frame.emptyText:SetText(empty[mode])
  end
end

local function updateRow(row, item)
  local frame = Compare.frame
  local shown = frame.columns or {}
  row.label:SetText(item.sub and (item.label .. "\n" .. UI.Code(C.faint) .. item.sub .. "|r") or item.label)
  for i = 1, math.max(#shown, #row.cellFrames) do
    local entry = shown[i]
    if entry then
      local cell = cellOf(row, row.content, i)
      local v = item.cells[entry.key]
      local tc = v and v.color or C.text
      cell.text:SetText(v and v.text or "—")
      if v then
        cell.text:SetTextColor(tc[1], tc[2], tc[3])
      else
        cell.text:SetTextColor(C.faint[1], C.faint[2], C.faint[3])
      end
      cell.small:SetText(v and v.small or "")
      cell.text:ClearAllPoints()
      cell.text:SetPoint("CENTER", 0, (v and v.small) and 5 or 0)
      local bg = v and v.bg or { 1, 1, 1, .03 }
      cell.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
      cell:Show()
    elseif row.cellFrames[i] then
      row.cellFrames[i]:Hide()
    end
  end
end

local function build(frame)
  Compare.frame = frame
  frame.modes = Kit.Modes(frame, MODES, function(key)
    R.db.cmp = key
    R.Window:Refresh()
  end)
  frame.modes:SetPoint("TOPLEFT")
  frame.modes:SetPoint("TOPRIGHT", -60, 0)

  frame.prev = UI.Button(frame, "<", "quiet", function()
    firstColumn = firstColumn - 1
    R.Window:Refresh()
  end)
  frame.nextc = UI.Button(frame, ">", "quiet", function()
    firstColumn = firstColumn + 1
    R.Window:Refresh()
  end)
  frame.nextc:SetSize(26, 20)
  frame.prev:SetSize(26, 20)
  frame.nextc:SetPoint("TOPRIGHT", 0, 0)
  frame.prev:SetPoint("RIGHT", frame.nextc, "LEFT", -4, 0)

  frame.questSearch = UI.Search(frame, "Any quest's name: who has done it, who is on it", function(text)
    questQuery, questFocus = text, nil
    if R.db.cmp == "quest" then R.Window:RefreshSoon() end
  end)
  frame.questSearch:SetPoint("TOPLEFT", 0, -28)
  frame.questSearch:SetWidth(380)

  frame.head = CreateFrame("Frame", nil, frame)
  frame.head:SetHeight(24)
  frame.headButtons = {}
  local rule = UI.Rule(frame.head)
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")

  frame.list = UI.List(frame, {
    rowHeight = ROW, groupBand = true, createRow = createRow, updateRow = updateRow,
    onClick = function(item, _, button)
      if button == "RightButton" and item.kind then
        Core:ShowActionMenu(frame, item.kind, item.id, { title = item.label })
      end
    end,
  })
  frame.emptyText = Kit.Note(frame, C.muted)
  frame.emptyText:SetPoint("TOP", frame.head, "BOTTOM", 0, -30)
  frame.note = Kit.Note(frame, C.muted)
  frame.note:SetPoint("BOTTOMLEFT", 0, 2)
  frame.note:SetPoint("BOTTOMRIGHT", 0, 2)
end

R.Window:RegisterPane("compare", build, fill)
