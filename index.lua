-- Who holds what. One small table per holder (a character, the account bank, a guild bank), built
-- from its packed items the first time anyone asks and again only when that holder changes, so a
-- tooltip costs a lookup per holder. The holders of other characters never change in a session.
-- After login they are built one per frame, so the first tooltip doesn't pay for all of them.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end

local Index = {}
R.Index = Index
local Store = R.Store

Index.PLACES = {
  { key = "bags", label = "Bags" }, { key = "bank", label = "Bank" }, { key = "mail", label = "In the mail" },
  { key = "auction", label = "Auction" }, { key = "gear", label = "Equipped" },
}
Index.PLACE_LABEL = { bags = "Bags", bank = "Bank", mail = "In the mail", auction = "Auction", gear = "Equipped", guild = "Guild bank", account = "Account bank" }

local maps = {}        -- holder key -> { [itemId] = { total, free, places = { [place] = n }, link } }
local qualities = {}   -- itemId -> quality, as scans saw it
local lowerNames = {}  -- itemId -> lower-case name, for search

local function add(map, place, id, count, q, bound, link)
  local e = map[id]
  if not e then
    e = { total = 0, free = 0, places = {} }
    map[id] = e
  end
  e.total = e.total + count
  e.places[place] = (e.places[place] or 0) + count
  if not bound and place ~= "gear" then e.free = e.free + count end
  if link then e.link = link end
  if q then qualities[id] = q end
end

local function addPacked(map, place, packed)
  Store.EachItem(packed, function(id, count, q, bound, link) add(map, place, id, count, q, bound, link) end)
end

local function addSection(map, place, section)
  for _, box in ipairs(section and section.containers or {}) do addPacked(map, place, box.items) end
end

local function buildCharacter(c)
  local map = {}
  addSection(map, "bags", c.bags)
  addSection(map, "bank", c.bank)
  for _, entry in pairs(c.gear and c.gear.slots or {}) do addPacked(map, "gear", entry) end
  for _, m in ipairs(c.mail and c.mail.list or {}) do addPacked(map, "mail", m.items) end
  for _, m in ipairs(c.incoming or {}) do addPacked(map, "mail", m.items) end
  for _, a in ipairs(c.auctions and c.auctions.list or {}) do
    if not a.sold then addPacked(map, "auction", a.item) end
  end
  return map
end

local function build(key)
  if key == "account" then
    local map = {}
    addSection(map, "account", R.db.accountBank)
    return map
  end
  local guild = key:match("^guild:(.+)$")
  if guild then
    local map = {}
    local record = R.db.guilds[guild]
    for _, tab in ipairs(record and record.tabs or {}) do addPacked(map, "guild", tab.items) end
    return map
  end
  local c = Store:Get(key)
  return c and buildCharacter(c) or {}
end

local function mapOf(key)
  local map = maps[key]
  if not map then
    map = build(key)
    maps[key] = map
  end
  return map
end

function Index:Invalidate(key)
  if key then maps[key] = nil else maps = {} end
end

---Everything that can hold items: { key, label, c (a character) or nil }.
function Index:Holders()
  local out = {}
  for _, entry in ipairs(Store:List()) do out[#out + 1] = { key = entry.key, c = entry.c, label = entry.c.name } end
  if R.db.accountBank then out[#out + 1] = { key = "account", label = "Account bank", seen = R.db.accountBank.seen } end
  for key, record in pairs(R.db.guilds) do
    out[#out + 1] = { key = "guild:" .. key, label = "<" .. tostring(record.name) .. ">", seen = record.seen }
  end
  return out
end

---What one holder has of an item, or nil.
function Index:Of(key, id) return mapOf(key)[id] end

---Who holds an item: { { holder, e }, ... }, most first, and the total.
function Index:Holdings(id, scopeKey)
  local out, total = {}, 0
  for _, holder in ipairs(self:Holders()) do
    if not scopeKey or holder.key == scopeKey then
      local e = mapOf(holder.key)[id]
      if e then
        out[#out + 1] = { holder = holder, e = e }
        total = total + e.total
      end
    end
  end
  table.sort(out, function(a, b)
    if a.e.total ~= b.e.total then return a.e.total > b.e.total end
    return a.holder.label < b.holder.label
  end)
  return out, total
end

---The best quality seen for an item.
function Index:Quality(id) return Store:ItemQuality(id, qualities[id]) end

local function lowerName(id)
  local name = lowerNames[id]
  if not name or name:find("^item #") then
    name = string.lower(Store:ItemName(id))
    lowerNames[id] = name
  end
  return name
end

---Items matching a search: { { id, name, q, total, free, holders = { labels } } }.
---opts = { query, scope (a holder key), hidePlaces = { [place] = true }, mailable = true }.
function Index:Search(opts)
  local query = string.lower(strtrim(opts.query or ""))
  local hide, rows, byId = opts.hidePlaces or {}, {}, {}
  for _, holder in ipairs(self:Holders()) do
    if not opts.scope or holder.key == opts.scope then
      for id, e in pairs(mapOf(holder.key)) do
        local name = (query == "" or lowerName(id):find(query, 1, true)) and true or false
        if name then
          local count = 0
          for place, n in pairs(e.places) do
            if not hide[place] then count = count + n end
          end
          if count > 0 then
            local row = byId[id]
            if not row then
              row = { id = id, total = 0, free = 0, holders = {} }
              byId[id] = row
              rows[#rows + 1] = row
            end
            row.total = row.total + count
            row.free = row.free + e.free
            row.holders[#row.holders + 1] = holder.label
          end
        end
      end
    end
  end
  local out = {}
  for _, row in ipairs(rows) do
    if not opts.mailable or row.free > 0 then
      row.name = Store:ItemName(row.id)
      row.q = self:Quality(row.id)
      row.lower = lowerName(row.id)
      out[#out + 1] = row
    end
  end
  -- what starts with the search first, then by name
  table.sort(out, function(a, b)
    if query ~= "" then
      local ap, bp = a.lower:sub(1, #query) == query, b.lower:sub(1, #query) == query
      if ap ~= bp then return ap end
    end
    return a.lower < b.lower
  end)
  return out
end

-- after login: one holder per frame
local function warm()
  local list = Index:Holders()
  local i = 0
  local function step()
    i = i + 1
    local holder = list[i]
    if not holder then return end
    mapOf(holder.key)
    C_Timer.After(0, step)
  end
  step()
end

Core:OnLogin(function()
  if R.db then C_Timer.After(2, warm) end
end)
