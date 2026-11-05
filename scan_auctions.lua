-- Your auctions and bids, read when the auction house opens. Forever has C_AuctionHouse, not the
-- classic GetAuctionItemInfo. Time left is turned into an end time, so it keeps counting offline.

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end

local Scan, Store = R.Scan, R.Store

-- Enum.AuctionHouseTimeLeftBand: the longest each band can mean, when no exact time is given
local BAND_SECONDS = { [0] = 1800, [1] = 7200, [2] = 43200, [3] = 172800 }
local BAND_UNKNOWN = 43200

local function itemEntry(info)
  local link = info.itemLink
  local key = type(info.itemKey) == "table" and info.itemKey or nil
  local id = key and key.itemID or (link and tonumber(link:match("item:(%d+)")))
  if not id then return nil end
  return Store.Entry(id, info.quantity or 1, R.In("C_Item", "GetItemQualityByID", id), false, link), id
end

local function untilEnd(info)
  if info.timeLeftSeconds then return info.timeLeftSeconds end
  return BAND_SECONDS[info.timeLeft] or BAND_UNKNOWN
end

function Scan:Auctions()
  local c = Store:Me()
  local total = R.In("C_AuctionHouse", "GetNumOwnedAuctions")
  if not total then
    Scan.Note("Auctions", false, "GetNumOwnedAuctions gave nothing")
    return
  end
  local now, list = R.Now(), {}
  local sold = rawget(_G, "Enum") and Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1
  for i = 1, total do
    local info = R.In("C_AuctionHouse", "GetOwnedAuctionInfo", i)
    if type(info) == "table" then
      local item = itemEntry(info)
      if item then
        list[#list + 1] = {
          item = item, buyout = info.buyoutAmount, bid = info.bidAmount,
          expires = now + untilEnd(info), sold = info.status == sold or nil,
        }
      end
    end
  end
  c.auctions = c.auctions or {}
  c.auctions.seen, c.auctions.list = now, list
  Scan.Note("Auctions", #list == total, string.format("%d of %d auctions read", #list, total))
  R:Changed(Store:MyKey(), true)
end

function Scan:Bids()
  local c = Store:Me()
  local total = R.In("C_AuctionHouse", "GetNumBids")
  if not total then return end
  local now, list = R.Now(), {}
  for i = 1, total do
    local info = R.In("C_AuctionHouse", "GetBidInfo", i)
    if type(info) == "table" then
      local item = itemEntry(info)
      if item then
        list[#list + 1] = { item = item, buyout = info.buyoutAmount, bid = info.bidAmount, expires = now + untilEnd(info) }
      end
    end
  end
  c.auctions = c.auctions or { list = {} }
  c.auctions.bids = list
  R:Changed(Store:MyKey(), true)
end

Core:On("AUCTION_HOUSE_SHOW", "retrospect.auctions", function()
  -- after the auction house's own first queries, which share the same throttle
  C_Timer.After(1, function()
    R.In("C_AuctionHouse", "QueryOwnedAuctions", {})
    R.In("C_AuctionHouse", "QueryBids", {}, {})
  end)
end)
Core:On("OWNED_AUCTIONS_UPDATED", "retrospect.auctions", function()
  Core:NextFrame(function() Scan:Auctions() end, "retrospect.auctions")
end)
Core:On("BIDS_UPDATED", "retrospect.auctions", function()
  Core:NextFrame(function() Scan:Bids() end, "retrospect.bids")
end)
