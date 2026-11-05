-- The Today tab: the list on the left, the account and what Retrospect hasn't seen on the right.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI
local C = UI.C

local Kit, Store, Today = R.Kit, R.Store, R.Today

local SIDE = 300
local WHEN = 110   -- the time column
local GROUPS = {
  { kind = "urgent", label = "Act soon" }, { kind = "ready", label = "Ready now" },
  { kind = "soon", label = "Coming up" }, { kind = "info", label = "Good to know" },
}
local WHEN_COLOR = { urgent = { 1, .58, .47 }, ready = { .56, .88, .56 }, soon = C.text, info = C.muted }

local function createRow(row, content)
  row.ring = CreateFrame("Frame", nil, content)
  row.ring:SetSize(28, 28)
  row.ring:SetPoint("LEFT", 8, 0)
  row.ring.tex = UI.Tex(row.ring, "BACKGROUND", 0, C.lineStrong)
  row.ring.tex:SetAllPoints()
  row.icon = row.ring:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("TOPLEFT", 1, -1)
  row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  row.icon:SetTexCoord(.07, .93, .07, .93)
  row.when = UI.Text(content, "body", 13)
  row.when:SetPoint("RIGHT", -10, 0)
  row.when:SetWidth(WHEN)
  row.when:SetJustifyH("RIGHT")
  row.when:SetWordWrap(false)
  row.title = UI.Text(content, "body", 14)
  row.title:SetPoint("TOPLEFT", row.ring, "TOPRIGHT", 10, 2)
  row.title:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(WHEN + 20), -6)
  row.title:SetWordWrap(false)
  row.sub = UI.Text(content, "body", 12, C.muted)
  row.sub:SetPoint("BOTTOMLEFT", row.ring, "BOTTOMRIGHT", 10, -2)
  row.sub:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -(WHEN + 20), 6)
  row.sub:SetWordWrap(false)
end

local function updateRow(row, item)
  local e = item.event
  local c = Store:Get(e.who)
  row.icon:SetTexture(e.icon)
  row.title:SetText(Kit.Name(c) .. UI.Code(C.faint) .. " · |r" .. e.title)
  row.sub:SetText(e.sub or "")
  row.when:SetText(e.when or "")
  local wc = WHEN_COLOR[e.kind] or C.text
  row.when:SetTextColor(wc[1], wc[2], wc[3])
  local ring = e.kind == "urgent" and { .85, .35, .23 } or e.kind == "ready" and { .31, .66, .31 } or C.lineStrong
  row.ring.tex:SetColorTexture(ring[1], ring[2], ring[3], 1)
end

local function buildRows(events)
  local rows = {}
  for _, group in ipairs(GROUPS) do
    local first = true
    for _, e in ipairs(events) do
      if e.kind == group.kind then
        if first then
          rows[#rows + 1] = { group = group.label }
          first = false
        end
        rows[#rows + 1] = { event = e }
      end
    end
  end
  return rows
end

local function sumRow(parent, label, y)
  local l = UI.Text(parent, "body", 13, C.muted)
  l:SetPoint("TOPLEFT", 0, y)
  l:SetText(label)
  local v = UI.Text(parent, "body", 13)
  v:SetPoint("TOPRIGHT", 0, y)
  v:SetJustifyH("RIGHT")
  return v
end

local function build(frame)
  local side = CreateFrame("Frame", nil, frame)
  side:SetPoint("TOPRIGHT")
  side:SetPoint("BOTTOMRIGHT")
  side:SetWidth(SIDE)

  frame.list = UI.List(frame, {
    rowHeight = 44, groupBand = true, createRow = createRow, updateRow = updateRow,
    onClick = function(item) R.Window:Select(item.event.who) end,
  })
  frame.list:SetPoint("TOPLEFT")
  frame.list:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -14, 0)
  frame.empty = UI.Text(frame.list, "body", 14, C.muted)
  frame.empty:SetPoint("TOP", 0, -40)
  frame.empty:SetText("Nothing waiting on any character.")

  local card = UI.Card(side, "The account")
  card:SetPoint("TOPLEFT")
  card:SetPoint("TOPRIGHT")
  card:SetHeight(174)
  frame.gold = sumRow(card.body, "Gold", 0)
  frame.week = sumRow(card.body, "This week", -21)
  frame.played = sumRow(card.body, "Played", -42)
  frame.space = sumRow(card.body, "Bag space", -63)
  frame.mail = sumRow(card.body, "Mail waiting", -84)
  frame.auctions = sumRow(card.body, "Auctions up", -105)

  local stale = UI.Card(side, "What Retrospect hasn't seen")
  stale:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -10)
  stale:SetPoint("BOTTOMRIGHT")
  local note = Kit.Note(stale.body, C.muted)
  note:SetPoint("TOPLEFT")
  note:SetPoint("TOPRIGHT")
  note:SetText("Numbers can be out of date or short by what's listed here.")
  frame.unseen = Kit.Table(stale.body, { {}, { width = 110, right = true } }, { rowHeight = 20 })
  frame.unseen:SetPoint("TOPLEFT", 0, -38)
  frame.unseen:SetPoint("BOTTOMRIGHT")
end

local function who(n, what)
  return string.format("%d %s", n, what)
end

local function fill(frame)
  local events = Today:Events()
  frame.list:SetData(buildRows(events), true)
  frame.empty:SetShown(#events == 0)

  local played, free, slots, mails, mailChars, ups, upChars = 0, 0, 0, 0, 0, 0, 0
  for _, entry in ipairs(Store:List()) do
    local c = entry.c
    played = played + (c.played or 0)
    if c.bags then
      free = free + c.bags.free
      slots = slots + c.bags.slots
    end
    local nm = c.mail and c.mail.list and #c.mail.list or 0
    if nm > 0 then
      mails = mails + nm
      mailChars = mailChars + 1
    end
    local na = 0
    for _, a in ipairs(c.auctions and c.auctions.list or {}) do
      if not a.sold then na = na + 1 end
    end
    if na > 0 then
      ups = ups + na
      upChars = upChars + 1
    end
  end
  frame.gold:SetText(Kit.Money(R.Window.TotalGold()))
  frame.week:SetText(Kit.Delta(R.Gold and R.Gold:Change(7) or 0))
  frame.played:SetText(played > 0 and Kit.Played(played) or UI.Code(C.faint) .. "—|r")
  frame.space:SetText(string.format("%d of %d free", free, slots))
  frame.mail:SetText(mails > 0 and string.format("%d on %s", mails, who(mailChars, mailChars == 1 and "character" or "characters")) or "None")
  frame.auctions:SetText(ups > 0 and string.format("%d on %s", ups, who(upChars, upChars == 1 and "character" or "characters")) or "None")

  local rows = {}
  for _, u in ipairs(Today:Unseen()) do
    rows[#rows + 1] = { cells = { Kit.Name(Store:Get(u.who)) .. " " .. u.what, UI.Code(Kit.UNKNOWN) .. u.state .. "|r" },
      onClick = function() R.Window:Select(u.who) end }
  end
  if #rows == 0 then rows[1] = { note = "Nothing: every bank and profession has been read." } end
  frame.unseen:SetRows(rows, true)
end

R.Window:RegisterPane("today", build, fill)
