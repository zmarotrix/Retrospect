-- The characters, in RetrospectDB.chars["Realm-Name"]. A character's sections each carry their own
-- `seen` (when Retrospect last read them): a section that is missing was never read, which is not
-- the same as empty. Sections:
--
--   name, realm, class, race, faction, level, money, seen (last time on this character), zone, subzone,
--   guild, spec, ilvl, bind, played, xp, xpMax, rest, resting, goldDays = { [day] = copper }
--   bags, bank = { seen, slots, free, containers = { { id, size, free, name, items = packed } } }
--   gear = { seen, slots = { [slot] = packed entry } }
--   mail = { seen, list = { { from, subject, money, cod, expires, read, items = packed } } }
--   incoming = { { from, subject, money, arrives, items = packed } }   (mail your own alts sent)
--   auctions = { seen, list = { { item = packed, buyout, bid, expires, sold } }, bids = { same } }
--   quests = { seen, log = { { id, title, level, complete, done, need, objectives } }, done = packed ids, doneCount }
--   professions = { seen, skills = { [skillLine] = { rank, max, name, seen, source, count, recipes = packed ids } } }
--   reputation = { seen, list = { [factionId] = { reaction, value, low, high } } }
--   lockouts = { seen, list = { { name, reset, killed, total, raid } } }
--   cooldowns = { [spellId] = ready time }
--
-- Items are packed into one string per container ("id,count,quality,bound,itemstring;...", the item
-- string only when the item has an enchant or suffix), so a character costs a few kilobytes and the
-- saved file stays quick to load. Quest and recipe id lists are packed as base-36 differences.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end

local Store = {}
R.Store = Store

local chars
local sorted
local myKey
local unpacked = {}   -- packed id lists of other characters, once asked for

function Store:Loaded()
  chars = R.db.chars
end

---"Realm-Name" of the character logged in now.
function Store:MyKey()
  if not myKey then
    local realm = R.Global("GetRealmName") or "Realm"
    local name = R.Global("UnitName", "player") or "Unknown"
    myKey = realm .. "-" .. name
  end
  return myKey
end

---The record of the character logged in now, created the first time it is seen.
function Store:Me()
  local key = self:MyKey()
  local c = chars[key]
  if not c then
    c = { name = R.Global("UnitName", "player") or "Unknown", realm = R.Global("GetRealmName") or "Realm", goldDays = {} }
    chars[key] = c
    sorted = nil
  end
  return c
end

function Store:Get(key) return chars[key] end

---Every character as { key, c }: this realm first, then by realm; you, then higher levels first in each.
function Store:List()
  if sorted then return sorted end
  sorted = {}
  for key, c in pairs(chars) do sorted[#sorted + 1] = { key = key, c = c } end
  local here = chars[self:MyKey()] and chars[self:MyKey()].realm
  table.sort(sorted, function(a, b)
    local ar, br = a.c.realm == here, b.c.realm == here
    if ar ~= br then return ar end
    if a.c.realm ~= b.c.realm then return tostring(a.c.realm) < tostring(b.c.realm) end
    if a.key == myKey or b.key == myKey then return a.key == myKey end   -- who you're on, first
    if (a.c.level or 0) ~= (b.c.level or 0) then return (a.c.level or 0) > (b.c.level or 0) end
    return tostring(a.c.name) < tostring(b.c.name)
  end)
  return sorted
end

---Levels change sort order; called when this character's facts are read.
function Store:Resort() sorted = nil end

---Removes a character for good (Settings > Forget a character).
function Store:Forget(key)
  if key == self:MyKey() then return false end
  chars[key] = nil
  sorted = nil
  unpacked = {}
  R:Changed(key, true)
  return true
end

-------------------------------------------------------------------------------------------
-- Packed items
-------------------------------------------------------------------------------------------

local MEANINGFUL = "item:%d+:(%d*):%d*:%d*:%d*:%d*:(%-?%d*)"

---One packed entry. link is the item's hyperlink, when there is one; its item string is kept only
---when an enchant or suffix makes this copy different from the plain item.
function Store.Entry(id, count, quality, bound, link)
  local itemString = ""
  if type(link) == "string" then
    local enchant, suffix = link:match(MEANINGFUL)
    if (enchant and enchant ~= "" and enchant ~= "0") or (suffix and suffix ~= "" and suffix ~= "0") then
      itemString = link:match("(item:[%-%d:]+)") or ""
    end
    -- a name for items NorgannonDB doesn't have (Forever's own, say)
    if not Core.DB:Name("items", id) then
      local name = link:match("%[(.-)%]")
      if name and name ~= "" then R.db.names[id] = name end
    end
  end
  return string.format("%d,%d,%s,%s,%s", id, count or 1, quality and tostring(quality) or "", bound and "1" or "", itemString)
end

local ENTRY = "^(%d+),(%d+),(%d*),(%d*),?(.*)$"

---fn(id, count, quality, bound, itemString) for each item in a packed string.
function Store.EachItem(packed, fn)
  if not packed or packed == "" then return end
  for entry in packed:gmatch("[^;]+") do
    local id, count, q, bound, itemString = entry:match(ENTRY)
    if id then
      fn(tonumber(id), tonumber(count), tonumber(q), bound == "1", itemString ~= "" and itemString or nil)
    end
  end
end

