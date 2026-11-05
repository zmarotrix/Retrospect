-- This character's own facts: level, gold (one value per day, kept for a year), played time, rest,
-- where it is, its gear. Each reader notes what it got for /retro probe.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end

local Scan = {}
R.Scan = Scan
local Store = R.Store

local KEEP_DAYS = 400

---Records what a reader got, for /retro probe: area, whether it worked, a short detail.
function Scan.Note(area, ok, detail)
  if not (R.db and R.db.probe) then return end
  R.db.probe[area] = { ok = ok and true or false, detail = detail, at = R.Now() }
end

local function today() return math.floor(R.Now() / 86400) end
Scan.Today = today

---Today's gold for this character; old days fall off after a year or so.
local function recordGold(c)
  if not c.money then return end
  c.goldDays = c.goldDays or {}
  c.goldDays[today()] = c.money
end

local function pruneGold(c)
  local oldest = today() - KEEP_DAYS
  for day in pairs(c.goldDays or {}) do
    if day < oldest then c.goldDays[day] = nil end
  end
end

function Scan:Money()
  local c = Store:Me()
  local money = R.Global("GetMoney")
  if money then
    c.money = money
    recordGold(c)
    Scan.Note("Gold", true, tostring(money) .. " copper")
  else
    Scan.Note("Gold", false, "GetMoney gave nothing")
  end
  R:Changed(Store:MyKey())
end

function Scan:Rest()
  local c = Store:Me()
  c.xp = R.Global("UnitXP", "player") or c.xp
  c.xpMax = R.Global("UnitXPMax", "player") or c.xpMax
  c.rest = R.Global("GetXPExhaustion") or 0
  c.resting = R.Global("IsResting") and true or false
  Scan.Note("Rest", c.xpMax ~= nil, c.xpMax and string.format("%d rested of %d", c.rest, c.xpMax) or "UnitXPMax gave nothing")
end

function Scan:Where()
  local c = Store:Me()
  c.zone = R.Global("GetRealZoneText") or c.zone
  c.subzone = R.Global("GetSubZoneText") or c.subzone
  c.seen = R.Now()
  R:Changed(Store:MyKey())
end

local function readSpec(c)
  local index = R.In("C_SpecializationInfo", "GetSpecialization")
  if not index then return end
  local _, name = R.In("C_SpecializationInfo", "GetSpecializationInfo", index)
  c.spec = name or c.spec
  return name ~= nil
end

function Scan:Basics()
  local c = Store:Me()
  c.name = R.Global("UnitName", "player") or c.name
  c.realm = R.Global("GetRealmName") or c.realm
  local _, class = R.Global("UnitClass", "player")
  local race = R.Global("UnitRace", "player")
  c.class, c.race = class or c.class, race or c.race
  c.faction = R.Global("UnitFactionGroup", "player") or c.faction
  local level = R.Global("UnitLevel", "player")
  if level and level ~= c.level then
    c.level = level
    Store:Resort()
  end
  c.guild = (R.Global("GetGuildInfo", "player")) or nil
  local _, equipped = R.Global("GetAverageItemLevel")
  c.ilvl = equipped or c.ilvl
  c.bind = R.Global("GetBindLocation") or c.bind
  local spec = readSpec(c)
  Scan.Note("Character", c.class ~= nil and c.level ~= nil, string.format("level %s %s%s", tostring(c.level), tostring(c.class),
    spec and (", spec " .. tostring(c.spec)) or ", no spec name"))
  self:Rest()
  self:Where()
  self:Money()
  pruneGold(c)
end

-------------------------------------------------------------------------------------------
-- Gear
-------------------------------------------------------------------------------------------

local LAST_SLOT = 19

function Scan:Gear(changed)
  local c = Store:Me()
  local slots, n = {}, 0
  for slot = 1, LAST_SLOT do
    local link = R.Global("GetInventoryItemLink", "player", slot)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
      slots[slot] = Store.Entry(id, 1, R.In("C_Item", "GetItemQualityByID", link), true, link)
      n = n + 1
    end
  end
  Scan.Note("Gear", n > 0, n .. " pieces")
  -- nothing at all at login means the client isn't ready yet, not a naked character
  if n > 0 or changed or not c.gear then
    c.gear = { seen = R.Now(), slots = slots }
    R:Changed(Store:MyKey(), true)
  end
end

-------------------------------------------------------------------------------------------
-- Played time. /played prints two chat lines the player didn't ask for, so the chat frames sit this
-- one reply out; if the reply never comes they listen again after a few seconds.
-------------------------------------------------------------------------------------------

local quieted

local function restoreChat()
  if not quieted then return end
  for _, frame in ipairs(quieted) do frame:RegisterEvent("TIME_PLAYED_MSG") end
  quieted = nil
end

local function requestPlayed()
  if not rawget(_G, "RequestTimePlayed") then
    Scan.Note("Played time", false, "no RequestTimePlayed")
    return
  end
  quieted = {}
  for i = 1, rawget(_G, "NUM_CHAT_WINDOWS") or 10 do
    local frame = rawget(_G, "ChatFrame" .. i)
    if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
      frame:UnregisterEvent("TIME_PLAYED_MSG")
      quieted[#quieted + 1] = frame
    end
  end
  R.Global("RequestTimePlayed")
  C_Timer.After(5, restoreChat)
end
Scan.RequestPlayed = requestPlayed

Core:On("TIME_PLAYED_MSG", "retrospect.played", function(_, total)
  if total and not Core.IsSecret(total) then
    Store:Me().played = total
    Scan.Note("Played time", true, total .. " seconds")
    R:Changed(Store:MyKey())
  end
  Core:NextFrame(restoreChat, "retrospect.played")
end)

-------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------

Core:OnLogin(function()
  if not R.db then return end
  Scan:Basics()
  Scan:Gear()
  C_Timer.After(8, requestPlayed)
end)

Core:On("PLAYER_MONEY", "retrospect.char", function() Scan:Money() end)
Core:On("PLAYER_UPDATE_RESTING", "retrospect.char", function() Scan:Rest() end)
Core:On("PLAYER_XP_UPDATE", "retrospect.char", function() Scan:Rest() end)
Core:On("UPDATE_EXHAUSTION", "retrospect.char", function() Scan:Rest() end)
Core:On("PLAYER_LEVEL_UP", "retrospect.char", function() Core:NextFrame(function() Scan:Basics() end, "retrospect.basics") end)
Core:On("PLAYER_GUILD_UPDATE", "retrospect.char", function() Core:NextFrame(function() Scan:Basics() end, "retrospect.basics") end)
Core:On("ZONE_CHANGED_NEW_AREA", "retrospect.char", function() Scan:Where() end)
Core:On("PLAYER_EQUIPMENT_CHANGED", "retrospect.char", function()
  Core:NextFrame(function() Core:AfterCombat(function() Scan:Gear(true) end, "retrospect.gear") end, "retrospect.gear")
end)
Core:On("PLAYER_ENTERING_WORLD", "retrospect.char", function()
  Scan:Gear()
  Core:Off("PLAYER_ENTERING_WORLD", "retrospect.char")
end)

-- leaving: when you were last on this character, and everything that is only packed on the way out
Core:On("PLAYER_LOGOUT", "retrospect.char", function()
  if not R.db then return end
  Scan:Rest()
  Scan:Where()
  if R.Scan.PackProgress then R.Scan:PackProgress() end
end)
