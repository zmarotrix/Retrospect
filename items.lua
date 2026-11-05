-- The Items tab: who has it. Filter chips per place and "Can be mailed" over a list of what your
-- characters hold; the card on the right says where each stack is, who can learn a recipe, and what
-- your crafters do with it. Also the search result of the header's box, in any scope.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI
local C = UI.C

local Items = {}
R.Items = Items
local Kit, Store, Index = R.Kit, R.Store, R.Index

local DETAIL = 400
local DETAIL_SHARE = .45   -- of the pane's width, at most
local ICON = 30
local COUNT = 60    -- the count column
local MAX_ACTIONS = 3

local hide = {}        -- place -> true when its chip is off
local mailable = false
local selected         -- the item id shown in the card
local focusNext        -- an id another add-on asked for

function Items:Focus(id)
  focusNext = id
end

local function placeText(e)
  local parts = {}
  for _, place in ipairs(Index.PLACES) do
    if e.places[place.key] then
      parts[#parts + 1] = string.lower(place.label) .. " " .. e.places[place.key]
    end
  end
  for key, n in pairs(e.places) do
    if key == "guild" or key == "account" then parts[#parts + 1] = string.lower(Index.PLACE_LABEL[key]) .. " " .. n end
  end
  return table.concat(parts, ", ")
end
Items.PlaceText = placeText

---Plain words for how old a holding could be: only the oldest place worth a mention.
local function holdingAge(holding)
  local c = holding.holder.c
  if not c then return holding.holder.seen and Kit.Seen(holding.holder.seen) or "" end
  if holding.e.places.bank and c.bank then return Kit.Seen(c.bank.seen) end
  if holding.e.places.mail and c.mail then return Kit.Seen(c.mail.seen) end
  if holding.e.places.auction and c.auctions then return Kit.Seen(c.auctions.seen) end
  return ""
end
Items.HoldingAge = holdingAge

---Short kind of item, from the client when it knows ("Trade Goods"), else nothing.
local function kindOf(id)
  local _, kind = R.In("C_Item", "GetItemInfoInstant", id)
  return type(kind) == "string" and kind ~= "" and kind or nil
end

-------------------------------------------------------------------------------------------
-- The card: facts about an item across your characters
-------------------------------------------------------------------------------------------

---Who can use a recipe item: { { key, c, text, can } } for characters with the profession.
function Items.Learners(id)
  local spell = Core.DB:RecipeTaughtBy(id)
  local rec = spell and Core.DB:Recipe(spell)
  if not rec then return {}, nil end
  local out = {}
  for _, entry in ipairs(Store:List()) do
    local p = entry.c.professions and entry.c.professions.skills and entry.c.professions.skills[rec.skill]
    if p then
      local knows = Store:Knows(entry.key, spell, rec.skill)
      local need = rec.learn or 1
      if knows then
        out[#out + 1] = { key = entry.key, c = entry.c, state = "known", rank = p.rank, need = need }
      elseif (p.rank or 0) >= need then
        out[#out + 1] = { key = entry.key, c = entry.c, state = "can", rank = p.rank, need = need }
      else
        out[#out + 1] = { key = entry.key, c = entry.c, state = "low", rank = p.rank, need = need }
      end
    end
  end
  return out, spell
end

---Characters who know a recipe, with its cooldown when one is running.
local function knowers(spell, skill)
  local out = {}
  for _, entry in ipairs(Store:List()) do
    if Store:Knows(entry.key, spell, skill) then
      local ready = entry.c.cooldowns and entry.c.cooldowns[spell]
      local name = Kit.Name(entry.c)
      if ready then
        name = name .. UI.Code(C.faint) .. (ready <= R.Now() and " (cooldown ready)" or " (ready in " .. R.Today.Span(ready - R.Now()) .. ")") .. "|r"
      end
      out[#out + 1] = name
    end
  end
  return out
end

local function crafterRows(rows, id)
  local made = Core.DB:CraftedBy(id)
  local any = false
  for _, spell in ipairs(made) do
    local rec = Core.DB:Recipe(spell)
    local who = rec and knowers(spell, rec.skill) or {}
    if #who > 0 then
      if not any then rows[#rows + 1] = { group = "Your crafters" } any = true end
      rows[#rows + 1] = { note = "Made by " .. tostring(Core.DB:RecipeName(spell)) .. ": " .. table.concat(who, ", ") }
    end
  end
  local uses = Core.DB:ReagentOf(id)
  if #uses > 0 then
    local best = {}
    for _, entry in ipairs(Store:List()) do
      local n = 0
      for _, spell in ipairs(uses) do
        local rec = Core.DB:Recipe(spell)
        if rec and Store:Knows(entry.key, spell, rec.skill) then n = n + 1 end
      end
      if n > 0 then best[#best + 1] = Kit.Name(entry.c) .. " " .. n end
    end
    if #best > 0 then
      if not any then rows[#rows + 1] = { group = "Your crafters" } end
      rows[#rows + 1] = { note = string.format("Used in %d recipes. Known by: %s", #uses, table.concat(best, ", ")) }
    end
  end
end

local function fillCard(frame, id, scopeKey)
  local card = frame.card
  card:SetShown(id ~= nil)
  if not id then return end
  local q = Kit.QualityColor(Index:Quality(id))
  card.name:SetText(Store:ItemName(id))
  card.name:SetTextColor(q[1], q[2], q[3])
  card.tile:SetItem({ id = id, q = Index:Quality(id) })

  local holdings, total = Index:Holdings(id, scopeKey)
  local who = #holdings == 1 and holdings[1].holder.label or (#holdings .. " holders")
  local kind = kindOf(id)
  card.facts:SetText((kind and (kind .. " · ") or "") .. string.format("%d on %s", total, who))

  local rows = { { group = "Where" } }
  for _, h in ipairs(holdings) do
    local age = Items.HoldingAge(h)
    rows[#rows + 1] = { cells = {
      (h.holder.c and (Kit.Name(h.holder.c) .. "  " .. UI.Code(C.muted) .. placeText(h.e) .. "|r") or h.holder.label) .. (age ~= "" and ("  " .. age) or ""),
      tostring(h.e.total) } }
  end
  local free = 0
  for _, h in ipairs(holdings) do free = free + h.e.free end
  if free == 0 and #holdings > 0 then rows[#rows + 1] = { note = "Soulbound or worn: it can't be mailed." } end

  local learners, spell = Items.Learners(id)
  if spell then
    rows[#rows + 1] = { group = "Who can use the recipe" }
    for _, l in ipairs(learners) do
      local text = l.state == "known" and UI.Code(C.faint) .. "Knows it|r"
        or l.state == "can" and UI.Code(Kit.UP) .. "Can learn|r"
        or UI.Code(C.muted) .. string.format("Skill %d, needs %d|r", l.rank or 0, l.need or 0)
      rows[#rows + 1] = { cells = { Kit.Name(l.c), text } }
    end
    if #learners == 0 then rows[#rows + 1] = { note = "None of your characters has this profession." } end
  end
  crafterRows(rows, id)
  card.rows:SetRows(rows)

  -- what other suite add-ons offer for it
  local actions = Core:ActionsFor("item", id)
  local shown = 0
  for i = 1, MAX_ACTIONS do
    local b = card.actions[i]
    local action
    repeat
      shown = shown + 1
      action = actions[shown]
    until not action or action.addon ~= "retrospect"
    b:SetShown(action ~= nil)
    if action then
      b:SetLabel(action.label)
      b:SetScript("OnClick", function() action.run("item", id) end)
    end
  end
end

-------------------------------------------------------------------------------------------
-- The list
-------------------------------------------------------------------------------------------

local function createRow(row, content)
  row.tile = Kit.ItemTile(content, ICON)
  row.tile:SetPoint("LEFT", 8, 0)
  row.count = UI.Text(content, "body", 15)
  row.count:SetPoint("RIGHT", -10, 0)
  row.count:SetJustifyH("RIGHT")
  row.name = UI.Text(content, "body", 14)
  row.name:SetPoint("TOPLEFT", row.tile, "TOPRIGHT", 8, 0)
  row.name:SetPoint("TOPRIGHT", content, "TOPRIGHT", -COUNT, -6)
  row.name:SetWordWrap(false)
  row.where = UI.Text(content, "body", 12, C.muted)
  row.where:SetPoint("BOTTOMLEFT", row.tile, "BOTTOMRIGHT", 8, 0)
  row.where:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -COUNT, 6)
  row.where:SetWordWrap(false)
end

local function updateRow(row, item)
  local r = item.row
  local q = Kit.QualityColor(r.q)
  row.name:SetText(r.name)
  row.name:SetTextColor(q[1], q[2], q[3])
  row.where:SetText(table.concat(r.holders, ", "))
  row.count:SetText(r.total)
  row.tile:SetItem({ id = r.id, q = r.q })
end

local function build(frame)
  local chips = CreateFrame("Frame", nil, frame)
  chips:SetPoint("TOPLEFT")
  chips:SetPoint("TOPRIGHT", 0, 0)
  chips:SetHeight(24)
  local label = UI.Text(chips, "body", 12, C.faint)
  label:SetPoint("LEFT", 0, 0)
  label:SetText("Show")
  local previous = label
  frame.placeChips = {}
  for _, place in ipairs(Index.PLACES) do
    local chip = UI.Chip(chips, place.label, nil, function(on)
      hide[place.key] = not on or nil
      R.Window:Refresh()
    end)
    chip.place = place.key
    chip:SetOn(true, true)
    chip:SetPoint("LEFT", previous, "RIGHT", 5, 0)
    frame.placeChips[#frame.placeChips + 1] = chip
    previous = chip
  end
  frame.mailable = UI.Chip(chips, "Can be mailed", nil, function(on)
    mailable = on
    R.Window:Refresh()
  end)
  frame.mailable:SetPoint("LEFT", previous, "RIGHT", 14, 0)
  frame.mailable:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Can be mailed", 1, 1, 1)
    GameTooltip:AddLine("Hides soulbound and worn items: only what you could send to another character.", C.muted[1], C.muted[2], C.muted[3], true)
    GameTooltip:Show()
  end)
  frame.mailable:HookScript("OnLeave", function() GameTooltip:Hide() end)

  frame.pane = UI.Pane(frame)
  frame.pane:SetPoint("TOPLEFT", chips, "BOTTOMLEFT", 0, -6)
  frame.list = UI.List(frame.pane, {
    rowHeight = 42, createRow = createRow, updateRow = updateRow,
    onClick = function(item, _, button)
      if button == "RightButton" then
        Kit.ItemClick(frame.pane, item.row.id, button)
        return
      end
      selected = item.row.id
      frame.list:Select(item)
      fillCard(frame, selected, frame.scopeKey)
    end,
  })
  frame.list:SetPoint("TOPLEFT", 1, -1)
  frame.list:SetPoint("BOTTOMRIGHT", -1, 1)
  frame.empty = Kit.Note(frame.pane, C.muted)
  frame.empty:SetPoint("TOPLEFT", 14, -14)
  frame.empty:SetPoint("TOPRIGHT", -14, -14)

  local card = UI.Card(frame)
  card:SetPoint("TOPRIGHT", chips, "BOTTOMRIGHT", 0, -6)
  card:SetPoint("BOTTOMRIGHT")
  card:SetWidth(DETAIL)
  frame.pane:SetPoint("BOTTOMRIGHT", card, "BOTTOMLEFT", -12, 0)
  frame.card = card
  card.tile = Kit.ItemTile(card.body, 36)
  card.tile:SetPoint("TOPLEFT")
  card.name = UI.Text(card.body, "title", 17)
  card.name:SetPoint("TOPLEFT", card.tile, "TOPRIGHT", 10, 0)
  card.name:SetPoint("TOPRIGHT", 0, 0)
  card.name:SetWordWrap(false)
  card.facts = UI.Text(card.body, "body", 13, C.muted)
  card.facts:SetPoint("BOTTOMLEFT", card.tile, "BOTTOMRIGHT", 10, 0)
  card.actions = {}
  for i = 1, MAX_ACTIONS do
    local b = UI.Button(card.body, "Action", "quiet")
    b:SetHeight(22)
    if i == 1 then
      b:SetPoint("BOTTOMLEFT")
    else
      b:SetPoint("LEFT", card.actions[i - 1], "RIGHT", 6, 0)
    end
    b:Hide()
    card.actions[i] = b
  end
  card.rows = Kit.Table(card.body, { {}, { width = 44, right = true } }, { rowHeight = 22 })
  card.rows:SetPoint("TOPLEFT", 0, -46)
  card.rows:SetPoint("BOTTOMRIGHT", 0, 30)
end

local function fill(frame, scopeKey)
  frame.scopeKey = scopeKey
  -- the card gives way first in a narrow window, so the list stays usable
  local width = frame:GetWidth() or 0
  frame.card:SetWidth(width > 0 and math.min(DETAIL, math.floor(width * DETAIL_SHARE)) or DETAIL)
  local query = R.Window:Get().search:GetText() or ""
  local found = Index:Search({ query = query, scope = scopeKey, hidePlaces = hide, mailable = mailable })
  local items = {}
  for i, row in ipairs(found) do items[i] = { row = row } end
  frame.list:SetData(items, query == "")
  if #found == 0 then
    local c = scopeKey and Store:Get(scopeKey)
    frame.empty:SetText(query ~= "" and (c and (tostring(c.name) .. " doesn't have that.") or "No character has that.")
      .. (Core:AddonState("archivum") == "loaded" and " Archivum looks things up in the whole game." or "")
      or "Nothing here yet. Open your bags, bank and mailbox on each character and they appear.")
  end
  frame.empty:SetShown(#found == 0)

  if focusNext then
    selected, focusNext = focusNext, nil
  end
  local chosen
  for _, item in ipairs(items) do
    if item.row.id == selected then chosen = item break end
  end
  chosen = chosen or items[1]
  frame.list:Select(chosen)
  selected = chosen and chosen.row.id or nil
  fillCard(frame, selected, scopeKey)
end

R.Window:RegisterPane("items", build, fill)
