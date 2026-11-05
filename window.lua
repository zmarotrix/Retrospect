-- Retrospect's window (design/suite/retrospect.html): the suite frame with a search in its header,
-- the rail on the left (All characters, then each character by realm), and tabs over a pane. The
-- rail sets the scope of everything on the right: tabs, search and what they show.
--
-- The mockup's layout is 1320 x 800; like Oracle, the window keeps those numbers and is scaled to
-- the same share of the screen, so its proportions hold. Size and opacity are settings.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI
local C = UI.C

local Window = {}
R.Window = Window
local Store, Kit = R.Store, R.Kit

local W, H = 1320, 800
local RAIL = 244
local SCREEN_SHARE = .88
local SEARCH_WIDTH = 330

local ALL_TABS = { { key = "today", label = "Today" }, { key = "items", label = "Items" }, { key = "compare", label = "Compare" }, { key = "gold", label = "Gold" } }
local CHAR_TABS = {
  { key = "over", label = "Overview" }, { key = "bags", label = "Bags & Bank" }, { key = "gear", label = "Gear" },
  { key = "mail", label = "Mail & Auctions" }, { key = "quests", label = "Quests" }, { key = "prof", label = "Professions" }, { key = "rep", label = "Reputation" },
}

local FOOTERS = {
  today = "Facts, not advice. Deadlines are worked out from when each thing was last seen",
  items = "Hover for the item · shift-click links it · right-click for the suite's menu",
  compare = "Click a character's name to open it · right-click a row for the suite's menu",
  gold = "One value per character per day, kept for a year. Offline characters hold their last known gold",
}
local CHAR_FOOTER = "Everything here is what this character had when you last saw it"

local win
local panes = {}

-------------------------------------------------------------------------------------------
-- The pane registry: each tab's file registers how to build and fill its pane
-------------------------------------------------------------------------------------------

---build(frame) once, fill(frame, scopeKey or nil) each time it shows or something changes.
function Window:RegisterPane(key, build, fill)
  panes[key] = { build = build, fill = fill }
end

local function paneFrame(key)
  local p = panes[key]
  if not p then return nil end
  if not p.frame then
    p.frame = CreateFrame("Frame", nil, win.paneArea)
    p.frame:SetAllPoints()
    p.build(p.frame)
  end
  return p.frame
end

local function scope()
  local who = R.db.who
  if who ~= "all" and Store:Get(who) then return who end
  return nil
end

-------------------------------------------------------------------------------------------
-- Which pane shows
-------------------------------------------------------------------------------------------

local function defaultTab(key) return key and "over" or "today" end

local function validTab(tab, key)
  for _, t in ipairs(key and CHAR_TABS or ALL_TABS) do
    if t.key == tab then return true end
  end
  return false
end

---The search is typed: the Items pane of the current scope shows it; cleared, the tab comes back.
local function paneKey()
  if (win.search:GetText() or "") ~= "" then return "items" end
  return R.db.tab
end

local function fillPane()
  local key, who = paneKey(), scope()
  for k, p in pairs(panes) do
    if p.frame then p.frame:SetShown(k == key) end
  end
  local frame = paneFrame(key)
  if frame then
    frame:Show()
    panes[key].fill(frame, who)
  end
  win.footerText:SetText(who and CHAR_FOOTER or FOOTERS[key] or "")
end

-------------------------------------------------------------------------------------------
-- The rail
-------------------------------------------------------------------------------------------

