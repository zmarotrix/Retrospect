# Changelog

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
