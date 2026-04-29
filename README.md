# Goldeneyes

**A robust Mudlet ledger for Achaean hunting parties.**

Goldeneyes is an automated gold tracking and distribution utility designed for Achaea. It seamlessly manages party splits, auto-looting, and hidden reward math, allowing hunting leaders to focus on combat instead of complex accounting.

**Author:** Solina
**Version:** 1.1.0

---

## ✨ Features

* **Smart Party Management:** Automatically add your party members, track their shares, and even pause tracking if someone steps away.
* **Interactive UI Prompts:** Clickable on-screen links appear when players join or leave your party, or when untracked gold is handed to you.
* **Split Strategies:** Choose between an `Even` split (equal shares regardless of join time) or a `Fair` split (prorated based on participation).
* **Smarter Payouts & Safety:** Distribution calculates the exact hunt yield to withdraw, sparing your personal gold, and automatically resets the tracker afterward to prevent double-paying.
* **Math Checks (Hidden Rewards):** The unique `goldeneyes check` feature takes a snapshot of your physical wealth and compares it to your ledger to automatically detect and distribute hidden quest rewards.
* **State Persistence (JSON):** Goldeneyes automatically saves your data and settings to a `Goldeneyes_Profile.json` file on exit/disconnect, so you never lose your hunt data to a crash.
* **Auto-Looting & Handover:** Automatically scoop gold into your designated container, or automatically hand it over to the designated party accountant.

---

## 📥 Installation

1. Download the latest release from the [GitHub Repository](https://github.com/solina-the-hawk/goldeneyes/).
2. Extract the files.
3. Place `Goldeneyes-Core.lua` inside a `Goldeneyes` folder within your Mudlet Home Directory. The path should look like this: `[Mudlet Home Directory]/Goldeneyes/Goldeneyes-Core.lua`.
4. Open Mudlet, go to **Package Manager**, and install `Goldeneyes.xml`.
5. Goldeneyes will automatically load the core Lua file.

---

## 🚀 Quick Start

All commands can be prefixed with either `goldeneyes` or `gold`.

* `gold help`: View the full list of commands and settings.
* `gold party`: Automatically scan and add your current party members to the ledger.
* `gold`: Displays the main tracking ledger and your current configuration.
* `gold distribute [channel]`: Withdraws only the needed gold from your container, shares it, and auto-resets the tracker.
* `gold reset confirm`: Safely wipes all current tracking data to start a fresh hunt.
* `gold profile save`: Exports your current configuration to the JSON profile.

---

## 🛠️ Advanced: The Snapshot System

Some quests or strongboxes deposit gold directly into your inventory without an obvious trigger. Goldeneyes can find it:
1. Ensure your baseline is set. If not, the script will prompt you when you first type `gold check`.
2. After turning in a quest or opening a box, type `gold check`.
3. Goldeneyes will capture your `show gold` output, calculate the difference between your physical wealth and the ledger, and automatically add any hidden profits to the pot!
