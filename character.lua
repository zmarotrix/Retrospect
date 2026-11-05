-- One character's tabs: Overview, Bags & Bank, Gear, Mail & Auctions, Quests, Professions and
-- Reputation. Each says when it was last read, and "never opened" is different from "empty".

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI
local C = UI.C

local Kit, Store, Today = R.Kit, R.Store, R.Today
local Window = R.Window

local HEAD = 34
local TILE, TILE_GAP = 34, 2
local BAGS_PER_ROW = 29

---The heading all these panes share: the name, then who they are.
local function buildHead(frame)
  frame.name = UI.Text(frame, "title", 22)
  frame.name:SetPoint("TOPLEFT", 0, -2)
  frame.facts = UI.Text(frame, "body", 13, C.muted)
  frame.facts:SetPoint("BOTTOMLEFT", frame.name, "BOTTOMRIGHT", 10, 2)
end

local function classWord(c)
  local token = tostring(c.class or "")
  return token:sub(1, 1) .. string.lower(token:sub(2))
end

local function fillHead(frame, key)
  local c = Store:Get(key)
  frame.name:SetText(Kit.Name(c))
  local who = string.format("Level %s %s %s%s", tostring(c.level or "?"), tostring(c.race or ""), c.spec and (c.spec .. " ") or "", classWord(c))
  frame.facts:SetText(who .. " · " .. tostring(c.realm) .. (c.guild and (" · <" .. c.guild .. ">") or ""))
  return c
end

local function rowsTable(frame, cols, opts)
  local t = Kit.Table(frame, cols, opts)
  t:SetPoint("TOPLEFT", 0, -HEAD)
  t:SetPoint("BOTTOMRIGHT")
  return t
end

-------------------------------------------------------------------------------------------
-- Overview
-------------------------------------------------------------------------------------------

Window:RegisterPane("over", function(frame)
  buildHead(frame)
  local facts = UI.Card(frame, "Facts")
  facts:SetPoint("TOPLEFT", 0, -HEAD)
  facts:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 0)
  frame.factRows = Kit.Table(facts.body, { { width = 100 }, {} }, { rowHeight = 26 })
  frame.factRows:SetAllPoints()
  local list = UI.Card(frame, "On the list")
  list:SetPoint("TOPLEFT", facts, "TOPRIGHT", 12, 0)
  list:SetPoint("BOTTOMRIGHT")
  frame.eventRows = Kit.Table(list.body, { {}, { width = 110, right = true } }, { rowHeight = 26 })
  frame.eventRows:SetAllPoints()
