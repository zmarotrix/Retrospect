# Changelog

## 0.10.0, 2026-11-07

- Built on NorgannonDB Core 1.20's `Core:NewAddon`: the same commands, window and settings, with Core's setup and
  client calls in place of Retrospect's own. `/retro help` lists the commands; `/retro <item>` still searches.
- The "Show the minimap button" setting is gone: NorgannonDB > Minimap pins any add-on.
- Settings asked for in combat open when the fight ends.

## 0.9.3, 2026-11-06

- Which containers a character has, and the kinds of item, now come from the Core (`Core.Bags`, Core 1.16), shared
  with Dimension. Nothing changes on screen.

## 0.9.2, 2026-11-05

From the first real saved file, and a design pass over every screen.

- **Reputation:** each standing in its colour with a bar through it and the numbers, a summary
  at the top, and a choice of By group or By standing. Compare's reputation grid matches.
- **Bags & Bank:** organized. By type sorts each place into Gear, Consumables, Trade goods, Recipes,
  Quest items, Keys, Junk and Other, with stacks added up and chips to show one kind. By bag lays
  them out as the game does, with each bag's own name. Each place shows how full it is.
- **Professions:** a heading with a bar for each profession, and All / Known / Not known.
- **Clearer:** quality edges only where they mean something, hover on item tiles, stronger contrast
  for information that was faint; Overview's Bag space and Professions lead to their tabs.
- **Fixed:** the keyring no longer counts as bag space. Logging out no longer wipes the rest reading.
  A spec that is only the class's name ("Druid Druid") isn't shown.
- **Learned in game:** `IsSpellKnown` doesn't find recipes on Forever, so recipes appear once you
  open each profession. `/retro probe` says so.

## 0.9.1, 2026-11-05

- **Resizable:** drag the window's bottom-right corner; lists and tables reflow and the text keeps
  its size. Right-click the corner for the default size. It also starts smaller, at about 1120 x 700.
- The settings' size slider is now Zoom, which scales everything, text too.

## 0.9.0, 2026-11-05

The first build. It has passed its harness but hasn't been played in game; `/retro probe` says what
each part can read on your client. Requires NorgannonDB 1.4 and NorgannonDB Core 1.15.

- **One window, one scope:** All characters (Today, Items, Compare, Gold) or one character
  (Overview, Bags & Bank, Gear, Mail & Auctions, Quests, Professions, Reputation).
- **Today:** mail about to expire, auctions sold, money waiting, cooldowns, lockouts ending, full
  bags, rested characters. One quiet chat line at login when something is urgent, never on /reload.
- **Honest about staleness:** every block says when it was seen; never opened isn't empty.
- **Who has it:** search across bags, banks (tabs or classic), account bank, guild bank where the
  client has one, mail, auctions and gear, with place filters and Can be mailed.
- **Mail to your own characters** counts at once.
- **Tooltips:** who holds an item, who can learn a recipe, who needs an item for a quest; who has
  done a quest and who is on it.
- **Compare:** reputation, professions, attunements and keys from NorgannonDB, lockouts, any quest.
- **Gold:** a year of history on a chart, each character's share.
- **`/retro probe`:** what each reader got, printed and saved in `RetrospectDB.probe`.
