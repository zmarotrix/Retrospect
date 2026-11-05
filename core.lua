-- Retrospect: what your other characters had when you last saw them. Account-wide alt tracking
-- for WoW Forever, built on NorgannonDB and NorgannonDB_Core.
-- Plan: docs/retrospect-v1.md in the suite workspace; the look: design/suite/retrospect.html.

local ADDON = ...
local Core = NorgannonCore
local DB = NorgannonDB

Retrospect = { addonName = ADDON or "Retrospect" }
local R = Retrospect

if not (Core and Core:Require(1, 15)) or not (DB and DB:RequireSchema(1, 4)) then
  R.disabled = true
  C_Timer.After(5, function()
    print("|cffffb35cRetrospect|r needs NorgannonDB 1.4 and NorgannonDB Core 1.15 or newer; it is turned off.")
  end)
  return
end

R.PREFIX = "|cffffb35cRetrospect|r"
function R:Print(msg) Core:Print(msg, self.PREFIX) end

-------------------------------------------------------------------------------------------
-- Calling the client. Docs list calls for every game flavour, so any of them may be missing or
-- refuse on Forever: nothing here assumes one works, and a secret value counts as no answer.
-------------------------------------------------------------------------------------------

local function clean(ok, ...)
  if not ok then return nil end
  local n = select("#", ...)
  if n == 0 then return nil end
  local out = { ... }
  for i = 1, n do
    if Core.IsSecret(out[i]) then out[i] = nil end
  end
  return unpack(out, 1, n)
end

---fn(...) with errors and secret values turned into nil; nil when fn doesn't exist.
function R.Try(fn, ...)
  if not fn then return nil end
  return clean(pcall(fn, ...))
end

---The global function name(...), through Try.
function R.Global(name, ...)
  return R.Try(rawget(_G, name), ...)
end

---The namespaced client function ns.name(...), through Try: R.In("C_Bank", "CanViewBank").
function R.In(ns, name, ...)
  local t = rawget(_G, ns)
  return R.Try(t and t[name], ...)
end

function R.Now()
  return R.Global("GetServerTime") or time()
end

-------------------------------------------------------------------------------------------
-- Saved data (account-wide; store.lua holds the characters)
-------------------------------------------------------------------------------------------

local DEFAULTS = {
  who = "all",           -- the rail's selection: "all" or a character's key
  tab = "today",
  cmp = "rep",           -- Compare's mode
  goldRange = 30,        -- days on the gold chart
  scale = 1,
  opacity = 1,
  locked = false,
  tooltips = true,       -- who holds an item, in item tooltips
  tooltipNeeds = true,   -- who can learn a recipe or needs an item for a quest, in tooltips
  loginLine = true,      -- one quiet chat line at login when something is urgent
}

local function fill(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then target[k] = v end
  end
  return target
end

Core:On("ADDON_LOADED", R, function(_, name)
  if name ~= R.addonName then return end
  Core:Off("ADDON_LOADED", R)
  local saved = rawget(_G, "RetrospectDB")
  RetrospectDB = fill(type(saved) == "table" and saved or {}, DEFAULTS)
  R.db = RetrospectDB
  R.db.chars = R.db.chars or {}       -- ["Realm-Name"] = a character (store.lua)
  R.db.guilds = R.db.guilds or {}     -- ["Realm-Guild"] = a guild bank
  R.db.names = R.db.names or {}       -- item names NorgannonDB doesn't have
  R.db.factions = R.db.factions or {} -- faction id = { name, group }
  R.db.probe = R.db.probe or {}       -- what each reader last got (probe.lua)
  R.Store:Loaded()
end)

-- Messages inside Retrospect ride on the Core's bus, prefixed RETROSPECT_
function R:Send(message, ...) Core:Send("RETROSPECT_" .. message, ...) end
function R:Listen(message, owner, fn) Core:Listen("RETROSPECT_" .. message, owner, fn) end

---Something about a character changed: its item counts (when items is true) and whatever is on screen.
function R:Changed(key, items)
  if items and self.Index then self.Index:Invalidate(key) end
  if self.Today then self.Today:Invalidate() end
  if self.Window then self.Window:RefreshSoon() end
end

-------------------------------------------------------------------------------------------
-- Opening
-------------------------------------------------------------------------------------------

---Opens Retrospect, or closes it when it is showing.
function R:Toggle()
  local win = self.Window and self.Window:Get()
  if not win then return end
  if win:IsShown() then
    win:Hide()
  else
    self.Window:Open()
  end
end

Core:RegisterAddon("retrospect", {
  version = C_AddOns and C_AddOns.GetAddOnMetadata(R.addonName, "Version") or "0.9.0",
  open = function() R:Toggle() end,
})

-- other add-ons can ask "who has this" from their menus
Core:RegisterAction("retrospect.who", {
  addon = "retrospect", label = "Who has this", kinds = { "item", "quest" },
  run = function(kind, id)
    if kind == "item" then
      R.Window:ShowItem(id)
    else
      R.Window:ShowQuest(id)
    end
  end,
})

SLASH_RETROSPECT1 = "/retro"
SLASH_RETROSPECT2 = "/retrospect"
SlashCmdList["RETROSPECT"] = function(msg)
  msg = strtrim(msg or "")
  local lower = string.lower(msg)
  if lower == "" then
    R:Toggle()
  elseif lower == "settings" or lower == "options" then
    R:OpenSettings()
  elseif lower == "probe" then
    R.Probe:Report()
  else
    R.Window:Search(msg)   -- /retro arcanite: who has it
  end
end

-- the minimap button and the client's addon menu: click opens or closes, right-click the settings
local function onClick(button)
  if button == "RightButton" then R:OpenSettings() else R:Toggle() end
end
local function tooltip(tt)
  tt:AddLine("Retrospect", 1, .702, .361)
  tt:AddLine("What your other characters had when you last saw them", 1, 1, 1)
  tt:AddLine("Click: open or close  ·  Right-click: settings  ·  Drag: move", .43, .4, .32)
end
Core:OnLogin(function() Core.MinimapButton:Add("retrospect", { onClick = onClick, tooltip = tooltip }) end)
function Retrospect_OnAddonCompartmentClick(_, button) onClick(button) end
function Retrospect_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  tooltip(GameTooltip)
  GameTooltip:Show()
end
function Retrospect_OnAddonCompartmentLeave() GameTooltip:Hide() end

BINDING_HEADER_RETROSPECT = "Retrospect"
BINDING_NAME_RETROSPECT_TOGGLE = "Open or close Retrospect"
