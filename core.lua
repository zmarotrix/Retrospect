-- Retrospect: what your other characters had when you last saw them. Account-wide alt tracking
-- for WoW Forever, built on NorgannonDB and NorgannonDB_Core.
-- Plan: docs/retrospect-v1.md in the suite workspace; the look: design/suite/retrospect.html.

local ADDON = ...
local Core = NorgannonCore

if not (Core and Core.NewAddon) then
  Retrospect = { disabled = true }
  print("Retrospect needs NorgannonDB Core 1.20 or newer; it is turned off.")
  return
end

Retrospect = {}
local R = Retrospect

-------------------------------------------------------------------------------------------
-- Saved data (account-wide; store.lua holds the characters)
-------------------------------------------------------------------------------------------

R.DEFAULTS = {
  who = "all",           -- the rail's selection: "all" or a character's key
  tab = "today",
  cmp = "rep",           -- Compare's mode
  goldRange = 30,        -- days on the gold chart
  bagView = "type",      -- Bags & Bank: "type" or "bag"
  bagFilter = "all",     -- Bags & Bank: a kind of item
  repView = "group",     -- Reputation: "group" or "standing"
  profFilter = "all",    -- Professions: "all", "known" or "unknown"
  scale = 1,
  opacity = 1,
  locked = false,
  tooltips = true,       -- who holds an item, in item tooltips
  tooltipNeeds = true,   -- who can learn a recipe or needs an item for a quest, in tooltips
  loginLine = true,      -- one quiet chat line at login when something is urgent
  chars = {},            -- ["Realm-Name"] = a character (store.lua)
  guilds = {},           -- ["Realm-Guild"] = a guild bank
  names = {},            -- item names NorgannonDB doesn't have
  factions = {},         -- faction id = { name, group }
  probe = {},            -- what each reader last got (probe.lua)
}

-- The suite's plumbing (Core:NewAddon): version checks, RetrospectDB with its defaults, the slash command, the minimap
-- row and the add-on menu. Left-click and /retro open the window; right-click opens settings; /retro <item> searches.
Core:NewAddon("retrospect", {
  folder = ADDON, api = { 1, 20 }, data = { 1, 4 },
  db = "RetrospectDB", defaults = R.DEFAULTS,
  slash = { "/retro", "/retrospect" },
  commands = { probe = { function() R.Probe:Report() end, "what Retrospect can read on this client" } },
  onUnknown = function(msg) R.Window:Search(msg) end,   -- /retro arcanite: who has it
})
if R.disabled then return end
R:OnReady(function() R.Store:Loaded() end)

-------------------------------------------------------------------------------------------
-- Calling the client: Core's helpers. Docs list calls for every game flavour, so any of them may be missing or refuse
-- on Forever: nothing here assumes one works, and a secret value counts as no answer.
-------------------------------------------------------------------------------------------

R.Try, R.Global, R.In, R.Now = Core.Plain, Core.Global, Core.In, Core.Now

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

BINDING_HEADER_RETROSPECT = "Retrospect"
BINDING_NAME_RETROSPECT_TOGGLE = "Open or close Retrospect"
