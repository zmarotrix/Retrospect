-- Today's list: real deadlines worked out from what each character was last seen with, and the one
-- quiet chat line at login when something can't wait. Facts only, never "do this next".
--
-- An event is { kind = "urgent" | "ready" | "soon" | "info", icon, who (character key), title, sub, when, at }.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end

local Today = {}
R.Today = Today
local Store = R.Store

local DAY, HOUR = 86400, 3600
local MAIL_URGENT = 3 * DAY     -- mail about to expire: on the "Act soon" part of the list
local MAIL_SOON = 7 * DAY
local COOLDOWN_SOON = 3 * DAY
local LOCKOUT_SOON = 2 * DAY
local AUCTION_SOON = 12 * HOUR
local BAGS_NEARLY_FULL = 2      -- free slots

local ICONS = {
  mail = "Interface\\Icons\\INV_Letter_15", auction = "Interface\\Icons\\INV_Misc_Coin_01",
  cooldown = "Interface\\Icons\\INV_Misc_PocketWatch_01", lockout = "Interface\\Icons\\INV_Misc_Key_03",
  rest = "Interface\\Icons\\Spell_Nature_Sleep", bags = "Interface\\Icons\\INV_Misc_Bag_08",
}
Today.ICONS = ICONS

-------------------------------------------------------------------------------------------
-- Time in words (also the kit's)
-------------------------------------------------------------------------------------------

---"2d 4h", "14h", "40m", "under a minute".
function Today.Span(seconds)
  seconds = math.max(0, math.floor(seconds))
  if seconds >= DAY then
    local d, h = math.floor(seconds / DAY), math.floor((seconds % DAY) / HOUR)
    return h > 0 and d < 10 and string.format("%dd %dh", d, h) or string.format("%dd", d)
  end
  if seconds >= HOUR then return string.format("%dh", math.floor(seconds / HOUR)) end
  if seconds >= 60 then return string.format("%dm", math.floor(seconds / 60)) end
  return "under a minute"
end

---"now", "6h ago", "23d ago"; "never" without a time.
function Today.Ago(at)
  if not at then return "never" end
  local seconds = R.Now() - at
  if seconds < 90 then return "now" end
  return Today.Span(seconds) .. " ago"
end

---Gold in plain text for sentences: "12g 40s", "41g", "60s".
function Today.Coins(copper)
  copper = copper or 0
  local g, s = math.floor(copper / 10000), math.floor((copper % 10000) / 100)
  if g > 0 and s > 0 then return string.format("%dg %ds", g, s) end
  if g > 0 then return g .. "g" end
  return s .. "s"
end

-------------------------------------------------------------------------------------------
-- Building the list
-------------------------------------------------------------------------------------------

---"20 Runecloth" or "20 Runecloth and 2 more kinds" from packed attachments.
local function whatIn(mails)
  local kinds, first = {}, nil
  for _, m in ipairs(mails) do
    Store.EachItem(m.items, function(id, count)
      kinds[id] = (kinds[id] or 0) + count
      first = first or id
    end)
  end
  if not first then return nil end
  local more = -1
  for _ in pairs(kinds) do more = more + 1 end
  local text = kinds[first] .. " " .. Store:ItemName(first)
  if more > 0 then text = text .. " and " .. more .. (more == 1 and " more kind" or " more kinds") end
  return text
end

local function plural(n, one, many) return n == 1 and ("1 " .. one) or (n .. " " .. (many or one .. "s")) end

local function mailEvents(events, key, c, now)
  local mail = c.mail
  if not mail then return end
  local urgent, soon, gone, money = {}, {}, {}, 0
  local soonest
  for _, m in ipairs(mail.list or {}) do
    if m.money then money = money + m.money end
    local left = (m.expires or now) - now
    if left <= 0 then
      gone[#gone + 1] = m
    elseif left <= MAIL_URGENT then
      urgent[#urgent + 1] = m
      soonest = math.min(soonest or left, left)
    elseif left <= MAIL_SOON then
      soon[#soon + 1] = m
    end
  end
  local function sub(list)
    local total = 0
    for _, m in ipairs(list) do total = total + (m.money or 0) end
    local parts = {}
    local items = whatIn(list)
    if items then parts[#parts + 1] = items end
    if total > 0 then parts[#parts + 1] = Today.Coins(total) end
    return #parts > 0 and table.concat(parts, " and ") or nil
  end
  if #gone > 0 then
    local what = sub(gone)
    -- too late to act on, so it never counts as urgent
    events[#events + 1] = { kind = "info", icon = ICONS.mail, who = key, at = now - DAY,
      title = plural(#gone, "mail") .. " may have expired since you last looked",
      sub = (what and ("With " .. what .. ". ") or "") .. "Last seen " .. Today.Ago(mail.seen), when = "by now" }
  end
  if #urgent > 0 then
    local what = sub(urgent)
    events[#events + 1] = { kind = "urgent", icon = ICONS.mail, who = key, at = now + soonest,
      title = plural(#urgent, "mail") .. (#urgent == 1 and " expires" or " expire") .. (what and (", with " .. what) or ""),
      sub = "What's in a mail is returned or lost when it expires", when = Today.Span(soonest) }
  end
  if #soon > 0 then
    events[#events + 1] = { kind = "soon", icon = ICONS.mail, who = key, at = now + MAIL_SOON,
      title = plural(#soon, "mail") .. " will expire this week", sub = sub(soon) or "Letters without anything attached", when = "within 7d" }
  end
  if money > 0 then
    events[#events + 1] = { kind = "ready", icon = ICONS.auction, who = key, at = now,
      title = Today.Coins(money) .. " waiting in the mail", sub = "Seen " .. Today.Ago(mail.seen), when = "in the mailbox" }
  end
end

local function auctionEvents(events, key, c, now)
  local auctions = c.auctions
  if not auctions then return end
  local sold, money, names, ended, ending = 0, 0, {}, 0, 0
  local soonest
  for _, a in ipairs(auctions.list or {}) do
    if a.sold then
      sold = sold + 1
      money = money + (a.bid or a.buyout or 0)
      Store.EachItem(a.item, function(id, count) names[#names + 1] = Store:ItemName(id) .. " x " .. count end)
    elseif (a.expires or now) <= now then
      ended = ended + 1
    elseif a.expires - now <= AUCTION_SOON then
      ending = ending + 1
      soonest = math.min(soonest or (a.expires - now), a.expires - now)
    end
  end
  if sold > 0 then
    events[#events + 1] = { kind = "ready", icon = ICONS.auction, who = key, at = now,
      title = plural(sold, "auction") .. " sold" .. (money > 0 and (": " .. Today.Coins(money)) or ""),
      sub = table.concat(names, ", "), when = "Seen " .. Today.Ago(auctions.seen) }
  end
  if ended > 0 then
    events[#events + 1] = { kind = "soon", icon = ICONS.auction, who = key, at = now,
      title = plural(ended, "auction") .. " ended since you last looked", sub = "Sold or back in the mail. Seen " .. Today.Ago(auctions.seen), when = "by now" }
  end
  if ending > 0 then
    events[#events + 1] = { kind = "soon", icon = ICONS.auction, who = key, at = now + soonest,
      title = plural(ending, "auction") .. (ending == 1 and " ends" or " end") .. " soon", sub = "Unsold when last seen", when = "in " .. Today.Span(soonest) }
  end
end

local function cooldownEvents(events, key, c, now)
  -- one row per ready time: transmutes share a cooldown
  local byTime = {}
  for id, ready in pairs(c.cooldowns or {}) do
    local at = ready <= now and 0 or ready
    byTime[at] = byTime[at] or {}
    table.insert(byTime[at], id)
  end
  for at, ids in pairs(byTime) do
    table.sort(ids)
    local name = Core.DB:RecipeName(ids[1]) or ("Spell " .. ids[1])
    if #ids > 1 then name = name .. " and " .. (#ids - 1) .. " more" end
    local record = Core.DB:Recipe(ids[1])
    local skill = record and record.skill and NorgannonDB:L("professions", record.skill, "name") or nil
    if at == 0 then
      events[#events + 1] = { kind = "ready", icon = ICONS.cooldown, who = key, at = now, title = name .. " is off cooldown", sub = skill, when = "ready now" }
    elseif at - now <= COOLDOWN_SOON then
      events[#events + 1] = { kind = "soon", icon = ICONS.cooldown, who = key, at = at, title = name .. " comes off cooldown", sub = skill, when = "in " .. Today.Span(at - now) }
    end
  end
end

local function lockoutEvents(events, key, c, now)
  for _, l in ipairs(c.lockouts and c.lockouts.list or {}) do
    if l.reset > now and l.reset - now <= LOCKOUT_SOON then
      local killed = l.total and l.total > 0 and string.format("%d of %d bosses killed", l.killed or 0, l.total) or nil
      events[#events + 1] = { kind = "soon", icon = ICONS.lockout, who = key, at = l.reset, title = l.name .. " lockout ends", sub = killed, when = "in " .. Today.Span(l.reset - now) }
    end
  end
end

local function characterEvents(events, key, c)
  local rest, estimate = Store:Rest(key)
  if rest and rest >= 1.5 then
    events[#events + 1] = { kind = "info", icon = ICONS.rest, who = key, at = R.Now() + DAY * 30, title = "Fully rested, 150% of a level",
      sub = estimate and "An estimate, from when you last logged out" or nil, when = "now" }
  end
  local bags = c.bags
  if bags and bags.slots > 0 and bags.free <= BAGS_NEARLY_FULL then
    events[#events + 1] = { kind = "info", icon = ICONS.bags, who = key, at = R.Now() + DAY * 30, title = "Bags nearly full",
      sub = string.format("%d of %d slots free", bags.free, bags.slots), when = Today.Ago(bags.seen) }
  end
end

local cached
local RANK = { urgent = 1, ready = 2, soon = 3, info = 4 }

---Every event: most pressing kind first, soonest first within a kind.
function Today:Events()
  if cached then return cached end
  local events, now = {}, R.Now()
  for _, entry in ipairs(Store:List()) do
    mailEvents(events, entry.key, entry.c, now)
    auctionEvents(events, entry.key, entry.c, now)
    cooldownEvents(events, entry.key, entry.c, now)
    lockoutEvents(events, entry.key, entry.c, now)
    characterEvents(events, entry.key, entry.c)
  end
  table.sort(events, function(a, b)
    if RANK[a.kind] ~= RANK[b.kind] then return RANK[a.kind] < RANK[b.kind] end
    if a.at ~= b.at then return a.at < b.at end
    return a.title < b.title
  end)
  cached = events
  return events
end

function Today:Invalidate() cached = nil end

---The events of one character.
function Today:For(key)
  local out = {}
  for _, e in ipairs(self:Events()) do
    if e.who == key then out[#out + 1] = e end
  end
  return out
end

-- the list goes stale by itself as time passes
C_Timer.NewTicker(60, function() Today:Invalidate() end)

-------------------------------------------------------------------------------------------
-- What Retrospect hasn't seen: totals are short by whatever is listed here
-------------------------------------------------------------------------------------------

local OLD = 14 * DAY
local LONG_GONE = 30 * DAY

---{ { who, what, state } }: banks never opened or old, characters gone a long time, recipes never read.
function Today:Unseen()
  local out, now = {}, R.Now()
  for _, entry in ipairs(Store:List()) do
    local key, c = entry.key, entry.c
    if c.seen and now - c.seen > LONG_GONE then
      out[#out + 1] = { who = key, what = "everything", state = Today.Ago(c.seen) }
    else
      if not c.bank then
        out[#out + 1] = { who = key, what = "bank", state = "never opened" }
      elseif now - c.bank.seen > OLD then
        out[#out + 1] = { who = key, what = "bank", state = Today.Ago(c.bank.seen) }
      end
      for _, p in pairs(c.professions and c.professions.skills or {}) do
        if not p.count and not p.recipes then
          out[#out + 1] = { who = key, what = "recipes", state = tostring(p.name) .. " not opened" }
        end
      end
    end
  end
  return out
end

-------------------------------------------------------------------------------------------
-- One quiet line at login, only when something is urgent: never on /reload, never twice
-------------------------------------------------------------------------------------------

---The login line for what's urgent, or nil when nothing is.
function Today:LoginLine()
  local urgent = {}
  for _, e in ipairs(self:Events()) do
    if e.kind == "urgent" then urgent[#urgent + 1] = e end
  end
  local first = urgent[1]
  if not first then return nil end
  local c = Store:Get(first.who)
  local line = string.format("%s: %s (%s).", c and c.name or "?", first.title, first.when)
  if #urgent > 1 then line = line .. string.format(" %d more %s urgent.", #urgent - 1, #urgent == 2 and "thing is" or "things are") end
  return line .. " /retro"
end

local said = false
Core:On("PLAYER_ENTERING_WORLD", "retrospect.login", function(_, isLogin)
  if said or not isLogin or Core.IsSecret(isLogin) then return end
  said = true
  C_Timer.After(6, function()
    if not (R.db and R.db.loginLine) then return end
    Today:Invalidate()
    local line = Today:LoginLine()
    if line then R:Print(line) end
  end)
end)
