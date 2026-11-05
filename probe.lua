-- /retro probe: what each reader actually got on this client. Blizzard's docs cover every game
-- flavour, so only the game can say which calls answer on Forever. Readers note their result as
-- they run (Scan.Note); this runs the ones that need no NPC again and prints them all. The same
-- table stays in RetrospectDB.probe, so a report can be read from the saved file.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end

local Probe = {}
R.Probe = Probe
local Scan = R.Scan

-- in the order they print; `visit` is what it takes for that reader to run at all
local AREAS = {
  { "Character" }, { "Gold" }, { "Rest" }, { "Played time" }, { "Gear" }, { "Bags" },
  { "Bank", visit = "open the bank" }, { "Account bank", visit = "open the bank" }, { "Guild bank", visit = "open the guild bank" },
  { "Professions" }, { "Recipes", visit = "open a profession" }, { "Cooldowns" }, { "Reputation" }, { "Quests" }, { "Lockouts" },
  { "Mail", visit = "open a mailbox" }, { "Auctions", visit = "open the auction house" },
}

-- calls a reader leans on, reported as present or missing whatever the reader got
local CALLS = {
  "C_Container.GetContainerItemInfo", "C_Bank.FetchPurchasedBankTabData", "C_Bank.FetchPurchasedBankTabIDs", "C_TradeSkillUI.GetAllRecipeIDs",
  "C_TradeSkillUI.GetFilteredRecipeIDs", "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.IsTradeSkillReady", "C_Reputation.GetFactionDataByIndex",
  "C_Reputation.ExpandFactionHeader", "C_Reputation.CollapseFactionHeader", "C_AuctionHouse.GetOwnedAuctionInfo", "C_AuctionHouse.QueryOwnedAuctions",
  "C_Spell.GetSpellCooldown", "GetInboxHeaderInfo", "GetSendMailItem", "GetSavedInstanceInfo", "RequestTimePlayed", "IsSpellKnown",
  "GetNumGuildBankTabs", "C_GuildBank.IsGuildBankEnabled", "C_SpecializationInfo.GetSpecialization", "TooltipDataProcessor.AddTooltipPostCall",
}

local function exists(path)
  local ns, name = path:match("^(.-)%.(.+)$")
  if not ns then return rawget(_G, path) ~= nil end
  local t = rawget(_G, ns)
  return type(t) == "table" and t[name] ~= nil
end

---The report as lines of text.
function Probe:Lines()
  Scan:Basics()
  Scan:Gear()
  Scan:Bags()
  Scan:QuestLog()
  Scan:Professions()
  Scan:Cooldowns()
  Scan:Lockouts()
  Scan:Reputation()

  local lines = {}
  local probe = R.db.probe
  for _, area in ipairs(AREAS) do
    local name = area[1]
    local got = probe[name]
    if got then
      lines[#lines + 1] = string.format("%s%s|r %s: %s", got.ok and "|cff8fe08f" or "|cffff9478", got.ok and "works" or "no data", name, tostring(got.detail or ""))
    else
      lines[#lines + 1] = string.format("|cffd9a066not run|r %s%s", name, area.visit and (": " .. area.visit .. " to check it") or "")
    end
  end
  local missing = {}
  for _, path in ipairs(CALLS) do
    if not exists(path) then missing[#missing + 1] = path end
  end
  lines[#lines + 1] = #missing == 0 and "Every call Retrospect leans on exists." or ("Missing calls: " .. table.concat(missing, ", "))
  probe.missing = missing
  probe.client = { build = (select(2, GetBuildInfo())), interface = (select(4, GetBuildInfo())) }
  return lines
end

function Probe:Report()
  R:Print("what each reader got on this client (saved in RetrospectDB.probe):")
  for _, line in ipairs(self:Lines()) do Core:Print(line, R.PREFIX) end
end
