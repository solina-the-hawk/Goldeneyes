# Goldeneyes

**A robust Mudlet ledger for Achaean hunting parties.**

Goldeneyes is an automated gold tracking and distribution utility designed for Achaea. It seamlessly manages party splits, auto-looting, and hidden reward math, allowing hunting leaders to focus on combat instead of complex accounting.

**Author:** Solina  
**Version:** 1.4.0

---

## Screenshots
<img width="814" height="443" alt="image" src="https://github.com/user-attachments/assets/f4688f15-4b52-4555-848b-c6216aa83120" />

---

## ✨ Features

* **Interactive Setup Dashboard:** Type `gold setup` for a clickable, easy-to-use configuration menu to get your ledger ready in seconds.
* **Smart Party Management:** Automatically add your party members, track their shares, and even pause tracking if someone steps away.
* **Organizational Share & Banking:** Easily set a percentage cut for your City, House, or Order. Goldeneyes tracks these debts safely and can automatically execute bank deposits (gold org deposit) when you reach a bank room!
* **Smart 3-Tier Container System:** Keep your gold safe from Achaean thieves and perfectly organized. Define custom storage sequences for your Group stash, Personal wallet, and Org tax containers. Supports nested anti-theft sequences (e.g., get pouch from pack / put <amount> gold in pouch / put pouch in pack).
* **Interactive UI Prompts:** Clickable on-screen links appear when players join or leave your party, or when untracked gold is handed to you.
* **Split Strategies:** Choose between an `Even` split (equal shares regardless of join time) or a `Fair` split (prorated based on participation).
* **Smarter Payouts & Safety:** Distribution calculates the exact hunt yield to withdraw, sparing your personal gold, and automatically resets the tracker afterward to prevent double-paying.
* **Math Checks (Hidden Rewards):** The unique `goldeneyes check` feature takes a snapshot of your physical wealth and compares it to your ledger to automatically detect and distribute hidden quest rewards.
* **State Persistence (JSON):** Goldeneyes automatically saves your data and settings to a `Goldeneyes_Profile.json` file on exit/disconnect, so you never lose your hunt data to a crash.
* **Auto-Looting & Handover:** Automatically scoop gold into your designated container, or automatically hand it over to the designated party accountant.
* **Collision-Free Auto-Looting:** Goldeneyes uses a reactive state machine to queue loot commands perfectly, meaning it plays flawlessly alongside aggressive combat scripts (like Battlesense) without their queue-clearing commands stepping on each other's toes.
* **Smart Inversions:** Need walking-around money? Type gold pull 500 and Goldeneyes will automatically invert your custom personal deposit sequence to safely withdraw the gold.

---

## 📥 Installation

1. Download the latest release from the [GitHub Repository](https://github.com/solina-the-hawk/goldeneyes/).
2. Install the Mudlet Package (You're done!)

OR
1. Create a new script in Mudlet called Goldeneyes Core, paste the contents of `Goldeneyes-Core.lua` inside and save it. (You're done!)

---

## 🚀 Quick Start

All commands can be prefixed with either `goldeneyes` or `gold`.

* `gold setup`: Launch the interactive quick-start dashboard.
* `gold help`: View the categorized help menu (e.g., gold help org, gold help party).
* `gold groupscan`: Automatically scan and add your current party/group/intrepid members to the ledger.
* `gold`: Displays the main tracking ledger and your current configuration.
* `gold` org <name|off> <%> [pot|personal]: Set an organizational tax, or disable it.
* `gold` container <group|personal|org> <sequence>: Set a container sequence using <amount> as a placeholder.
* `gold` stash [group|personal]: Instantly stow loose gold into the specified container.
* `gold` pull <amount>: Automatically withdraws gold using your personal container sequence.
* `gold` org deposit [note]: Automatically deposits held org funds into the bank and clears the ledger.
* `gold` distribute [channel]: Withdraws the exact hunt yield, staggers payouts safely, and auto-resets the tracker.
* `gold` report [channel]: Announces totals to party, intrepid, say, or individually via tell.

---

## 🛠️ Advanced: The Snapshot System

Some quests or strongboxes deposit gold directly into your inventory without an obvious trigger. Goldeneyes can find it:
1. Ensure your baseline is set. If not, the script will prompt you when you first type `gold check`.
2. After turning in a quest or opening a box, type `gold check`.
3. Goldeneyes will capture your `show gold` output, calculate the difference between your physical wealth and the ledger, and automatically add any hidden profits to the pot!
