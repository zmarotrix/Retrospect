-- What the panes share: gold and time as text, class and quality colours, an item tile with the
-- game's tooltip, a virtual table, a "seen" label that turns amber when old.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end
local UI = Core.UI
local C = UI.C

local Kit = {}
R.Kit = Kit
local Store = R.Store

-------------------------------------------------------------------------------------------
-- Colours
-------------------------------------------------------------------------------------------

Kit.UP = { .56, .88, .56 }       -- more gold, done, ready
Kit.DOWN = { 1, .58, .47 }       -- less gold, urgent
Kit.PART = { 1, .82, 0 }         -- on the way
Kit.UNKNOWN = { .85, .63, .4 }   -- not seen, old

local CLASS = {
  WARRIOR = { .78, .61, .43 }, PALADIN = { .96, .55, .73 }, HUNTER = { .67, .83, .45 }, ROGUE = { 1, .96, .41 },
  PRIEST = { 1, 1, 1 }, SHAMAN = { 0, .44, .87 }, MAGE = { .25, .78, .92 }, WARLOCK = { .53, .53, .93 }, DRUID = { 1, .49, .04 },
  DEATHKNIGHT = { .77, .12, .23 },
}
local QUALITY = {
  [0] = { .62, .62, .62 }, [1] = { 1, 1, 1 }, [2] = { .12, 1, 0 }, [3] = { 0, .44, .87 }, [4] = { .64, .21, .93 }, [5] = { 1, .5, 0 },
}

function Kit.ClassColor(token) return CLASS[token] or C.text end
function Kit.QualityColor(q) return QUALITY[q] or C.text end

---A character's name in its class colour.
function Kit.Name(c)
  if not c then return "?" end
  return UI.Code(Kit.ClassColor(c.class)) .. tostring(c.name) .. "|r"
end

-------------------------------------------------------------------------------------------
-- Text
-------------------------------------------------------------------------------------------

local GOLD, SILVER = { .906, .776, .424 }, { .78, .78, .78 }

local function commas(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
Kit.Commas = commas

---"84,213g", or "12g 40s" below 1,000 gold, or "40s" below a gold; in gold and silver colours.
function Kit.Money(copper)
  copper = copper or 0
  local g, s = math.floor(math.abs(copper) / 10000), math.floor((math.abs(copper) % 10000) / 100)
  local sign = copper < 0 and "-" or ""
  if g > 0 and (g >= 1000 or s == 0) then return UI.Code(GOLD) .. sign .. commas(g) .. "g|r" end
  if g > 0 then return UI.Code(GOLD) .. sign .. g .. "g|r " .. UI.Code(SILVER) .. s .. "s|r" end
  return UI.Code(SILVER) .. sign .. s .. "s|r"
end

---"+3,410g" / "-212g" / "—", coloured.
function Kit.Delta(copper)
  local g = math.floor(math.abs(copper or 0) / 10000)
  if g == 0 then return UI.Code(C.faint) .. "—|r" end
  if copper > 0 then return UI.Code(Kit.UP) .. "+" .. commas(g) .. "g|r" end
  return UI.Code(Kit.DOWN) .. "-" .. commas(g) .. "g|r"
end

local OLD = 14 * 86400

---"seen 2d ago", amber once it is old enough to doubt; "never opened" without a time.
function Kit.Seen(at, never)
  if not at then return UI.Code(Kit.UNKNOWN) .. (never or "never opened") .. "|r" end
  local old = R.Now() - at > OLD
  return UI.Code(old and Kit.UNKNOWN or C.faint) .. "seen " .. R.Today.Ago(at) .. "|r"
end

---A character's played time: "41d 6h".
function Kit.Played(seconds)
  if not seconds then return nil end
  return R.Today.Span(seconds)
end

-------------------------------------------------------------------------------------------
-- An item tile: icon, count, quality edge; hover for the game's tooltip, shift-click to link,
-- right-click for the suite's menu
-------------------------------------------------------------------------------------------

---UI: Kit.ItemTile(parent, size). :SetItem({ id, count, q, link }) or :SetItem(nil) for an empty slot.
function Kit.ItemTile(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.edge = UI.Tex(b, "BACKGROUND", 0, C.lineStrong)
  b.edge:SetAllPoints()
  b.back = UI.Tex(b, "BACKGROUND", 1, { .05, .04, .03 })
  b.back:SetPoint("TOPLEFT", 1, -1)
  b.back:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(.07, .93, .07, .93)
  b.count = UI.Text(b, "bold", 12, { 1, 1, 1 }, "OVERLAY")
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)

  function b:SetItem(item)
    self.item = item
    if not item then
      self.icon:Hide()
      self.count:SetText("")
      self.edge:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
      return
    end
    self.icon:SetTexture(R.In("C_Item", "GetItemIconByID", item.id) or 134400)
    self.icon:Show()
    self.count:SetText((item.count or 1) > 1 and tostring(item.count) or "")
    local q = Kit.QualityColor(R.Index:Quality(item.id) or item.q)
    self.edge:SetColorTexture(q[1], q[2], q[3], (item.q or 1) >= 2 and .9 or .25)
  end

  b:SetScript("OnEnter", function(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.item.link or ("item:" .. self.item.id))
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self, button)
    if not self.item then return end
    Kit.ItemClick(self, self.item.id, button, self.item.link)
  end)
  return b