local function railItems()
  local items = { { all = true } }
  local realm
  for _, entry in ipairs(Store:List()) do
    if entry.c.realm ~= realm then
      realm = entry.c.realm
      items[#items + 1] = { group = tostring(realm) }
    end
    items[#items + 1] = { key = entry.key, c = entry.c }
  end
  return items
end

local function totalGold()
  local total = 0
  for _, entry in ipairs(Store:List()) do total = total + (entry.c.money or 0) end
  return total
end
Window.TotalGold = totalGold

local function fillRail()
  local items = railItems()
  win.rail:SetData(items, true)
  local who = R.db.who
  for _, item in ipairs(items) do
    if (item.all and who == "all") or (item.key and item.key == who) then
      win.rail:Select(item)
      break
    end
  end
  win.railGold:SetText(Kit.Money(totalGold()))
end

local function createRailRow(row, content)
  row.badge = CreateFrame("Frame", nil, content)
  row.badge:SetSize(26, 26)
  row.badge:SetPoint("LEFT", 8, 0)
  row.badge.edge = UI.Tex(row.badge, "BACKGROUND", 0, C.black)
  row.badge.edge:SetAllPoints()
  row.badge.fill = UI.Tex(row.badge, "BACKGROUND", 1)
  row.badge.fill:SetPoint("TOPLEFT", 1, -1)
  row.badge.fill:SetPoint("BOTTOMRIGHT", -1, 1)
  row.badge.text = UI.Text(row.badge, "title", 13, { .07, .07, .07 })
  row.badge.text:SetPoint("CENTER")
  row.name = UI.Text(content, "body", 14)
  row.name:SetPoint("TOPLEFT", row.badge, "TOPRIGHT", 8, 1)
  row.name:SetWordWrap(false)
  row.meta = UI.Text(content, "body", 12, C.faint)
  row.meta:SetPoint("BOTTOMLEFT", row.badge, "BOTTOMRIGHT", 8, -1)
  row.meta:SetWordWrap(false)
  row.money = UI.Text(content, "body", 12, C.muted)
  row.money:SetPoint("TOPRIGHT", -8, -8)
  row.money:SetJustifyH("RIGHT")
  row.flag = UI.Text(content, "bold", 11, { 1, 1, 1 })
  row.flag:SetPoint("BOTTOMRIGHT", -8, 7)
  row.flag:SetJustifyH("RIGHT")
end

local function updateRailRow(row, item)
  if item.all then
    local a = UI.Accent("retrospect")
    row.badge.fill:SetColorTexture(a[1], a[2], a[3], 1)
    row.badge.text:SetText("All")
    row.badge.text:SetFontObject(UI.Font("bold", 10))
    row.name:SetText("All characters")
    local n = #R.Today:Events()
    row.meta:SetText(n == 1 and "1 thing on today's list" or n .. " things on today's list")
    row.money:SetText("")
    row.flag:SetText("")
    return
  end
  local c = item.c
  local cc = Kit.ClassColor(c.class)
  row.badge.fill:SetColorTexture(cc[1], cc[2], cc[3], 1)
  row.badge.text:SetFontObject(UI.Font("title", 13))
  row.badge.text:SetText(c.level or "?")
  local mine = item.key == Store:MyKey()
  row.name:SetText(Kit.Name(c) .. (mine and " |cff6fdc6f•|r" or ""))
  row.meta:SetText(mine and (c.zone or "Here") or R.Today.Ago(c.seen))
  row.money:SetText(c.money and Kit.Money(c.money) or "")
  local n = #R.Today:For(item.key)
  row.flag:SetText(n > 0 and (UI.Code(UI.Accent("retrospect")) .. n .. "|r") or "")
end

-------------------------------------------------------------------------------------------
-- The frame
-------------------------------------------------------------------------------------------

function Window.Scale()
  local screen = UIParent:GetHeight() or 768
  return math.min(1.25, screen * SCREEN_SHARE / H) * (R.db.scale or 1)
end

function Window:ApplyLook()
  if not win then return end
  win:SetSize(W, H)
  win:SetScale(Window.Scale())
  win:SetAlpha(R.db.opacity or 1)
  win.locked = R.db.locked and true or false
end

local function build()
  win = UI.Window({ name = "RetrospectWindow", addon = "retrospect", title = "Retrospect", width = W, height = H, footer = true })
  win:SetAccent("retrospect")
  win:Hide()

  win.search = UI.Search(win.header, "Who has it? Search every character…", function()
    if win:IsShown() then fillPane() end
  end, nil, "/retro")
  win.search:SetWidth(SEARCH_WIDTH)
  win.search:SetPoint("RIGHT", win.powered, "LEFT", -14, 0)

  -- the rail
  local rail = CreateFrame("Frame", nil, win.body)
  rail:SetPoint("TOPLEFT")
  rail:SetPoint("BOTTOMLEFT")
  rail:SetWidth(RAIL)
  win.railFrame = rail
  local edge = UI.Tex(rail, "ARTWORK", 0, C.line)
  edge:SetWidth(1)
  edge:SetPoint("TOPRIGHT")
  edge:SetPoint("BOTTOMRIGHT")
  local foot = CreateFrame("Frame", nil, rail)
  foot:SetPoint("BOTTOMLEFT")
  foot:SetPoint("BOTTOMRIGHT", -1, 0)
  foot:SetHeight(50)
  local rule = UI.Rule(foot)
  rule:SetPoint("TOPLEFT")
  rule:SetPoint("TOPRIGHT")
  local label = UI.Text(foot, "body", 12, C.muted)
  label:SetPoint("TOPLEFT", 12, -8)
  label:SetText("All characters")
  win.railGold = UI.Text(foot, "body", 15)
  win.railGold:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
  win.rail = UI.List(rail, {
    rowHeight = 42,
    createRow = createRailRow,
    updateRow = updateRailRow,
    onClick = function(item)
      if item.all then Window:Select("all") else Window:Select(item.key) end
    end,
  })
  win.rail:SetPoint("TOPLEFT")
  win.rail:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT")

  -- tabs over the pane
  local main = CreateFrame("Frame", nil, win.body)
  main:SetPoint("TOPLEFT", rail, "TOPRIGHT")
  main:SetPoint("BOTTOMRIGHT")
  win.main = main
  local function selectTab(key)
    R.db.tab = key
    win.search:SetText("")
    fillPane()
  end
  win.allTabs = UI.Tabs(main, ALL_TABS, selectTab)
  win.charTabs = UI.Tabs(main, CHAR_TABS, selectTab)
  for _, bar in ipairs({ win.allTabs, win.charTabs }) do
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:ApplyAccent(UI.Accent("retrospect"))
  end
  win.paneArea = CreateFrame("Frame", nil, main)
  win.paneArea:SetPoint("TOPLEFT", win.allTabs, "BOTTOMLEFT", 14, -10)
  win.paneArea:SetPoint("BOTTOMRIGHT", -14, 10)

  -- the footer's settings button
  win.gear = UI.Button(win.footer, "Settings", "quiet", function() R:OpenSettings() end)
  win.gear:SetHeight(20)
  win.gear:SetPoint("RIGHT", -10, 0)

  Window:ApplyLook()
end

function Window:Get()
  if not win and R.db then build() end
  return win
end

local function applyScope()
  local key = scope()
  win.allTabs:SetShown(not key)
  win.charTabs:SetShown(key ~= nil)
  if not validTab(R.db.tab, key) then R.db.tab = defaultTab(key) end
  local bar = key and win.charTabs or win.allTabs
  bar:Select(R.db.tab, true)
  bar:SetCount("today", not key and #R.Today:Events() or nil)
  if key then
    local c = Store:Get(key)
    win:SetSub(string.format("%s · %s", tostring(c.name), key == Store:MyKey() and "logged in now" or ("as last seen " .. R.Today.Ago(c.seen))))
    win.search.placeholder:SetText(string.format("Search %s's things…", tostring(c.name)))
  else
    local n = #Store:List()
    win:SetSub(n == 1 and "1 character" or n .. " characters")
    win.search.placeholder:SetText("Who has it? Search every character…")
  end
end

-------------------------------------------------------------------------------------------
-- What the rest of the add-on calls
-------------------------------------------------------------------------------------------

---Draws everything again from the saved data.
function Window:Refresh()
  if not (win and win:IsShown()) then return end
  applyScope()
  fillRail()
  fillPane()
end

---Redraws on the next frame, once however many things changed.
function Window:RefreshSoon()
  if not (win and win:IsShown()) then return end
  Core:NextFrame(function() Window:Refresh() end, "retrospect.refresh")
end

---Puts the rail on "all" or a character (and a tab, else that scope's first).
function Window:Select(who, tab)
  self:Get()
  R.db.who = who
  R.db.tab = tab or defaultTab(who ~= "all" and who or nil)
  win.search:SetText("")
  self:Refresh()
end

function Window:Open()
  self:Get()
  if not win then return end
  win:Show()
  self:Refresh()
end

---/retro <text> and anything else that asks "who has it": every character's Items, searched.
function Window:Search(text)
  self:Open()
  R.db.who = "all"
  R.db.tab = "items"
  win.search:SetText(text or "")
  self:Refresh()
end

---Opens Items on one item, across every character.
function Window:ShowItem(id)
  self:Open()
  R.db.who = "all"
  R.db.tab = "items"
  win.search:SetText("")
  if R.Items then R.Items:Focus(id) end
  self:Refresh()
end

---Opens Compare on one quest: who has done it, who is on it.
function Window:ShowQuest(id)
  self:Open()
  R.db.who = "all"
  R.db.tab = "compare"
  R.db.cmp = "quest"
  win.search:SetText("")
  if R.Compare then R.Compare:FocusQuest(id) end
  self:Refresh()
end

Window.W, Window.H, Window.RAIL = W, H, RAIL
