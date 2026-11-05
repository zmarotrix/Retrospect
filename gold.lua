-- The Gold tab: the account's total over time (one value per character per day; an offline
-- character holds its last known gold), and each character's share. One series on one axis: a thin
-- line with a crosshair and the day's value under the mouse.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI
local C = UI.C

local Gold = {}
R.Gold = Gold
local Kit, Store = R.Kit, R.Store

local CHART_HEIGHT = 220
local LEFT, BOTTOM, TOP, RIGHT = 58, 22, 8, 8
local MAX_SEGMENTS = 180
local RANGES = { { key = 30, label = "30 days" }, { key = 90, label = "90 days" }, { key = 365, label = "A year" } }

-------------------------------------------------------------------------------------------
-- The numbers
-------------------------------------------------------------------------------------------

local function today() return R.Scan.Today() end

---A character's gold at the end of a day: the last value recorded on or before it, or nil.
local function goldOn(c, day)
  local best, value
  for d, v in pairs(c.goldDays or {}) do
    if d <= day and (not best or d > best) then best, value = d, v end
  end
  return value
end

---The account's total per day for the last `days` days: an array, oldest first, and the first day
---with any data (earlier days hold nil).
function Gold:Series(days)
  local now = today()
  local out = {}
  local byChar = {}
  for _, entry in ipairs(Store:List()) do
    local list = {}
    for d, v in pairs(entry.c.goldDays or {}) do list[#list + 1] = { d, v } end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    byChar[#byChar + 1] = list
  end
  for i = 1, days do
    local day = now - days + i
    local total, any = 0, false
    for _, list in ipairs(byChar) do
      local value
      for _, rec in ipairs(list) do
        if rec[1] <= day then value = rec[2] else break end
      end
      if value then
        total = total + value
        any = true
      end
    end
    out[i] = any and total or false
  end
  return out
end

---How much the account's total changed over the last `days` days (0 without enough history).
function Gold:Change(days)
  local now, past, then_ = today(), 0, false
  local current = 0
  for _, entry in ipairs(Store:List()) do
    current = current + (entry.c.money or goldOn(entry.c, now) or 0)
    local v = goldOn(entry.c, now - days)
    if v then
      past = past + v
      then_ = true
    else
      past = past + (entry.c.money or 0)   -- not yet tracked then: no change to report
    end
  end
  return then_ and current - past or 0
end

---One character's change over the last `days` days.
function Gold:ChangeOf(c, days)
  local v = goldOn(c, today() - days)
  return v and (c.money or 0) - v or nil
end

-------------------------------------------------------------------------------------------
-- The chart
-------------------------------------------------------------------------------------------

local function line(parent, pool, i, c, thick, layer)
  local l = pool[i]
  if not l then
    l = parent:CreateLine(nil, layer or "ARTWORK")
    pool[i] = l
  end
  l:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  l:SetThickness(thick)
  l:Show()
  return l
end

local function fmtAxis(copper)
  local g = copper / 10000
  if g >= 1000 then return string.format("%.1fk", g / 1000) end
  return string.format("%d", g)
end

local function drawChart(frame, values)
  local chart = frame.chart
  local w, h = chart:GetWidth() or 0, chart:GetHeight() or 0
  local plotW, plotH = w - LEFT - RIGHT, h - TOP - BOTTOM
  local lo, hi
  local first
  for i, v in ipairs(values) do
    if v then
      first = first or i
      lo, hi = math.min(lo or v, v), math.max(hi or v, v)
    end
  end
  local points = 0
  for _, v in ipairs(values) do if v then points = points + 1 end end
  frame.emptyChart:SetShown(points < 2)
  chart.series = values
  for _, l in ipairs(chart.lines) do l:Hide() end
  for _, l in ipairs(chart.grid) do l:Hide() end
  for _, t in ipairs(chart.labels) do t:Hide() end
  chart.xh:Hide()
  chart.dot:Hide()
  chart.tip:Hide()
  if points < 2 or plotW <= 0 or plotH <= 0 then
    chart.lo = nil
    return
  end
  if hi == lo then
    lo, hi = lo * .9, hi * 1.1 + 10000
  else
    local pad = (hi - lo) * .05
    lo, hi = math.max(0, lo - pad), hi + pad
  end
  chart.lo, chart.hi, chart.plotW, chart.plotH = lo, hi, plotW, plotH

  local n = #values
  local function X(i) return LEFT + plotW * (i - 1) / (n - 1) end
  local function Y(v) return BOTTOM + plotH * (v - lo) / (hi - lo) end

  -- three quiet gridlines, labelled in gold
  for i = 1, 3 do
    local v = lo + (hi - lo) * (i - 1) / 2
    local y = Y(v)
    local g = line(chart, chart.grid, i, C.line, 1, "BACKGROUND")
    g:SetStartPoint("BOTTOMLEFT", chart, LEFT, y)
    g:SetEndPoint("BOTTOMLEFT", chart, w - RIGHT, y)
    local t = chart.labels[i]
    if not t then
      t = UI.Text(chart, "body", 11, C.faint)
      chart.labels[i] = t
    end
    t:ClearAllPoints()
    t:SetPoint("RIGHT", chart, "BOTTOMLEFT", LEFT - 6, y)
    t:SetJustifyH("RIGHT")
    t:SetText(fmtAxis(v) .. "g")
    t:Show()
  end
  for i, share in ipairs({ 0, .5, 1 }) do
    local t = chart.labels[3 + i]
    if not t then
      t = UI.Text(chart, "body", 11, C.faint)
      chart.labels[3 + i] = t
    end
    t:ClearAllPoints()
    t:SetPoint("BOTTOM", chart, "BOTTOMLEFT", LEFT + plotW * share - (share == 1 and 14 or 0) + (share == 0 and 14 or 0), 2)
    local ago = math.floor((n - 1) * (1 - share))
    t:SetText(ago == 0 and "today" or (ago .. "d ago"))
    t:Show()
  end

  -- the line, at most a couple of hundred segments
  local step = math.max(1, math.ceil((n - first) / MAX_SEGMENTS))
  local a = chart.accent or UI.Accent("retrospect")
  local count, prevX, prevY = 0, nil, nil
  local i = first
  while true do
    local v = values[i]
    if v then
      local x, y = X(i), Y(v)
      if prevX then
        count = count + 1
        local seg = line(chart, chart.lines, count, a, 2, "ARTWORK")
        seg:SetStartPoint("BOTTOMLEFT", chart, prevX, prevY)
        seg:SetEndPoint("BOTTOMLEFT", chart, x, y)
      end
      prevX, prevY = x, y
    end
    if i == n then break end
    i = math.min(n, i + step)
  end
  return count
end

local function hover(chart)
  local values = chart.series
  if not (values and chart.lo and chart:IsMouseOver()) then
    chart.xh:Hide()
    chart.dot:Hide()
    chart.tip:Hide()
    return
  end
  local cx = GetCursorPosition() / chart:GetEffectiveScale()
  local n = #values
  local i = math.floor((cx - (chart:GetLeft() or 0) - LEFT) / chart.plotW * (n - 1) + .5) + 1
  i = math.max(1, math.min(n, i))
  local v = values[i]
  if not v then
    chart.xh:Hide()
    chart.dot:Hide()
    chart.tip:Hide()
    return
  end
  local x = LEFT + chart.plotW * (i - 1) / (n - 1)
  local y = BOTTOM + chart.plotH * (v - chart.lo) / (chart.hi - chart.lo)
  chart.xh:ClearAllPoints()
  chart.xh:SetPoint("BOTTOM", chart, "BOTTOMLEFT", x, BOTTOM)
  chart.xh:SetHeight(chart.plotH)
  chart.xh:Show()
  chart.dot:ClearAllPoints()
  chart.dot:SetPoint("CENTER", chart, "BOTTOMLEFT", x, y)
  chart.dot:Show()
  local ago = n - i
  chart.tipText:SetText((ago == 0 and "Today" or (ago .. (ago == 1 and " day ago" or " days ago"))) .. ": " .. Kit.Money(v))
  chart.tip:SetWidth(math.floor(chart.tipText:GetStringWidth() + 16))
  chart.tip:ClearAllPoints()
  local room = (chart:GetWidth() or 0) - x > 180
  chart.tip:SetPoint(room and "TOPLEFT" or "TOPRIGHT", chart, "TOPLEFT", x + (room and 8 or -8), -4)
  chart.tip:Show()
end

local function build(frame)
  frame.total = UI.Text(frame, "title", 22)
  frame.total:SetPoint("TOPLEFT", 0, -2)
  frame.deltas = UI.Text(frame, "body", 13, C.muted)
  frame.deltas:SetPoint("BOTTOMLEFT", frame.total, "BOTTOMRIGHT", 12, 2)
  frame.range = Kit.Modes(frame, RANGES, function(days)
    R.db.goldRange = days
    R.Window:Refresh()
  end)
  frame.range:SetPoint("TOPRIGHT", 0, 0)
  frame.range:SetWidth(220)

  local chart = CreateFrame("Frame", nil, frame)
  chart:SetPoint("TOPLEFT", 0, -34)
  chart:SetPoint("TOPRIGHT", 0, -34)
  chart:SetHeight(CHART_HEIGHT)
  chart:EnableMouse(true)
  chart.lines, chart.grid, chart.labels = {}, {}, {}
  chart.xh = UI.Tex(chart, "OVERLAY", 0, { .66, .63, .54, 1 })
  chart.xh:SetWidth(1)
  chart.xh:Hide()
  chart.dot = UI.Icon(chart, "circle", 9, UI.Accent("retrospect"), "OVERLAY")
  chart.dot:Hide()
  chart.tip = CreateFrame("Frame", nil, chart)
  chart.tip:SetHeight(22)
  chart.tip.box = UI.Box(chart.tip, "BACKGROUND", 0)
  chart.tip.box:Set(C.lineStrong, { .03, .04, .09 })
  chart.tipText = UI.Text(chart.tip, "body", 13)
  chart.tipText:SetPoint("LEFT", 8, 0)
  chart.tip:Hide()
  chart:SetScript("OnUpdate", hover)
  chart:SetScript("OnSizeChanged", function()
    if frame:IsVisible() then drawChart(frame, chart.series or Gold:Series(R.db.goldRange or 30)) end
  end)
  frame.chart = chart
  frame.emptyChart = Kit.Note(chart, C.muted)
  frame.emptyChart:SetPoint("CENTER")
  frame.emptyChart:SetText("Gold history starts today. The line appears once there's a second day.")

  frame.table = Kit.Table(frame, {
    { label = "Character" }, { label = "Gold", width = 130, right = true }, { label = "This week", width = 110, right = true },
    { label = "Share", width = 70, right = true }, { label = "Last seen", width = 130, right = true },
  })
  frame.table:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -12)
  frame.table:SetPoint("BOTTOMRIGHT")
end

local function fill(frame)
  local days = R.db.goldRange or 30
  frame.range:Select(days, true)
  local total = R.Window.TotalGold()
  frame.total:SetText(Kit.Money(total))
  frame.deltas:SetText(Kit.Delta(Gold:Change(7)) .. " this week · " .. Kit.Delta(Gold:Change(30)) .. " in 30 days")
  drawChart(frame, Gold:Series(days))

  local list = {}
  for _, entry in ipairs(Store:List()) do list[#list + 1] = entry end
  table.sort(list, function(a, b) return (a.c.money or 0) > (b.c.money or 0) end)
  local rows = {}
  for _, entry in ipairs(list) do
    local c = entry.c
    rows[#rows + 1] = {
      cells = { Kit.Name(c), Kit.Money(c.money or 0), Kit.Delta(Gold:ChangeOf(c, 7) or 0),
        total > 0 and (math.floor((c.money or 0) * 100 / total + .5) .. "%") or "—",
        entry.key == Store:MyKey() and "logged in" or UI.Code(C.muted) .. R.Today.Ago(c.seen) .. "|r" },
      onClick = function() R.Window:Select(entry.key) end,
    }
  end
  frame.table:SetRows(rows, true)
end

R.Window:RegisterPane("gold", build, fill)