end

---Shift-click links the item in chat; right-click opens the suite's menu for it.
function Kit.ItemClick(owner, id, button, link)
  if button == "RightButton" then
    Core:ShowActionMenu(owner, "item", id, { title = Store:ItemName(id) })
  elseif IsShiftKeyDown() then
    local name = Store:ItemName(id)
    local full = link and ("|H" .. link .. "|h[" .. name .. "]|h") or nil
    if not full then
      local _, itemLink = R.In("C_Item", "GetItemInfo", id)
      full = itemLink
    end
    if full then R.Global("ChatEdit_InsertLink", full) end
  end
end

-------------------------------------------------------------------------------------------
-- A virtual table: fixed columns, header line, any number of rows
--
--   local t = Kit.Table(parent, { {label = "Faction"}, {label = "Standing", width = 120, right = true} })
--   t:SetRows({ { group = "Horde" }, { cells = { "Orgrimmar", "Honored" }, tip = fn(tt), onClick = fn(button, row) } })
--
-- One column without a width takes what is left. A row { note = "..." } is one line of quiet text
-- across the table. A row's `item` puts a tile before the first cell.
-------------------------------------------------------------------------------------------

local TILE = 18

function Kit.Table(parent, cols, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  local rowHeight = opts.rowHeight or 22
  local headed = false
  for _, col in ipairs(cols) do headed = headed or col.label ~= nil end
  local PAD = 8
  local left, right = {}, {}
  do
    local x = PAD
    for i, col in ipairs(cols) do
      left[i] = x
      if not col.width then break end
      x = x + col.width + PAD
    end
    x = PAD
    for i = #cols, 1, -1 do
      if not cols[i].width then break end
      right[i] = x
      x = x + cols[i].width + PAD
    end
  end

  local function place(fs, i, parentFrame)
    local col = cols[i]
    if not col.width then
      fs:SetPoint("LEFT", parentFrame, "LEFT", left[i], 0)
      fs:SetPoint("RIGHT", parentFrame, "RIGHT", -(right[i + 1] and (right[i + 1] + (cols[i + 1].width or 0) + PAD) or PAD), 0)
    elseif left[i] then
      fs:SetPoint("LEFT", parentFrame, "LEFT", left[i], 0)
      fs:SetWidth(col.width)
    else
      fs:SetPoint("RIGHT", parentFrame, "RIGHT", -right[i], 0)
      fs:SetWidth(col.width)
    end
    fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
    fs:SetWordWrap(false)
  end

  if headed then
    f.header = CreateFrame("Frame", nil, f)
    f.header:SetPoint("TOPLEFT")
    f.header:SetPoint("TOPRIGHT")
    f.header:SetHeight(20)
    local rule = UI.Rule(f.header)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    f.headers = {}
    for i, col in ipairs(cols) do
      local fs = UI.Text(f.header, "body", 12, C.faint)
      place(fs, i, f.header)
      fs:SetText(col.label or "")
      f.headers[i] = fs
    end
  end

  f.list = UI.List(f, {
    rowHeight = rowHeight,
    groupBand = true,
    createRow = function(row, content)
      row.cells = {}
      for i in ipairs(cols) do
        local fs = UI.Text(content, "body", 13, C.text)
        place(fs, i, content)
        row.cells[i] = fs
      end
      row.noteText = UI.Text(content, "body", 13, C.muted)
      row.noteText:SetPoint("LEFT", PAD, 0)
      row.noteText:SetPoint("RIGHT", -PAD, 0)
      row.noteText:SetWordWrap(false)
      row.tile = Kit.ItemTile(content, TILE)
      row.tile:SetPoint("LEFT", PAD, 0)
      row.tile:Hide()
    end,
    updateRow = function(row, item)
      if item.note then
        row.noteText:SetText(item.note)
        row.noteText:Show()
        row.tile:Hide()
        for _, fs in ipairs(row.cells) do fs:SetText("") end
        return
      end
      row.noteText:Hide()
      for i, fs in ipairs(row.cells) do fs:SetText(item.cells and item.cells[i] or "") end
      row.cells[1]:ClearAllPoints()
      if item.item then
        row.tile:SetItem(item.item)
        row.tile:Show()
        row.cells[1]:SetPoint("LEFT", row.content, "LEFT", PAD + TILE + 6, 0)
      else
        row.tile:Hide()
        row.cells[1]:SetPoint("LEFT", row.content, "LEFT", PAD, 0)
      end
      local first = cols[1]
      if first.width then
        row.cells[1]:SetWidth(first.width - (item.item and (TILE + 6) or 0))
      else
        row.cells[1]:SetPoint("RIGHT", row.content, "RIGHT", -(right[2] and (right[2] + (cols[2].width or 0) + PAD) or PAD), 0)
      end
    end,
    onClick = function(item, _, button)
      if item.onClick then item.onClick(button, item) end
    end,
    onEnter = function(row, item)
      if item.tip then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        item.tip(GameTooltip)
        GameTooltip:Show()
      elseif item.note then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(item.note, 1, 1, 1, true)
        GameTooltip:Show()
      end
    end,
    onLeave = function() GameTooltip:Hide() end,
  })
  f.list:SetPoint("TOPLEFT", f.header or f, f.header and "BOTTOMLEFT" or "TOPLEFT", 0, f.header and -2 or 0)
  f.list:SetPoint("BOTTOMRIGHT")

  ---Rows, keeping the scroll position when keep is true.
  function f:SetRows(rows, keep) self.list:SetData(rows, keep) end
  return f
end

-------------------------------------------------------------------------------------------
-- A row of radio chips: exactly one on
-------------------------------------------------------------------------------------------

---Kit.Modes(parent, { {key, label} }, onSelect): the chips, laid out left to right. :Select(key).
function Kit.Modes(parent, items, onSelect)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(22)
  row.chips = {}
  local previous
  function row:Select(key, silent)
    self.selected = key
    for _, chip in ipairs(self.chips) do chip:SetOn(chip.key == key, true) end
    if not silent and onSelect then onSelect(key) end
  end
  for _, item in ipairs(items) do
    local chip = UI.Chip(row, item.label)
    chip.key = item.key
    chip:SetScript("OnClick", function(self) row:Select(self.key) end)
    if previous then
      chip:SetPoint("LEFT", previous, "RIGHT", 5, 0)
    else
      chip:SetPoint("LEFT", 0, 0)
    end
    table.insert(row.chips, chip)
    previous = chip
  end
  return row
end

---A pane's quiet line of text under its content (or an empty state).
function Kit.Note(parent, color)
  local fs = UI.Text(parent, "body", 13, color or C.muted)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  return fs
end
