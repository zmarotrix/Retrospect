<p align="center">
  <img src=".github/banner.png" alt="Retrospect: your characters, account-wide. What your other characters had, when you last saw them. Powered by NorgannonDB." width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/WoW%20Forever-1.60.1-e7c66c?style=flat-square" alt="WoW Forever 1.60.1">
  <img src="https://img.shields.io/badge/status-not%20yet%20played%20in%20game-ffb35c?style=flat-square" alt="Status: not yet played in game">
  <img src="https://img.shields.io/badge/part%20of-NorgannonDB%20suite-2b2333?style=flat-square" alt="Part of the NorgannonDB suite">
</p>

> [!WARNING]
> **Very much a work in progress.** This first build has passed its test harness but hasn't been
> played in the game yet, so expect things to need fixing. Bug reports and feedback are welcome in
> [Issues](../../issues). `/retro probe` says what each part can read on your client.

**Retrospect remembers what your other characters had when you last saw them.** Bags, bank, gear,
gold, mail, auctions, recipes, reputations, quests and lockouts, across every character on your
account, in one window.

## What it does

### One rail, one scope
Pick **All characters** or one character on the left. The tabs and the search follow.

### Today
One list with real deadlines instead of a calendar: mail about to expire, auctions sold, money
waiting, profession cooldowns, lockouts ending, bags nearly full, characters fully rested. Facts
only, never "do this next". If something can't wait, one quiet chat line says so at login.

### Honest about what it knows
Every block says when it was last seen. "Never opened" is different from "empty", and the Today page
lists what the totals could be missing.

### Who has it
- **Search every character's** bags, banks, mail, auctions and gear, with place filters and a
  **Can be mailed** filter that hides soulbound items.
- **Mail you send between your characters** counts at once, as "on its way".
- **Tooltips** say who holds an item and where, who can learn a recipe, and which of your characters
  needs an item for a quest. Quest tooltips say who has done it and who is on it.

### Compare
One grid, every character a column: **reputation**, **professions** with recipe counts,
**attunements and keys** built from NorgannonDB rather than a hand-kept list, **lockouts**, and any
**one quest** you type.

### Gold
One value per character per day, kept for a year, on a chart with each character's share.

### One character
Overview, Bags & Bank, Gear, Mail & Auctions, Quests (with "has this character done it?"),
Professions (every recipe, known or not) and Reputation.

## The NorgannonDB suite

|   | Add-on | |
|:-:|---|---|
| <img src="https://raw.githubusercontent.com/zmarotrix/NorgannonDB_Core/main/.github/suite/clairvoyance.png" width="36"> | **[Clairvoyance](https://github.com/zmarotrix/Clairvoyance)** | Quest helper: your objectives on the map, minimap and compass, and a modern tracker |
| <img src="https://raw.githubusercontent.com/zmarotrix/NorgannonDB_Core/main/.github/suite/oracle.png" width="36"> | **[Oracle](https://github.com/zmarotrix/Oracle)** | Dungeon and zone atlas: maps, bosses, loot, zones and professions |
| <img src="https://raw.githubusercontent.com/zmarotrix/NorgannonDB_Core/main/.github/suite/retrospect.png" width="36"> | **Retrospect** | Your characters, account-wide: what each one has, knows and has waiting |
| <img src="https://raw.githubusercontent.com/zmarotrix/NorgannonDB_Core/main/.github/suite/norgannondb.png" width="36"> | **[NorgannonDB](https://github.com/zmarotrix/NorgannonDB)** | The open game database underneath, with **NorgannonDB Core**, the shared runtime |
| <img src="https://raw.githubusercontent.com/zmarotrix/NorgannonDB_Core/main/.github/suite/collector.png" width="36"> | **[NorgannonDB Collector](https://github.com/zmarotrix/NorgannonDBCollector)** | Help map Azeroth: improves the database while you play |

## Getting started

1. Download **Retrospect**, **[NorgannonDB](https://github.com/zmarotrix/NorgannonDB)** and
   **[NorgannonDB Core](https://github.com/zmarotrix/NorgannonDB_Core)** (on each page: **Code →
   Download ZIP**).
2. Extract them into your WoW Forever `Interface/AddOns` folder, and remove the `-main` that
   GitHub adds to each folder's name, so you end up with `Retrospect`, `NorgannonDB` and
   `NorgannonDB_Core`.
3. Log in on each character once. Open the bank, a mailbox, the auction house and each profession
   once per character, so Retrospect can read them.
4. Type **`/retro`**, or click Retrospect's minimap button.

| Command | What it does |
|---|---|
| `/retro` | open or close Retrospect |
| `/retro arcanite` | who has it: search every character |
| `/retro probe` | what each part can read on this client |
| `/retro settings` | the settings (also under NorgannonDB in the game's Settings) |

Saved data belongs to one WoW account. If you have two accounts on one login, each sees its own
characters; merging them isn't in this version.

---

## Technical details

<details>
<summary>How it works</summary>

- **Private by design.** Nothing is sent anywhere; there are no comms in this version.
- **Saved data** is in `RetrospectDB`, per WoW account. Items are packed into one string per
  container, and id lists into base-36 differences, so a character costs little. The harness budgets
  30 full characters.
- **Nothing replaced.** Events and post-hooks only. Scans are coalesced and wait for combat to end;
  secret values are skipped; a call the client lacks counts as no answer.
- **Built on NorgannonDB Core 1.15**, including its known-recipes scan, shared with the rest of the
  suite. Requires NorgannonDB 1.4.

</details>

Retrospect is by Maro. All rights reserved; see [LICENSE](LICENSE).
