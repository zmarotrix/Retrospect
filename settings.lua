-- Retrospect's settings page, under NorgannonDB in the game's Settings window (/retro settings).

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI

local Store = R.Store

StaticPopupDialogs["RETROSPECT_FORGET"] = {
  text = "Forget %s? Everything Retrospect remembers about this character goes, until it logs in again.",
  button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
  OnAccept = function(self, data)
    Store:Forget(data or self.data)
    if R.db.who == (data or self.data) then R.db.who = "all" end
    if R.Window then R.Window:Refresh() end
  end,
}

local forgetKey

local function forgetOptions()
  local options = {}
  for _, entry in ipairs(Store:List()) do
    if entry.key ~= Store:MyKey() then
      options[#options + 1] = { entry.key, tostring(entry.c.name) .. " (" .. tostring(entry.c.realm) .. ")" }
    end
  end
  if #options == 0 then options[1] = { "", "No other characters" } end
  return options
end

---Asks before forgetting a character, by its key.
function R:AskForget(key)
  local c = Store:Get(key)
  if not c or key == Store:MyKey() then return false end
  local dialog = StaticPopup_Show("RETROSPECT_FORGET", tostring(c.name))
  if dialog then dialog.data = key end
  return true
end

Core:OnLogin(function()
  if not R.db then return end
  local page = CreateFrame("Frame")
  page:Hide()
  local list = UI.SettingsList(page)

  list:Header("Window")
  list:Slider("Window size", nil, .6, 1.6, .05,
    function() return R.db.scale or 1 end,
    function(v) R.db.scale = v R.Window:ApplyLook() end, "%.0f%%", 100)
  list:Slider("Window opacity", nil, .4, 1, .05,
    function() return R.db.opacity or 1 end,
    function(v) R.db.opacity = v R.Window:ApplyLook() end, "%.0f%%", 100)
  list:Toggle("Lock the window", "Stops it from being moved.",
    function() return R.db.locked end,
    function(on) R.db.locked = on R.Window:ApplyLook() end)
  list:Buttons("Position", "Puts the window back in the middle of the screen.", { { "Reset position", function()
    if Core.db and Core.db.windows then Core.db.windows.RetrospectWindow = nil end
    local win = R.Window:Get()
    if win then
      win:ClearAllPoints()
      win:SetPoint("CENTER")
    end
  end } })
  list:Toggle("Show the minimap button", "Retrospect is also in the game's addon menu and opens with /retro.",
    function() return Core.MinimapButton:IsShown("retrospect") end,
    function(on) Core.MinimapButton:SetShown("retrospect", on) end)

  list:Header("Chat")
  list:Toggle("One line at login when something is urgent", "Only for what can't wait, such as mail about to expire. Never on /reload.",
    function() return R.db.loginLine end,
    function(on) R.db.loginLine = on end)

  list:Header("Tooltips")
  list:Toggle("Who holds an item", "How many your characters have, and where.",
    function() return R.db.tooltips end,
    function(on) R.db.tooltips = on end)
  list:Toggle("Who needs an item or knows a quest", "Who can learn a recipe, who needs an item for a quest, who has done a quest.",
    function() return R.db.tooltipNeeds end,
    function(on) R.db.tooltipNeeds = on end)

  list:Header("Characters")
  list:Dropdown("Forget a character", "For a character you deleted or don't want counted.", forgetOptions(),
    function() return forgetKey or forgetOptions()[1][1] end,
    function(v) forgetKey = v end)
  list:Buttons("", nil, { { "Forget this character", function()
    R:AskForget(forgetKey or forgetOptions()[1][1])
  end } })

  list:Header("Checking the client")
  list:Buttons("What each reader gets", "Prints what Retrospect can read on this client, the same as /retro probe.", { { "Check now", function()
    R.Probe:Report()
  end } })

  list:Header("Key binding")
  list:Buttons("Open or close Retrospect", "Set a key in the game's Key Bindings, under AddOns.", {})

  page:SetScript("OnShow", function() list:Refresh() end)
  R.settingsPage, R.settingsList = page, list
  R.settingsCategory = Core:AddSettingsPage(page, "Retrospect")

  -- Retrospect's hot paths for /norg perf (wrapped only while measuring)
  local function perf(label, tbl, method) Core:RegisterPerf("Retrospect: " .. label, tbl, method, "retrospect") end
  perf("bag scan", R.Scan, "Bags")
  perf("bank scan", R.Scan, "Bank")
  perf("reputation scan", R.Scan, "Reputation")
  perf("cooldown scan", R.Scan, "Cooldowns")
  perf("tooltip lines", R.Tips, "AddItem")
  perf("item search", R.Index, "Search")
  perf("today's list", R.Today, "Events")
  perf("window refresh", R.Window, "Refresh")
end)

function R:OpenSettings()
  if self.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(self.settingsCategory:GetID())
  else
    Core:OpenSettings()
  end
end