end, function(frame, key)
  local c = fillHead(frame, key)
  local rows = {}
  local function add(label, value) rows[#rows + 1] = { cells = { UI.Code(C.muted) .. label .. "|r", value } } end
  local mine = key == Store:MyKey()
  add("Last seen", (mine and "Now" or Today.Ago(c.seen)) .. (c.zone and (", " .. c.zone) or ""))
  add("Gold", Kit.Money(c.money or 0))
  add("Played", Kit.Played(c.played) or UI.Code(C.faint) .. "Not read yet|r")
  local rest, estimate = Store:Rest(key)
  if rest then
    add("Rested", string.format("%d%% of a level%s", math.floor(rest * 100 + .5), estimate and UI.Code(C.faint) .. " (estimate)|r" or ""))
  end
  add("Bag space", c.bags and string.format("%d of %d free", c.bags.free, c.bags.slots) or Kit.Seen(nil))
  add("Item level", c.ilvl and tostring(math.floor(c.ilvl)) or UI.Code(C.faint) .. "—|r")
  local profs = {}
  for _, p in pairs(c.professions and c.professions.skills or {}) do profs[#profs + 1] = tostring(p.name) .. " " .. tostring(p.rank) end
  table.sort(profs)
  add("Professions", #profs > 0 and table.concat(profs, " · ") or "None")
  add("Hearthstone", c.bind or UI.Code(C.faint) .. "—|r")
  frame.factRows:SetRows(rows, true)

  local events = {}
  for _, e in ipairs(Today:For(key)) do
    events[#events + 1] = { cells = { e.title, UI.Code(C.muted) .. (e.when or "") .. "|r" }, tip = e.sub and function(tt)
      tt:AddLine(e.title, 1, 1, 1)
      tt:AddLine(e.sub, C.muted[1], C.muted[2], C.muted[3], true)
    end or nil }
  end
  if #events == 0 then events[1] = { note = "Nothing waiting." } end
  frame.eventRows:SetRows(events, true)
end)

-------------------------------------------------------------------------------------------
-- Bags & Bank: every slot as a tile, section by section
-------------------------------------------------------------------------------------------

local function layoutSection(frame, y, title, seen, section, unknownText, shareNote)
  local content = frame.area.content
  local h = frame.headers[frame.nh + 1]
  if not h then
    h = UI.Text(content, "title", 15, C.gold)
    frame.headers[frame.nh + 1] = h
  end
  frame.nh = frame.nh + 1
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT", 0, y)
  local parts = { title, "  " .. (seen and Kit.Seen(seen) or Kit.Seen(nil)) }
  if section then parts[#parts + 1] = "  " .. UI.Code(C.faint) .. string.format("%d of %d free", section.free or 0, section.slots or 0) .. "|r" end
  if shareNote then parts[#parts + 1] = "  " .. UI.Code(C.faint) .. shareNote .. "|r" end
  h:SetText(table.concat(parts))
  h:Show()
  y = y - 24
  if not section then
    local note = frame.notes[frame.nn + 1]
    if not note then
      note = Kit.Note(content, Kit.UNKNOWN)
      frame.notes[frame.nn + 1] = note
    end
    frame.nn = frame.nn + 1
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", 0, y)
    note:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    note:SetText(unknownText)
    note:Show()
    return y - 26
  end
  local col = 0
  local function nextTile(item)
    local tile = frame.tiles[frame.nt + 1]
    if not tile then
      tile = Kit.ItemTile(content, TILE)
      frame.tiles[frame.nt + 1] = tile
    end
    frame.nt = frame.nt + 1
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT", col * (TILE + TILE_GAP), y)
    tile:SetItem(item)
    tile:Show()
    col = col + 1
    if col >= BAGS_PER_ROW then
      col = 0
      y = y - (TILE + TILE_GAP)
    end
  end
  for _, box in ipairs(section.containers or {}) do
    local items = Store.Items(box.items)
    for _, item in ipairs(items) do nextTile(item) end
    for _ = 1, box.free or 0 do nextTile(nil) end
  end
  if col > 0 then y = y - (TILE + TILE_GAP) end
  return y - 10
end

Window:RegisterPane("bags", function(frame)
  buildHead(frame)
  frame.area = UI.ScrollArea(frame)
  frame.area:SetPoint("TOPLEFT", 0, -HEAD)
  frame.area:SetPoint("BOTTOMRIGHT")
  frame.tiles, frame.headers, frame.notes = {}, {}, {}
end, function(frame, key)
  local c = fillHead(frame, key)
  frame.area.content:SetWidth(frame.area:GetWidth() or 1000)
  frame.nt, frame.nh, frame.nn = 0, 0, 0
  local y = 0
  y = layoutSection(frame, y, "Bags", c.bags and c.bags.seen, c.bags, "Not read yet. It is read as soon as this character logs in with Retrospect on.")
  y = layoutSection(frame, y, "Character bank", c.bank and c.bank.seen, c.bank,
    "Never opened with Retrospect running, so this isn't empty, just unknown. Visit a banker on this character.")
  if R.db.accountBank then
    y = layoutSection(frame, y, "Account bank", R.db.accountBank.seen, R.db.accountBank, nil, "shared by the whole account")
  end
  for i = frame.nt + 1, #frame.tiles do frame.tiles[i]:Hide() end
  for i = frame.nh + 1, #frame.headers do frame.headers[i]:Hide() end
  for i = frame.nn + 1, #frame.notes do frame.notes[i]:Hide() end
  frame.area.content:SetHeight(math.max(1, -y))
end)

-------------------------------------------------------------------------------------------
-- Gear
-------------------------------------------------------------------------------------------

local SLOTS = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands", "Finger", "Finger", "Trinket", "Trinket", "Back", "Main hand", "Off hand", "Ranged", "Tabard" }

Window:RegisterPane("gear", function(frame)
  buildHead(frame)
  frame.table = rowsTable(frame, { {}, { label = "Slot", width = 110 } }, { rowHeight = 24 })
end, function(frame, key)
  local c = fillHead(frame, key)
  local rows = {}
  if not c.gear then
    rows[1] = { note = "Not read yet." }
  else
    rows[1] = { note = "As last seen, " .. Today.Ago(c.gear.seen) .. (c.ilvl and string.format(". Item level %d.", math.floor(c.ilvl)) or ".") .. " Hover a piece for the game's tooltip." }
    for slot, label in ipairs(SLOTS) do
      local items = Store.Items(c.gear.slots[slot])
      local item = items[1]
      if item then
        local q = Kit.QualityColor(R.Index:Quality(item.id) or item.q)
        rows[#rows + 1] = { item = item, cells = { UI.Code(q) .. Store:ItemName(item.id) .. "|r", UI.Code(C.faint) .. label .. "|r" } }
      end
    end
  end
  frame.table:SetRows(rows, true)
end)

-------------------------------------------------------------------------------------------
-- Mail & Auctions
-------------------------------------------------------------------------------------------

local function attachedText(packed, money)
  local parts = {}
  Store.EachItem(packed, function(id, count)
    parts[#parts + 1] = Store:ItemName(id) .. (count > 1 and (" x " .. count) or "")
  end)
  if money then parts[#parts + 1] = Kit.Money(money) end
  return #parts > 0 and table.concat(parts, ", ") or UI.Code(C.faint) .. "—|r"
end

local function expiresText(at)
  local left = (at or 0) - R.Now()
  if left <= 0 then return UI.Code(Kit.UNKNOWN) .. "may be gone|r" end
  local color = left < 3 * 86400 and Kit.DOWN or C.text
  return UI.Code(color) .. Today.Span(left) .. "|r"
end

local function auctionRow(rows, a)
  local entry = Store.Items(a.item)[1]
  if not entry then return end
  local q = Kit.QualityColor(R.Index:Quality(entry.id) or entry.q)
  rows[#rows + 1] = {
    item = entry,
    cells = { UI.Code(q) .. Store:ItemName(entry.id) .. (entry.count > 1 and (" x " .. entry.count) or "") .. "|r",
      a.bid and ("Bid " .. Kit.Money(a.bid)) or "", a.buyout and ("Buyout " .. Kit.Money(a.buyout)) or "",
      a.sold and (UI.Code(Kit.UP) .. "Sold|r") or expiresText(a.expires) },
  }
end

Window:RegisterPane("mail", function(frame)
  buildHead(frame)
  frame.table = rowsTable(frame, { { label = "What" }, { label = "Subject", width = 300 }, { label = "Attached", width = 220 }, { label = "Expires", width = 100, right = true } }, { rowHeight = 24 })
end, function(frame, key)
  local c = fillHead(frame, key)
  local rows = {}
  local function group(title, seen) rows[#rows + 1] = { group = title .. (seen ~= nil and ("  ·  " .. Today.Ago(seen)) or "") } end

  group("Mailbox", c.mail and c.mail.seen)
  if not c.mail then
    rows[#rows + 1] = { note = "Never opened with Retrospect running. Visit a mailbox on this character." }
  elseif #c.mail.list == 0 then
    rows[#rows + 1] = { note = "No mail when last seen." }
  else
    for _, m in ipairs(c.mail.list) do
      rows[#rows + 1] = { cells = { tostring(m.from or "?"), tostring(m.subject or ""), attachedText(m.items, m.money), expiresText(m.expires) } }
    end
  end

  group("On its way here")
  if c.incoming and #c.incoming > 0 then
    for _, m in ipairs(c.incoming) do
      local left = (m.arrives or 0) - R.Now()
      rows[#rows + 1] = { cells = { tostring(m.from or "?"), tostring(m.subject or ""), attachedText(m.items, m.money),
        left > 0 and ("in " .. Today.Span(left)) or "arrived" } }
    end
  else
    rows[#rows + 1] = { note = "Nothing. Mail you send between your characters shows here and in item counts as soon as you send it." }
  end

  group("Auctions", c.auctions and c.auctions.seen)
  if not c.auctions then
    rows[#rows + 1] = { note = "Never read. Open the auction house on this character." }
  elseif #(c.auctions.list or {}) == 0 then
    rows[#rows + 1] = { note = "No auctions when last seen." }
  else
    for _, a in ipairs(c.auctions.list) do auctionRow(rows, a) end
  end
  if c.auctions and #(c.auctions.bids or {}) > 0 then
    group("Bids")
    for _, a in ipairs(c.auctions.bids) do auctionRow(rows, a) end
  end
  frame.table:SetRows(rows, true)
end)

-------------------------------------------------------------------------------------------
-- Quests: the log as last seen, and "has this character done it?"
-------------------------------------------------------------------------------------------

local function alsoOn(id, key)
  local names = {}
  for _, entry in ipairs(Store:List()) do
    if entry.key ~= key and Store:QuestInLog(entry.key, id) then names[#names + 1] = Kit.Name(entry.c) end
  end
  return #names > 0 and table.concat(names, ", ") or UI.Code(C.faint) .. "—|r"
end

local function questState(entry)
  if entry.complete == "failed" then return UI.Code(Kit.DOWN) .. "Failed|r" end
  if entry.complete == true then return UI.Code(Kit.UP) .. "Ready to turn in|r" end
  if entry.need and entry.need > 0 then return string.format("In the log, %d/%d", entry.done or 0, entry.need) end
  return "In the log"
end

Window:RegisterPane("quests", function(frame)
  buildHead(frame)
  frame.search = UI.Search(frame, "Has this character done a quest?", function() Window:RefreshSoon() end)
  frame.search:SetPoint("TOPLEFT", 0, -HEAD)
  frame.search:SetWidth(380)
  frame.done = UI.Text(frame, "body", 13, C.muted)
  frame.done:SetPoint("LEFT", frame.search, "RIGHT", 14, 0)
  frame.table = Kit.Table(frame, { { label = "Quest" }, { label = "Level", width = 50, right = true }, { label = "State", width = 170 }, { label = "Also on it", width = 220 } }, { rowHeight = 24 })
  frame.table:SetPoint("TOPLEFT", 0, -(HEAD + 36))
  frame.table:SetPoint("BOTTOMRIGHT")
end, function(frame, key)
  local c = fillHead(frame, key)
  local count = Store:QuestDoneCount(key)
  frame.done:SetText(count and string.format("%s quests completed", Kit.Commas(count)) or UI.Code(Kit.UNKNOWN) .. "Completed quests not read yet|r")
  local rows = {}
  local query = strtrim(frame.search:GetText() or "")
  if query ~= "" then
    rows[1] = { group = "Search" }
    for _, found in ipairs(Core.DB:Search(query, { kinds = { quests = true }, limit = 40 })) do
      local cell = R.Compare.QuestCell(key, found.ids)
      local state = cell and (UI.Code(cell.color) .. cell.text .. (cell.small and (" " .. cell.small) or "") .. "|r") or UI.Code(C.faint) .. "Not done|r"
      rows[#rows + 1] = { cells = { found.name, "", state, alsoOn(found.ids[1], key) },
        onClick = function(button)
          if button == "RightButton" then Core:ShowActionMenu(frame, "quest", found.ids[1], { title = found.name }) end
        end }
    end
    if #rows == 1 then rows[2] = { note = "No quest has that name." } end
  end
  rows[#rows + 1] = { group = "The quest log  ·  " .. Today.Ago(c.quests and c.quests.seen) }
  local log = c.quests and c.quests.log or {}
  for _, entry in ipairs(log) do
    rows[#rows + 1] = { cells = { tostring(entry.title or Core.DB:Name("quests", entry.id) or entry.id), tostring(entry.level or ""), questState(entry), alsoOn(entry.id, key) },
      onClick = function(button)
        if button == "RightButton" then Core:ShowActionMenu(frame, "quest", entry.id, { title = entry.title }) end
      end }
  end
  if #log == 0 then rows[#rows + 1] = { note = "Nothing in the log when last seen." } end
  frame.table:SetRows(rows, true)
end)

-------------------------------------------------------------------------------------------
-- Professions: rank, then every recipe NorgannonDB lists, known or not
-------------------------------------------------------------------------------------------

Window:RegisterPane("prof", function(frame)
  buildHead(frame)
  frame.table = rowsTable(frame, { {}, { label = "Learned at", width = 80, right = true }, { label = "", width = 170, right = true } }, { rowHeight = 22 })
end, function(frame, key)
  local c = fillHead(frame, key)
  local skills = {}
  for skill, p in pairs(c.professions and c.professions.skills or {}) do skills[#skills + 1] = { skill = skill, p = p } end
  table.sort(skills, function(a, b) return tostring(a.p.name) < tostring(b.p.name) end)
  local rows = {}
  if #skills == 0 then rows[1] = { note = "No professions when last seen." } end
  for _, s in ipairs(skills) do
    local p = s.p
    local rank = tostring(p.rank or "?") .. (p.max and ("/" .. p.max) or "")
    local set = Store:Recipes(key, s.skill)
    rows[#rows + 1] = { group = string.format("%s %s%s", tostring(p.name), rank, p.seen and ("  ·  recipes read " .. Today.Ago(p.seen)) or "") }
    if not set then
      rows[#rows + 1] = { note = "Open this profession once on this character so Retrospect can read its recipes." }
    else
      local listed = {}
      for _, spell in ipairs(Core.DB:Recipes(s.skill)) do
        listed[spell] = true
        local rec = Core.DB:Recipe(spell)
        local ready = c.cooldowns and c.cooldowns[spell]
        local state
        if set[spell] then
          state = UI.Code(Kit.UP) .. "Known|r"
          if ready then
            state = state .. UI.Code(C.faint) .. (ready <= R.Now() and " · cooldown ready" or " · ready in " .. Today.Span(ready - R.Now())) .. "|r"
          end
        else
          state = UI.Code(C.faint) .. "Not known yet|r"
        end
        rows[#rows + 1] = { cells = { tostring(Core.DB:RecipeName(spell)), tostring(rec and rec.learn or ""), state },
          onClick = function(button)
            if button == "RightButton" and rec and rec.item then
              Core:ShowActionMenu(frame, "item", rec.item, { title = Core.DB:RecipeName(spell) })
            end
          end }
      end
      -- what the client knows and NorgannonDB doesn't, yet
      for spell in pairs(set) do
        if not listed[spell] then
          rows[#rows + 1] = { cells = { R.In("C_Spell", "GetSpellName", spell) or ("Recipe " .. spell), "", UI.Code(Kit.UP) .. "Known|r" } }
        end
      end
    end
  end
  frame.table:SetRows(rows, true)
end)

-------------------------------------------------------------------------------------------
-- Reputation
-------------------------------------------------------------------------------------------

Window:RegisterPane("rep", function(frame)
  buildHead(frame)
  frame.table = rowsTable(frame, { { label = "Faction" }, { label = "Standing", width = 120 }, { label = "Progress", width = 140, right = true } }, { rowHeight = 24 })
end, function(frame, key)
  local c = fillHead(frame, key)
  local rows = {}
  if not c.reputation then
    rows[1] = { note = "Not read yet." }
  else
    local groups, order = {}, {}
    for id, r in pairs(c.reputation.list) do
      local info = R.db.factions[id] or {}
      local g = info.group or "Other"
      if not groups[g] then
        groups[g] = {}
        order[#order + 1] = g
      end
      table.insert(groups[g], { id = id, r = r, name = info.name or ("Faction " .. id) })
    end
    table.sort(order)
    rows[1] = { note = "As last seen, " .. Today.Ago(c.reputation.seen) .. "." }
    for _, g in ipairs(order) do
      rows[#rows + 1] = { group = g }
      table.sort(groups[g], function(a, b) return a.name < b.name end)
      for _, f in ipairs(groups[g]) do
        rows[#rows + 1] = { cells = { f.name, R.Compare.StandingName(f.r.reaction), R.Compare.RepProgress(f.r) or UI.Code(C.faint) .. "Max|r" } }
      end
    end
  end
  frame.table:SetRows(rows, true)
end)
