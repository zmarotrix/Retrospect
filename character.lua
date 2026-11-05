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

---The heading all these panes share: the name, then who they are.
local function buildHead(frame)
  frame.name = UI.Text(frame, "title", 22)
  frame.name:SetPoint("TOPLEFT", 0, -2)
  frame.facts = UI.Text(frame, "body", 13, C.muted)
  frame.facts:SetPoint("BOTTOMLEFT", frame.name, "BOTTOMRIGHT", 10, 2)
end

local function classWord(c)
  if c.className then return c.className end
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
R.CharacterHead = { Build = buildHead, Fill = fillHead, HEIGHT = HEAD }

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
  local function add(label, value, tab)
    rows[#rows + 1] = { cells = { UI.Code(C.muted) .. label .. "|r", value },
      onClick = tab and function() Window:Select(key, tab) end or nil }
  end
  local mine = key == Store:MyKey()
  add("Last seen", (mine and "Now" or Today.Ago(c.seen)) .. (c.zone and (", " .. c.zone) or ""))
  add("Gold", Kit.Money(c.money or 0))
  add("Played", Kit.Played(c.played) or UI.Code(C.faint) .. "Not read yet|r")
  local rest, estimate = Store:Rest(key)
  if rest then
    add("Rested", string.format("%d%% of a level%s", math.floor(rest * 100 + .5), estimate and UI.Code(C.faint) .. " (estimate)|r" or ""))
  end
  add("Bag space", c.bags and string.format("%d of %d free", c.bags.free, c.bags.slots) or Kit.Seen(nil), "bags")
  add("Item level", c.ilvl and tostring(math.floor(c.ilvl)) or UI.Code(C.faint) .. "—|r")
  local profs = {}
  for _, p in pairs(c.professions and c.professions.skills or {}) do profs[#profs + 1] = tostring(p.name) .. " " .. tostring(p.rank) end
  table.sort(profs)
  add("Professions", #profs > 0 and table.concat(profs, " · ") or "None", "prof")
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
  frame.table = rowsTable(frame, { { label = "What", width = 180 }, { label = "Subject" }, { label = "Attached", width = 200 }, { label = "Expires", width = 80, right = true } }, { rowHeight = 24 })
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

local PROF_FILTERS = { { key = "all", label = "All" }, { key = "known", label = "Known" }, { key = "unknown", label = "Not known" } }

Window:RegisterPane("prof", function(frame)
  buildHead(frame)
  frame.filter = UI.Segmented(frame, PROF_FILTERS, function(key)
    R.db.profFilter = key
    Window:Refresh()
  end, 20)
  frame.filter:SetPoint("TOPRIGHT", 0, -2)
  frame.table = rowsTable(frame, { { label = "Recipe" }, { label = "Learned at", width = 70, right = true }, { label = "", width = 180, bar = true } }, { rowHeight = 24 })
end, function(frame, key)
  local c = fillHead(frame, key)
  local filter = R.db.profFilter or "all"
  frame.filter:Select(filter, true)
  local skills = {}
  for skill, p in pairs(c.professions and c.professions.skills or {}) do skills[#skills + 1] = { skill = skill, p = p } end
  table.sort(skills, function(a, b) return tostring(a.p.name) < tostring(b.p.name) end)
  local rows = {}
  if #skills == 0 then rows[1] = { note = "No professions when last seen." } end
  for _, s in ipairs(skills) do
    local p = s.p
    local rank = tostring(p.rank or "?") .. (p.max and ("/" .. p.max) or "")
    local set = Store:Recipes(key, s.skill)
    rows[#rows + 1] = { heading = true, cells = {
      UI.Code(C.gold) .. tostring(p.name) .. "|r  " .. rank .. (p.seen and (UI.Code(C.muted) .. "  ·  recipes read " .. Today.Ago(p.seen) .. "|r") or ""),
      "", { ratio = p.max and p.max > 0 and (p.rank or 0) / p.max or 0, color = UI.Accent("retrospect") } } }
    if not set then
      rows[#rows + 1] = { note = "Recipes unknown: open this profession once on this character and Retrospect reads them." }
    else
      local listed = {}
      for _, spell in ipairs(Core.DB:Recipes(s.skill)) do
        listed[spell] = true
        local known = set[spell] == true
        if filter == "all" or (filter == "known") == known then
          local rec = Core.DB:Recipe(spell)
          local ready = c.cooldowns and c.cooldowns[spell]
          local state = known and (UI.Code(Kit.UP) .. "Known|r") or (UI.Code(C.muted) .. "Not known yet|r")
          if known and ready then
            state = state .. UI.Code(C.muted) .. (ready <= R.Now() and " · cooldown ready" or " · ready in " .. Today.Span(ready - R.Now())) .. "|r"
          end
          local name = tostring(Core.DB:RecipeName(spell))
          rows[#rows + 1] = { cells = { known and name or (UI.Code(C.muted) .. name .. "|r"), tostring(rec and rec.learn or ""), state },
            onClick = function(button)
              if button == "RightButton" and rec and rec.item then
                Core:ShowActionMenu(frame, "item", rec.item, { title = Core.DB:RecipeName(spell) })
              end
            end }
        end
      end
      -- what the client knows and NorgannonDB doesn't, yet
      if filter ~= "unknown" then
        for spell in pairs(set) do
          if not listed[spell] then
            rows[#rows + 1] = { cells = { R.In("C_Spell", "GetSpellName", spell) or ("Recipe " .. spell), "", UI.Code(Kit.UP) .. "Known|r" } }
          end
        end
      end
    end
  end
  frame.table:SetRows(rows, true)
end)

-------------------------------------------------------------------------------------------
-- Reputation: every faction with its standing in colour and a bar through that standing
-------------------------------------------------------------------------------------------

local VIEWS = { { key = "group", label = "By group" }, { key = "standing", label = "By standing" } }

local function repRow(f)
  local color = Kit.STANDING[f.r.reaction] or C.text
  local ratio, numbers = Kit.StandingProgress(f.r)
  return { cells = { f.name, UI.Code(color) .. Kit.StandingName(f.r.reaction) .. "|r", { ratio = ratio, color = color },
    numbers or (UI.Code(C.muted) .. "Max|r") } }
end

Window:RegisterPane("rep", function(frame)
  buildHead(frame)
  frame.view = UI.Segmented(frame, VIEWS, function(key)
    R.db.repView = key
    Window:Refresh()
  end, 20)
  frame.view:SetPoint("TOPRIGHT", 0, -2)
  frame.summary = UI.Text(frame, "body", 13, C.muted)
  frame.summary:SetPoint("TOPLEFT", 0, -HEAD)
  frame.table = Kit.Table(frame, { { label = "Faction" }, { label = "Standing", width = 96 }, { label = "Progress", width = 200, bar = true },
    { label = "", width = 96, right = true } }, { rowHeight = 26 })
  frame.table:SetPoint("TOPLEFT", 0, -(HEAD + 22))
  frame.table:SetPoint("BOTTOMRIGHT")
end, function(frame, key)
  local c = fillHead(frame, key)
  local view = R.db.repView or "group"
  frame.view:Select(view, true)
  local rows = {}
  if not c.reputation then
    frame.summary:SetText("")
    rows[1] = { note = "Not read yet. It is read when this character logs in with Retrospect on." }
    frame.table:SetRows(rows, true)
    return
  end
  local factions, counts = {}, {}
  for id, r in pairs(c.reputation.list) do
    local info = R.db.factions[id] or {}
    factions[#factions + 1] = { id = id, r = r, name = info.name or ("Faction " .. id), group = info.group or "Other" }
    counts[r.reaction] = (counts[r.reaction] or 0) + 1
  end
  table.sort(factions, function(a, b) return a.name < b.name end)

  -- the character's standing at a glance, best first
  local summary = {}
  for reaction = 8, 1, -1 do
    if counts[reaction] then
      summary[#summary + 1] = UI.Code(Kit.STANDING[reaction]) .. counts[reaction] .. " " .. Kit.StandingName(reaction) .. "|r"
    end
  end
  frame.summary:SetText(table.concat(summary, UI.Code(C.faint) .. "  ·  |r") .. "   " .. Kit.Seen(c.reputation.seen))

  if view == "standing" then
    for reaction = 8, 1, -1 do
      if counts[reaction] then
        rows[#rows + 1] = { group = UI.Code(Kit.STANDING[reaction]) .. Kit.StandingName(reaction) .. "|r" }
        for _, f in ipairs(factions) do
          if f.r.reaction == reaction then rows[#rows + 1] = repRow(f) end
        end
      end
    end
  else
    local groups, order = {}, {}
    for _, f in ipairs(factions) do
      if not groups[f.group] then
        groups[f.group] = {}
        order[#order + 1] = f.group
      end
      table.insert(groups[f.group], f)
    end
    table.sort(order)
    for _, g in ipairs(order) do
      rows[#rows + 1] = { group = g }
      for _, f in ipairs(groups[g]) do rows[#rows + 1] = repRow(f) end
    end
  end
  frame.table:SetRows(rows, true)
end)
