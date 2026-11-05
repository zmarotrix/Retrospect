-- Bags, bank and guild bank. The client's bank has been tabs and classic bank bags on different
-- builds, so both are read: the character's tabs from C_Bank when it answers, else whichever bank
-- containers have slots. The bank can only be read while it is open; the rest of the time this
-- is what it held when last seen. Account bank tabs belong to the whole account.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end

local Scan, Store = R.Scan, R.Store

local function bagIndex()
  return (rawget(_G, "Enum") and Enum.BagIndex) or {}
end

---One container as { id, size, free, items = packed }, or nil if it has no slots.
local function readContainer(id, name, keyring)
  local size = R.In("C_Container", "GetContainerNumSlots", id)
  if not size or size <= 0 then return nil end
  local out, free = {}, 0
  for slot = 1, size do
    local info = R.In("C_Container", "GetContainerItemInfo", id, slot)
    if type(info) == "table" and info.itemID then
      out[#out + 1] = Store.Entry(info.itemID, info.stackCount or 1, info.quality, info.isBound, info.hyperlink)
    else
      free = free + 1
    end
  end
  return { id = id, size = size, free = free, name = name, keyring = keyring, items = table.concat(out, ";") }
end

local function readSection(list)
  local section = { seen = R.Now(), slots = 0, free = 0, containers = {} }
  for _, spec in ipairs(list) do
    local box = readContainer(spec.id, spec.name, spec.keyring)
    if box then
      table.insert(section.containers, box)
      -- keys go nowhere else, so the keyring's slots aren't bag space
      if not box.keyring then
        section.slots = section.slots + box.size
        section.free = section.free + box.free
      end
    end
  end
  return section
end

-------------------------------------------------------------------------------------------
-- Bags: only the bags that changed are read again
-------------------------------------------------------------------------------------------

---A bag's own name ("Small Silk Pack"), from the item in its slot.
local function bagName(id, fallback)
  local slot = R.In("C_Container", "ContainerIDToInventoryID", id)
  local link = slot and R.Global("GetInventoryItemLink", "player", slot)
  return link and link:match("%[(.-)%]") or fallback
end

local function bagList()
  local B = bagIndex()
  local list = { { id = B.Backpack or 0, name = "Backpack" } }
  for i = 1, 4 do
    local id = B["Bag_" .. i] or i
    list[#list + 1] = { id = id, name = bagName(id, "Bag " .. i) }
  end
  if B.ReagentBag then list[#list + 1] = { id = B.ReagentBag, name = bagName(B.ReagentBag, "Reagent bag") } end
  if B.Keyring then list[#list + 1] = { id = B.Keyring, name = "Keyring", keyring = true } end
  return list
end

function Scan:Bags()
  local c = Store:Me()
  local section = readSection(bagList())
  Scan.Note("Bags", section.slots > 0, string.format("%d slots, %d free", section.slots, section.free))
  -- early in a login the client can still report no slots; that isn't an empty backpack
  if section.slots > 0 then
    c.bags = section
    R:Changed(Store:MyKey(), true)
  end
end

local function queueBags()
  Core:NextFrame(function()
    Core:AfterCombat(function() Scan:Bags() end, "retrospect.bags")
  end, "retrospect.bags")
end

-------------------------------------------------------------------------------------------
-- Bank
-------------------------------------------------------------------------------------------

local bankOpen = false

---Character bank containers: the purchased tabs, else every bank container that has slots.
local function bankList(kind)
  local B = bagIndex()
  local list = {}
  local bankType = rawget(_G, "Enum") and Enum.BankType and Enum.BankType[kind]
  if bankType ~= nil then
    local tabs = R.In("C_Bank", "FetchPurchasedBankTabData", bankType)
    if type(tabs) == "table" then
      for _, tab in ipairs(tabs) do
        if type(tab) == "table" and tab.ID then list[#list + 1] = { id = tab.ID, name = tab.name } end
      end
    end
    if #list == 0 then
      local ids = R.In("C_Bank", "FetchPurchasedBankTabIDs", bankType)
      if type(ids) == "table" then
        for i, id in ipairs(ids) do list[#list + 1] = { id = id, name = "Tab " .. i } end
      end
    end
  end
  if #list > 0 then return list end
  local prefix = kind == "Account" and "AccountBankTab_" or "CharacterBankTab_"
  for i = 1, 9 do
    if B[prefix .. i] then list[#list + 1] = { id = B[prefix .. i], name = "Tab " .. i } end
  end
  if kind == "Character" then
    if B.Bank then list[#list + 1] = { id = B.Bank, name = "Bank" } end
    for i = 1, 7 do
      if B["BankBag_" .. i] then list[#list + 1] = { id = B["BankBag_" .. i], name = "Bank bag " .. i } end
    end
  end
  return list
end

function Scan:Bank()
  if not bankOpen then return end
  local c = Store:Me()
  local section = readSection(bankList("Character"))
  if section.slots > 0 then
    c.bank = section
    Scan.Note("Bank", true, string.format("%d slots in %d containers", section.slots, #section.containers))
  else
    Scan.Note("Bank", false, "the bank was open but no container had slots")
  end
  if R.In("C_PlayerInfo", "IsAccountBankEnabled") ~= false then
    local shared = readSection(bankList("Account"))
    if shared.slots > 0 then
      R.db.accountBank = shared
      Scan.Note("Account bank", true, shared.slots .. " slots")
      R:Changed("account", true)
    else
      Scan.Note("Account bank", false, "no tabs with slots")
    end
  end
  R:Changed(Store:MyKey(), true)
end

local function queueBank()
  if bankOpen then Core:NextFrame(function() Scan:Bank() end, "retrospect.bank") end
end

Core:On("BANKFRAME_OPENED", "retrospect.bags", function()
  bankOpen = true
  queueBank()
end)
Core:On("BANKFRAME_CLOSED", "retrospect.bags", function() bankOpen = false end)
for _, event in ipairs({ "PLAYERBANKSLOTS_CHANGED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED" }) do
  Core:On(event, "retrospect.bags", queueBank)
end

-------------------------------------------------------------------------------------------
-- Guild bank, only where the client has one
-------------------------------------------------------------------------------------------

local guildOpen = false

function Scan:GuildBank()
  if not guildOpen then return end
  local c = Store:Me()
  local key = Store:GuildKey(c)
  if not key then return end
  local tabs = R.Global("GetNumGuildBankTabs") or 0
  local record = { seen = R.Now(), name = c.guild, realm = c.realm, tabs = {} }
  local n = 0
  for tab = 1, tabs do
    local name, _, viewable = R.Global("GetGuildBankTabInfo", tab)
    if viewable then
      local out = {}
      for slot = 1, rawget(_G, "MAX_GUILDBANK_SLOTS_PER_TAB") or 98 do
        local link = R.Global("GetGuildBankItemLink", tab, slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
          local _, count, _, _, quality = R.Global("GetGuildBankItemInfo", tab, slot)
          out[#out + 1] = Store.Entry(id, count or 1, quality, false, link)
          n = n + 1
        end
      end
      record.tabs[#record.tabs + 1] = { name = name, items = table.concat(out, ";") }
    end
  end
  R.db.guilds[key] = record
  Scan.Note("Guild bank", tabs > 0, string.format("%d tabs, %d stacks", tabs, n))
  R:Changed("guild:" .. key, true)
end

Core:On("GUILDBANKFRAME_OPENED", "retrospect.bags", function()
  if R.In("C_GuildBank", "IsGuildBankEnabled") == false then
    Scan.Note("Guild bank", false, "IsGuildBankEnabled is false")
    return
  end
  guildOpen = true
  for tab = 1, R.Global("GetNumGuildBankTabs") or 0 do R.Global("QueryGuildBankTab", tab) end
end)
Core:On("GUILDBANKFRAME_CLOSED", "retrospect.bags", function() guildOpen = false end)
Core:On("GUILDBANKBAGSLOTS_CHANGED", "retrospect.bags", function()
  if guildOpen then Core:NextFrame(function() Scan:GuildBank() end, "retrospect.guildbank") end
end)

-------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------

Core:OnLogin(function()
  if not R.db then return end
  Scan:Bags()
end)
Core:On("PLAYER_ENTERING_WORLD", "retrospect.bags", function()
  queueBags()
  Core:Off("PLAYER_ENTERING_WORLD", "retrospect.bags")
end)
Core:On("BAG_UPDATE_DELAYED", "retrospect.bags", function()
  queueBags()
  queueBank()
end)
