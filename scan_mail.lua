-- The mailbox, and mail sent to your own characters. Expiry is worked out when the mailbox is read
-- (days left then, counted from then), so it stays right while the character is offline.
-- A mail you send to one of your characters counts toward its items at once, as "on its way".

local Core = NorgannonCore
local R = Retrospect
if R.disabled then return end

local Scan, Store = R.Scan, R.Store

local ATTACHMENTS = 16      -- more than any client's slots; empty ones are skipped
local ARRIVES_AFTER = 3600  -- the game's delivery time for mail with items or money, at most

-------------------------------------------------------------------------------------------
-- Reading the mailbox
-------------------------------------------------------------------------------------------

local function readAttachments(index, count)
  local out = {}
  if (count or 0) == 0 then return "" end
  for slot = 1, rawget(_G, "ATTACHMENTS_MAX_RECEIVE") or ATTACHMENTS do
    local _, id, _, stack, quality = R.Global("GetInboxItem", index, slot)
    if id then
      out[#out + 1] = Store.Entry(id, stack or 1, quality, false, R.Global("GetInboxItemLink", index, slot))
    end
  end
  return table.concat(out, ";")
end

function Scan:Mail()
  local c = Store:Me()
  local total = R.Global("GetInboxNumItems")
  if not total then
    Scan.Note("Mail", false, "GetInboxNumItems gave nothing")
    return
  end
  local now, list, read = R.Now(), {}, 0
  for i = 1, total do
    local _, _, sender, subject, money, cod, daysLeft, itemCount, wasRead = R.Global("GetInboxHeaderInfo", i)
    if daysLeft then
      list[#list + 1] = {
        from = sender, subject = subject, money = (money or 0) > 0 and money or nil, cod = (cod or 0) > 0 and cod or nil,
        expires = now + math.floor(daysLeft * 86400), read = wasRead and true or nil,
        items = readAttachments(i, itemCount),
      }
      read = read + 1
    end
  end
  c.mail = { seen = now, list = list }

  -- what was on its way and is in the box now; what should have arrived but isn't has been taken
  -- by another route (returned, or read before this scan), so it no longer counts either
  if c.incoming then
    local keep = {}
    for _, m in ipairs(c.incoming) do
      local found = false
      for _, box in ipairs(list) do
        if box.from == m.from and box.subject == m.subject then found = true break end
      end
      if not found and m.arrives > now then keep[#keep + 1] = m end
    end
    c.incoming = #keep > 0 and keep or nil
  end
  Scan.Note("Mail", read == total, string.format("%d of %d mails read", read, total))
  R:Changed(Store:MyKey(), true)
end

local function queueMail() Core:NextFrame(function() Scan:Mail() end, "retrospect.mail") end
Core:On("MAIL_SHOW", "retrospect.mail", function()
  R.Global("CheckInbox")
  queueMail()
end)
Core:On("MAIL_INBOX_UPDATE", "retrospect.mail", queueMail)

-------------------------------------------------------------------------------------------
-- Mail to your own characters. Only a hook that watches: SendMail itself is never replaced.
-------------------------------------------------------------------------------------------

local pending

---The character key of a recipient on this realm, if it is one of yours.
local function ownCharacter(recipient)
  if type(recipient) ~= "string" or Core.IsSecret(recipient) then return nil end
  local name, realm = strsplit("-", recipient, 2)
  local me = Store:Me()
  local key = (realm or me.realm) .. "-" .. name
  for _, entry in ipairs(Store:List()) do
    if string.lower(entry.key) == string.lower(key) then return entry.key end
  end
end

local function onSend(recipient, subject)
  pending = nil
  local key = ownCharacter(recipient)
  if not key or key == Store:MyKey() then return end
  local out = {}
  for slot = 1, rawget(_G, "ATTACHMENTS_MAX_SEND") or ATTACHMENTS do
    local _, id, _, stack, quality = R.Global("GetSendMailItem", slot)
    if id then
      out[#out + 1] = Store.Entry(id, stack or 1, quality, false, R.Global("GetSendMailItemLink", slot))
    end
  end
  local money = R.Global("GetSendMailMoney") or 0
  if #out == 0 and money == 0 then return end
  pending = { key = key, mail = { from = Store:Me().name, subject = subject, money = money > 0 and money or nil, items = table.concat(out, ";") } }
end

if rawget(_G, "SendMail") then
  hooksecurefunc("SendMail", onSend)
end

Core:On("MAIL_SEND_SUCCESS", "retrospect.mail", function()
  if not pending then return end
  local target = Store:Get(pending.key)
  if target then
    pending.mail.arrives = R.Now() + ARRIVES_AFTER
    target.incoming = target.incoming or {}
    table.insert(target.incoming, pending.mail)
    R:Changed(pending.key, true)
  end
  pending = nil
end)
Core:On("MAIL_FAILED", "retrospect.mail", function() pending = nil end)
