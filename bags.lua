-- Bags & Bank. Each place (bags, character bank, account bank) has a heading with how full it is.
-- By type sorts what's there into kinds, one labelled row each, with stacks added up and chips to
-- show one kind. By bag lays it out as the game does, empty slots included, with each bag's name.
-- A place never opened says so and what to do; that isn't the same as empty.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI
local C = UI.C

local Bags = {}
R.Bags = Bags
local Kit, Store, Index = R.Kit, R.Store, R.Index
local Head = R.CharacterHead

local TILE, GAP = 34, 2
local LABEL = 118           -- the column of row labels
local FALLBACK_WIDTH = 1000 -- until the real width is known
local CAPACITY_BAR = 120
local FULL = .9             -- share of a place's slots at which its bar turns to a warning

local KINDS = {
  { key = "gear", label = "Gear" }, { key = "consumable", label = "Consumables" }, { key = "trade", label = "Trade goods" },
  { key = "recipe", label = "Recipes" }, { key = "quest", label = "Quest items" }, { key = "key", label = "Keys" },
  { key = "junk", label = "Junk" }, { key = "other", label = "Other" },
}
-- Enum.ItemClass: what each class of item goes under
local BY_CLASS = { [0] = "consumable", [2] = "gear", [4] = "gear", [5] = "trade", [7] = "trade", [9] = "recipe", [12] = "quest", [13] = "key" }
local VIEWS = { { key = "type", label = "By type" }, { key = "bag", label = "By bag" } }

---Which kind an item is: from the client, else NorgannonDB; poor quality is junk unless a quest wants it.
function Bags.Kind(id, quality)
  local _, _, _, _, _, class = R.In("C_Item", "GetItemInfoInstant", id)
  if class == nil and NorgannonDB.Peek then
    local record = NorgannonDB:Peek("items", id)
    class = record and record.class
  end
  local kind = BY_CLASS[class] or "other"
  if (quality or Index:Quality(id)) == 0 and kind ~= "quest" then return "junk" end
  return kind
end

---A place's stacks, added up per item (copies with an enchant stay apart), grouped by kind and
---sorted best quality first, then by name: { [kind] = { items } }.
local function byKind(section)
  local merged, kinds = {}, {}
  for _, box in ipairs(section.containers or {}) do
    for _, item in ipairs(Store.Items(box.items)) do
      local key = item.link or item.id
      local into = merged[key]
      if into then
        into.count = into.count + item.count
      else
        merged[key] = item
        local kind = Bags.Kind(item.id, item.q)
        kinds[kind] = kinds[kind] or {}
        table.insert(kinds[kind], item)
      end
    end
  end
  for _, list in pairs(kinds) do
    for _, item in ipairs(list) do item.name = Store:ItemName(item.id) end
    table.sort(list, function(a, b)
      local aq, bq = a.q or 1, b.q or 1
      if aq ~= bq then return aq > bq end
      return a.name < b.name
    end)
  end
  return kinds
end
Bags.ByKind = byKind

-------------------------------------------------------------------------------------------
-- Drawing: everything is pooled, since a character's whole inventory is on screen at once
-------------------------------------------------------------------------------------------

local function nextTile(frame, x, y, item)
  frame.nt = frame.nt + 1
  local tile = frame.tiles[frame.nt]
  if not tile then
    tile = Kit.ItemTile(frame.area.content, TILE)
    frame.tiles[frame.nt] = tile
  end
  tile:ClearAllPoints()
  tile:SetPoint("TOPLEFT", x, y)
  tile:SetItem(item)
  tile:Show()
end

local function nextLabel(frame, x, y, text)
  frame.nl = frame.nl + 1
  local label = frame.labels[frame.nl]
  if not label then
    label = UI.Text(frame.area.content, "body", 13, C.text)
    label:SetJustifyH("LEFT")
    label:SetWidth(LABEL - 10)
    frame.labels[frame.nl] = label
  end
  label:ClearAllPoints()
  label:SetPoint("TOPLEFT", x, y)
  label:SetText(text)
  label:Show()
end