---A packed string as a list of { id, count, q, bound, link }.
function Store.Items(packed)
  local out = {}
  Store.EachItem(packed, function(id, count, q, bound, link)
    out[#out + 1] = { id = id, count = count, q = q, bound = bound, link = link }
  end)
  return out
end

-------------------------------------------------------------------------------------------
-- Packed id lists: sorted, as base-36 differences
-------------------------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function base36(n)
  if n == 0 then return "0" end
  local out = {}
  while n > 0 do
    local d = n % 36
    out[#out + 1] = DIGITS:sub(d + 1, d + 1)
    n = math.floor(n / 36)
  end
  return string.reverse(table.concat(out))
end

---A set { [id] = true } as a compact string.
function Store.PackIds(set)
  local ids = {}
  for id in pairs(set) do ids[#ids + 1] = id end
  table.sort(ids)
  local out, last = {}, 0
  for i, id in ipairs(ids) do
    out[i] = base36(id - last)
    last = id
  end
  return table.concat(out, " "), #ids
end

---The compact string back as a set.
function Store.UnpackIds(packed)
  local set, last = {}, 0
  for piece in (packed or ""):gmatch("%S+") do
    last = last + tonumber(piece, 36)
    set[last] = true
  end
  return set
end

-------------------------------------------------------------------------------------------
-- Questions about a character. The one logged in answers from the live state; others unpack once.
-------------------------------------------------------------------------------------------

---A character's completed quests as a set. Returns nil if none were ever read.
local function doneSet(key)
  if key == Store:MyKey() and Core.Player.ready then return Core.Player.completed end
  local c = chars[key]
  local q = c and c.quests
  if not (q and q.done) then return nil end
  local set = unpacked[key]
  if not set then
    set = Store.UnpackIds(q.done)
    unpacked[key] = set
  end
  return set
end

---true / false, or nil when that character's quests were never read.
function Store:QuestDone(key, id)
  local set = doneSet(key)
  if not set then return nil end
  return set[id] == true
end

function Store:QuestDoneCount(key)
  if key == self:MyKey() and Core.Player.ready then
    local n = 0
    for _ in pairs(Core.Player.completed) do n = n + 1 end
    return n
  end
  local q = chars[key] and chars[key].quests
  return q and q.doneCount
end

---The quest-log entry for a quest on a character, or nil.
function Store:QuestInLog(key, id)
  local q = chars[key] and chars[key].quests
  for _, entry in ipairs(q and q.log or {}) do
    if entry.id == id then return entry end
  end
end

---The set of recipes a character knows in a profession, and the profession's record; nil set = not read.
function Store:Recipes(key, skill)
  local c = chars[key]
  local p = c and c.professions and c.professions.skills and c.professions.skills[skill]
  if not p then return nil end
  if key == self:MyKey() then
    local live = Core.Player:KnownRecipes(skill)
    if live then return live.ids, p end
  end
  if not p.recipes then return nil, p end
  local cacheKey = key .. "#" .. skill
  local set = unpacked[cacheKey]
  if not set then
    set = Store.UnpackIds(p.recipes)
    unpacked[cacheKey] = set
  end
  return set, p
end

---Which of your characters know a recipe, from the record of the profession that teaches it.
function Store:Knows(key, spellId, skill)
  local set = self:Recipes(key, skill)
  if not set then return nil end
  return set[spellId] == true
end

-------------------------------------------------------------------------------------------
-- Rest: what it was when last seen, carried forward. The game gives 5% of a level per 8 hours at an
-- inn and a quarter of that outside, up to 150%; for an offline character this is an estimate.
-------------------------------------------------------------------------------------------

local EIGHT_HOURS = 8 * 3600

---Rested share of a level (0 to 1.5) and whether it is an estimate; nil at the level cap or when unread.
function Store:Rest(key)
  local c = chars[key]
  if not (c and c.xpMax and c.xpMax > 0) then return nil end
  if (c.level or 0) >= (R.Global("GetMaxPlayerLevel") or 60) then return nil end
  local base = (c.rest or 0) / c.xpMax
  if key == self:MyKey() then return math.min(1.5, base), false end
  local elapsed = math.max(0, R.Now() - (c.seen or R.Now()))
  local rate = c.resting and .05 or .0125
  return math.min(1.5, base + elapsed / EIGHT_HOURS * rate), elapsed > 0
end

-------------------------------------------------------------------------------------------
-- Names and qualities
-------------------------------------------------------------------------------------------

---An item's name: the client's language through NorgannonDB, what a link told us, the client, else "Item #id".
function Store:ItemName(id)
  local name = Core.DB:Name("items", id) or R.db.names[id]
  if name then return name end
  name = R.In("C_Item", "GetItemNameByID", id)
  if name then return name end
  R.In("C_Item", "RequestLoadItemDataByID", id)
  return "Item #" .. id
end

---An item's quality: what a scan saw, else what the client knows, else nil.
function Store:ItemQuality(id, seen)
  return seen or R.In("C_Item", "GetItemQualityByID", id)
end

-- a late item name or quality redraws what is on screen
Core:On("ITEM_DATA_LOAD_RESULT", "retrospect.items", function()
  if R.Window then R.Window:RefreshSoon() end
end)

-- a guild's key, for the shared holdings
function Store:GuildKey(c)
  return c.guild and ((c.realm or "") .. "-" .. c.guild) or nil
end
