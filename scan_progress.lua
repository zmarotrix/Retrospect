-- What a character has done and knows: quests, professions and recipes, reputations, raid lockouts
-- and profession cooldowns. The Core owns the quest log, skills and the recipe scan; this keeps a
-- copy of them per character.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end

local Scan, Store = R.Scan, R.Store
local Player = Core.Player

-------------------------------------------------------------------------------------------
-- Quests. The completed list is only packed on the way out: while logged in, the live set answers.
-------------------------------------------------------------------------------------------

function Scan:QuestLog()
  local c = Store:Me()
  local log = {}
  for _, id in ipairs(Player:QuestIds()) do
    local q = Player:GetQuest(id)
    local done, need, objectives = 0, 0, {}
    for i, o in ipairs(q.objectives or {}) do
      need = need + 1
      if o.finished then done = done + 1 end
      objectives[i] = { name = o.name, type = o.type, current = o.current, required = o.required }
    end
    log[#log + 1] = { id = id, title = q.title, level = q.level, complete = q.complete or nil, done = done, need = need, objectives = objectives }
  end
  c.quests = c.quests or {}
  c.quests.seen, c.quests.log = R.Now(), log
  Scan.Note("Quests", true, string.format("%d in the log, %d completed", #log, Store:QuestDoneCount(Store:MyKey()) or 0))
  R:Changed(Store:MyKey())
end

---Packs what is only kept live until logout: completed quests and known recipes.
function Scan:PackProgress()
  local c = Store:Me()
  if Player.ready then
    c.quests = c.quests or {}
    local packed, count = Store.PackIds(Player.completed)
    -- an empty list on a character that had some means the client never answered this session
    if count > 0 or not c.quests.done then
      c.quests.done, c.quests.doneCount = packed, count
    end
    c.quests.seen = R.Now()
    for skill, p in pairs(c.professions and c.professions.skills or {}) do
      local live = Player:KnownRecipes(skill)
      if live then p.recipes = Store.PackIds(live.ids) end
    end
  end
end

-------------------------------------------------------------------------------------------
-- Professions and recipes
-------------------------------------------------------------------------------------------

---Rank and cap by skill line, from the client's profession slots.
local function readCaps()
  local caps = {}
  local slots = { R.Global("GetProfessions") }
  for i = 1, 6 do
    if slots[i] then
      local name, _, rank, cap, _, _, skillLine = R.Global("GetProfessionInfo", slots[i])
      if skillLine then caps[skillLine] = { name = name, rank = rank, cap = cap } end
    end
  end
  return caps
end

function Scan:Professions()
  local c = Store:Me()
  local old = c.professions and c.professions.skills or {}
  local skills, caps = {}, readCaps()
  for skill, rank in pairs(Player.skills) do
    local before = old[skill] or {}
    local cap = caps[skill] or {}
    local live = Player:KnownRecipes(skill)
    skills[skill] = {
      rank = rank, max = cap.cap or before.max,
      name = cap.name or NorgannonDB:L("professions", skill, "name") or before.name,
      recipes = before.recipes,
      count = live and live.count or before.count,
      source = live and live.source or before.source,
      seen = live and live.seen or before.seen,
    }
  end
  c.professions = { seen = R.Now(), skills = skills }
  local n = 0
  for _ in pairs(skills) do n = n + 1 end
  Scan.Note("Professions", n > 0, n .. " professions")
  if n > 0 and not R.db.probe["Recipes"] then
    Scan.Note("Recipes", false, "IsSpellKnown found none; open a profession to read it")
  end
  R:Changed(Store:MyKey())
end

-- a window that opens and gives nothing is worth knowing about, for /retro probe
Core:On("TRADE_SKILL_SHOW", "retrospect.recipes", function()
  C_Timer.After(2, function()
    local probe = R.db.probe["Recipes"]
    if probe and not probe.ok then
      Scan.Note("Recipes", false, "a profession window opened but no recipes could be read")
    end
  end)
end)

Core:Listen("NORGANNON_SKILLS_CHANGED", "retrospect", function() Scan:Professions() end)
Core:Listen("NORGANNON_RECIPES_SCANNED", "retrospect", function(_, skill, count, source)
  Core:NextFrame(function()
    Scan:Professions()
    Scan:Cooldowns()
    Scan.Note("Recipes", count > 0, string.format("%s: %d recipes, read from the %s", tostring(skill), count, source == "window" and "profession window" or "spell list"))
  end, "retrospect.recipes")
end)

-------------------------------------------------------------------------------------------
-- Profession cooldowns: any known recipe the client says is cooling down for more than a couple
-- of minutes, so a new transmute or Forever's own recipes need no list here
-------------------------------------------------------------------------------------------

local LONG = 120
local FORGET_READY_AFTER = 14 * 86400

function Scan:Cooldowns()
  if not (rawget(_G, "C_Spell") and C_Spell.GetSpellCooldown) then
    Scan.Note("Cooldowns", false, "no C_Spell.GetSpellCooldown")
    return
  end
  local c = Store:Me()
  c.cooldowns = c.cooldowns or {}
  local now, clock, found = R.Now(), GetTime(), 0
  for _, rec in pairs(Player.recipes) do
    for id in pairs(rec.ids) do
      local info = R.In("C_Spell", "GetSpellCooldown", id)
      if type(info) == "table" and (info.duration or 0) > LONG and (info.startTime or 0) > 0 then
        c.cooldowns[id] = now + math.floor(info.startTime + info.duration - clock)
        found = found + 1
      end
    end
  end
  for id, ready in pairs(c.cooldowns) do
    if now - ready > FORGET_READY_AFTER then c.cooldowns[id] = nil end
  end
  Scan.Note("Cooldowns", true, found .. " cooling down")
  R:Changed(Store:MyKey())
end

Core:On("UNIT_SPELLCAST_SUCCEEDED", "retrospect.cooldowns", function(_, unit, _, spellId)
  if unit ~= "player" or Core.IsSecret(spellId) or not spellId then return end
  if Player:KnowsRecipe(spellId) then
    -- the cooldown starts just after the cast
    C_Timer.After(1, function() Scan:Cooldowns() end)
  end
end)

-------------------------------------------------------------------------------------------
-- Reputation. Collapsed headers hide their factions from the list, so they are opened for the read
-- and closed again in the same moment, unless the player has the reputation window open.
-------------------------------------------------------------------------------------------

local reading, queued = false, false
local ignoreUntil = 0   -- our own opening and closing of headers fires UPDATE_FACTION too

local function factionAt(i)
  local data = R.In("C_Reputation", "GetFactionDataByIndex", i)
  return type(data) == "table" and data or nil
end

local function reputationWindowOpen()
  local frame = rawget(_G, "ReputationFrame")
  return frame and frame.IsShown and frame:IsShown()
end

function Scan:Reputation()
  local total = R.In("C_Reputation", "GetNumFactions")
  if not total then
    Scan.Note("Reputation", false, "C_Reputation.GetNumFactions gave nothing")
    return
  end
  reading = true
  -- open from the bottom up: what appears below doesn't move the headers above
  local opened = {}
  if not reputationWindowOpen() and rawget(_G, "C_Reputation").ExpandFactionHeader then
    for i = total, 1, -1 do
      local data = factionAt(i)
      if data and data.isHeader and data.isCollapsed and data.factionID then
        opened[data.factionID] = true
        R.In("C_Reputation", "ExpandFactionHeader", i)
      end
    end
    total = R.In("C_Reputation", "GetNumFactions") or total
  end

  local c = Store:Me()
  -- on top of what's known: a faction hidden by a collapsed header while the window is open is still met
  local list, group, n = c.reputation and c.reputation.list or {}, nil, 0
  for i = 1, total do
    local data = factionAt(i)
    if data then
      if data.isHeader then group = data.name end
      if data.factionID and data.reaction and (not data.isHeader or data.isHeaderWithRep) then
        list[data.factionID] = {
          reaction = data.reaction, value = data.currentStanding,
          low = data.currentReactionThreshold, high = data.nextReactionThreshold,
        }
        R.db.factions[data.factionID] = { name = data.name, group = group }
        n = n + 1
      end
    end
  end

  -- put the list back as the player had it
  if next(opened) and rawget(_G, "C_Reputation").CollapseFactionHeader then
    for i = total, 1, -1 do
      local data = factionAt(i)
      if data and data.factionID and opened[data.factionID] then
        R.In("C_Reputation", "CollapseFactionHeader", i)
      end
    end
  end
  reading = false
  if next(opened) then ignoreUntil = GetTime() + 2 end
  if n > 0 then c.reputation = { seen = R.Now(), list = list } end
  Scan.Note("Reputation", n > 0, n .. " factions")
  R:Changed(Store:MyKey())
end

local function queueReputation()
  if reading or queued or GetTime() < ignoreUntil then return end
  queued = true
  C_Timer.After(1, function()
    queued = false
    Core:AfterCombat(function() Scan:Reputation() end, "retrospect.rep")
  end)
end
Core:On("UPDATE_FACTION", "retrospect.rep", queueReputation)

-------------------------------------------------------------------------------------------
-- Raid lockouts
-------------------------------------------------------------------------------------------

function Scan:Lockouts()
  local total = R.Global("GetNumSavedInstances")
  if not total then
    Scan.Note("Lockouts", false, "GetNumSavedInstances gave nothing")
    return
  end
  local c, now, list = Store:Me(), R.Now(), {}
  for i = 1, total do
    local name, _, reset, _, locked, extended, _, isRaid, _, _, encounters, progress = R.Global("GetSavedInstanceInfo", i)
    if name and (locked or extended) and (reset or 0) > 0 then
      list[#list + 1] = { name = name, reset = now + reset, killed = progress, total = encounters, raid = isRaid and true or nil }
    end
  end
  c.lockouts = { seen = now, list = list }
  Scan.Note("Lockouts", true, #list .. " saved")
  R:Changed(Store:MyKey())
end

Core:On("UPDATE_INSTANCE_INFO", "retrospect.lockouts", function()
  Core:NextFrame(function() Scan:Lockouts() end, "retrospect.lockouts")
end)

-------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------

Core:Listen("NORGANNON_QUESTLOG_UPDATED", "retrospect", function()
  Core:NextFrame(function() Scan:QuestLog() end, "retrospect.questlog")
end)
Core:Listen("NORGANNON_QUEST_TURNED_IN", "retrospect", function()
  Core:NextFrame(function() Scan:QuestLog() end, "retrospect.questlog")
end)

Core:OnLogin(function()
  if not R.db then return end
  Store:Me()
  Scan:QuestLog()
  Scan:Professions()
  Scan:Cooldowns()
  R.Global("RequestRaidInfo")
  queueReputation()
end)