---A row of tiles under a label on the left. Returns the y below it.
local function tileRow(frame, y, label, items, empties)
  nextLabel(frame, 0, y - 2, label)
  local col = 0
  local function place(item)
    nextTile(frame, LABEL + col * (TILE + GAP), y, item)
    col = col + 1
    if col >= frame.perRow then
      col = 0
      y = y - (TILE + GAP)
    end
  end
  for _, item in ipairs(items) do place(item) end
  for _ = 1, empties or 0 do place(nil) end
  if col > 0 or (#items == 0 and (empties or 0) == 0) then y = y - (TILE + GAP) end
  return y - 6
end

---A place's heading: its name, when it was seen, how full it is.
local function sectionHead(frame, y, title, section, seen, note)
  frame.nh = frame.nh + 1
  local h = frame.heads[frame.nh]
  if not h then
    local content = frame.area.content
    h = { title = UI.Text(content, "title", 16, C.gold), used = UI.Text(content, "body", 13, C.text), bar = UI.Bar(content, nil, 7), rule = UI.Rule(content) }
    h.bar:SetWidth(CAPACITY_BAR)
    h.used:SetJustifyH("RIGHT")
    frame.heads[frame.nh] = h
  end
  h.title:ClearAllPoints()
  h.title:SetPoint("TOPLEFT", 0, y)
  h.title:SetText(title .. "   " .. Kit.Seen(seen) .. (note and (UI.Code(C.muted) .. "   " .. note .. "|r") or ""))
  h.title:Show()
  h.rule:ClearAllPoints()
  h.rule:SetPoint("TOPLEFT", 0, y - 24)
  h.rule:SetPoint("TOPRIGHT", 0, y - 24)
  h.rule:Show()
  local slots = section and section.slots or 0
  if slots > 0 then
    local used = slots - (section.free or 0)
    local ratio = used / slots
    h.bar:ClearAllPoints()
    h.bar:SetPoint("TOPRIGHT", 0, y - 7)
    h.bar:ApplyAccent(ratio >= FULL and Kit.DOWN or UI.Accent("retrospect"))
    h.bar:SetProgress(ratio, 1)
    h.bar:Show()
    h.used:ClearAllPoints()
    h.used:SetPoint("TOPRIGHT", -(CAPACITY_BAR + 10), y - 2)
    h.used:SetText(string.format("%d of %d slots used", used, slots))
    h.used:Show()
  else
    h.bar:Hide()
    h.used:Hide()
  end
  return y - 32
end

local function drawByType(frame, y, section)
  local kinds = byKind(section)
  local filter = R.db.bagFilter
  local any = false
  for _, kind in ipairs(KINDS) do
    local items = kinds[kind.key]
    if items and (filter == "all" or filter == kind.key) then
      any = true
      y = tileRow(frame, y, kind.label .. UI.Code(C.muted) .. "  " .. #items .. "|r", items)
    end
  end
  if not any then
    nextLabel(frame, 0, y, UI.Code(C.muted) .. "Nothing of that kind here.|r")
    y = y - 24
  end
  return y
end

local function drawByBag(frame, y, section)
  for _, box in ipairs(section.containers or {}) do
    local items = Store.Items(box.items)
    if not box.keyring or #items > 0 then
      local counted = string.format("%d of %d", #items, box.size)
      y = tileRow(frame, y, tostring(box.name or "Bag") .. "\n" .. UI.Code(C.muted) .. counted .. "|r", items, box.keyring and 0 or box.free)
    end
  end
  return y
end

local function drawSection(frame, y, title, section, unknown, note)
  y = sectionHead(frame, y, title, section, section and section.seen, note)
  if not section then
    frame.nn = frame.nn + 1
    local n = frame.notes[frame.nn]
    if not n then
      n = Kit.Note(frame.area.content, Kit.UNKNOWN)
      frame.notes[frame.nn] = n
    end
    n:ClearAllPoints()
    n:SetPoint("TOPLEFT", 0, y)
    n:SetPoint("TOPRIGHT", 0, y)
    n:SetText(unknown)
    n:Show()
    return y - 34
  end
  if R.db.bagView == "bag" then y = drawByBag(frame, y, section) else y = drawByType(frame, y, section) end
  return y - 8
end

-------------------------------------------------------------------------------------------
-- The chips: only the kinds this character has, with how many
-------------------------------------------------------------------------------------------

local function fillChips(frame, c)
  local counts, total = {}, 0
  for _, section in ipairs({ c.bags or false, c.bank or false, R.db.accountBank or false }) do
    if section then
      for kind, items in pairs(byKind(section)) do
        counts[kind] = (counts[kind] or 0) + #items
        total = total + #items
      end
    end
  end
  if R.db.bagFilter ~= "all" and not counts[R.db.bagFilter] then R.db.bagFilter = "all" end
  local previous
  local function lay(chip, text, key)
    chip.label:SetText(text)
    chip:SetWidth(math.floor(chip.label:GetStringWidth() + 20))
    chip:SetOn(R.db.bagFilter == key, true)
    chip:ClearAllPoints()
    if previous then
      chip:SetPoint("LEFT", previous, "RIGHT", 5, 0)
    else
      chip:SetPoint("LEFT", 0, 0)
    end
    chip:Show()
    previous = chip
  end
  lay(frame.chips.all, "All " .. total, "all")
  for _, kind in ipairs(KINDS) do
    local chip = frame.chips[kind.key]
    if counts[kind.key] then lay(chip, kind.label .. " " .. counts[kind.key], kind.key) else chip:Hide() end
  end
end

-------------------------------------------------------------------------------------------
-- The pane
-------------------------------------------------------------------------------------------

R.Window:RegisterPane("bags", function(frame)
  Head.Build(frame)
  frame.view = UI.Segmented(frame, VIEWS, function(key)
    R.db.bagView = key
    R.Window:Refresh()
  end, 20)
  frame.view:SetPoint("TOPRIGHT", 0, -2)

  frame.chipRow = CreateFrame("Frame", nil, frame)
  frame.chipRow:SetPoint("TOPLEFT", 0, -Head.HEIGHT)
  frame.chipRow:SetPoint("TOPRIGHT", 0, -Head.HEIGHT)
  frame.chipRow:SetHeight(22)
  frame.chips = {}
  local function chip(key)
    local c = UI.Chip(frame.chipRow, key)
    c:SetScript("OnClick", function()
      R.db.bagFilter = key
      R.Window:Refresh()
    end)
    frame.chips[key] = c
  end
  chip("all")
  for _, kind in ipairs(KINDS) do chip(kind.key) end

  frame.area = UI.ScrollArea(frame)
  frame.tiles, frame.heads, frame.notes, frame.labels = {}, {}, {}, {}
end, function(frame, key)
  local c = Head.Fill(frame, key)
  local byType = R.db.bagView ~= "bag"
  frame.view:Select(R.db.bagView, true)
  frame.chipRow:SetShown(byType)
  if byType then fillChips(frame, c) end
  frame.area:ClearAllPoints()
  frame.area:SetPoint("TOPLEFT", 0, -(Head.HEIGHT + (byType and 30 or 0)))
  frame.area:SetPoint("BOTTOMRIGHT")

  local width = frame.area:GetWidth() or 0
  frame.area.content:SetWidth(width > 0 and width or FALLBACK_WIDTH)
  if width <= 0 then width = FALLBACK_WIDTH end
  frame.perRow = math.max(1, math.floor((width - LABEL + GAP) / (TILE + GAP)))
  frame.nt, frame.nh, frame.nn, frame.nl = 0, 0, 0, 0

  local y = 0
  y = drawSection(frame, y, "Bags", c.bags, "Not read yet. Bags are read as soon as this character logs in with Retrospect on.")
  y = drawSection(frame, y, "Character bank", c.bank,
    "Never opened with Retrospect running, so this isn't empty, just unknown. Visit a banker on this character.")
  if R.db.accountBank then
    y = drawSection(frame, y, "Account bank", R.db.accountBank, nil, "shared by the whole account")
  end

  for i = frame.nt + 1, #frame.tiles do frame.tiles[i]:Hide() end
  for i = frame.nl + 1, #frame.labels do frame.labels[i]:Hide() end
  for i = frame.nn + 1, #frame.notes do frame.notes[i]:Hide() end
  for i = frame.nh + 1, #frame.heads do
    local h = frame.heads[i]
    h.title:Hide()
    h.used:Hide()
    h.bar:Hide()
    h.rule:Hide()
  end
  frame.area.content:SetHeight(math.max(1, -y))
end)
