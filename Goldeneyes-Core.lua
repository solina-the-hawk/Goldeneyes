-- =========================================================================
-- GOLDENEYES: Gold Tracking & Distribution Utility
-- A robust Mudlet ledger for Achaean hunting parties.
-- Author: Solina (https://github.com/solina-the-hawk/goldeneyes/)
-- Version: 1.1.0
-- =========================================================================
goldeneyes = goldeneyes or {}
goldeneyes.settings = {}

-- =========================================================== --
-- SECTION 1: INITIALIZATION & DEFAULTS                        --
-- =========================================================== --

-- Base settings
goldeneyes.settings.commandseparator = ";"
goldeneyes.settings.getalias = false
goldeneyes.settings.container = goldeneyes.settings.container or "pouch"
goldeneyes.settings.promptfunction = false

-- Colors
color_table.geGold = {255,215,0}
color_table.geSilver = {160,160,160}

-- Core Data Structures (These will be overwritten by load() if a save exists)
if goldeneyes.enabled == nil then goldeneyes.enabled = true end
goldeneyes.pickup = goldeneyes.pickup or true
goldeneyes.names = goldeneyes.names or {}
goldeneyes.paused = goldeneyes.paused or {}
goldeneyes.total = goldeneyes.total or 0
goldeneyes.org = goldeneyes.org or {name = false, percent = 0, gold = 0}
goldeneyes.starttime = goldeneyes.starttime or os.time()
goldeneyes.ledger = goldeneyes.ledger or {}
goldeneyes.unknown_ledger = goldeneyes.unknown_ledger or {}
goldeneyes.snapshot = goldeneyes.snapshot or {hand = 0, bank = 0, phase = nil}
goldeneyes.baseline = goldeneyes.baseline or {hand = 0, bank = 0, set = false}
goldeneyes.expenses = goldeneyes.expenses or 0
goldeneyes.autohandover = goldeneyes.autohandover or false
goldeneyes.reset_pending = false
goldeneyes.split_strategy = goldeneyes.split_strategy or "even"
goldeneyes.party_alerts = goldeneyes.party_alerts or true
goldeneyes.pending_gold = goldeneyes.pending_gold or {}

local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
goldeneyes.accountant = goldeneyes.accountant or my_name

-- =========================================================== --
-- SECTION 2: UTILITIES & FILE I/O                             --
-- =========================================================== --

-- Counts elements in a table
goldeneyes.count = function(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Standardized script echo
goldeneyes.echo = function(x)
    cecho("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: " .. x .. "<reset>")
end

-- Formats numbers with commas (e.g., 10000 -> 10,000)
goldeneyes.format = function(amount)
    if not amount then return "0" end
    local formatted = tostring(math.floor(tonumber(amount) or 0))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k == 0) then break end
    end
    return formatted
end

-- Apply general settings
goldeneyes.getsettings = function()
    if goldeneyes.settings then
        goldeneyes.cs = goldeneyes.settings.commandseparator or ";"
        goldeneyes.getalias = goldeneyes.settings.getalias
        goldeneyes.container = goldeneyes.settings.container or "pack"
        goldeneyes.showprompt = goldeneyes.settings.promptfunction or function() end
    end
end
goldeneyes.getsettings() -- Execute immediately

-- Returns cross-platform compatible save path
goldeneyes.get_save_path = function()
    return getMudletHomeDir() .. "/Goldeneyes-Data.lua"
end

-- Writes current state to file to survive crashes/disconnects
goldeneyes.save = function()
    local save_path = goldeneyes.get_save_path()
    local data = {
        enabled = goldeneyes.enabled,
        pickup = goldeneyes.pickup,
        names = goldeneyes.names,
        paused = goldeneyes.paused,
        total = goldeneyes.total,
        org = goldeneyes.org,
        ledger = goldeneyes.ledger,
        unknown_ledger = goldeneyes.unknown_ledger,
        baseline = goldeneyes.baseline,
        expenses = goldeneyes.expenses,
        autohandover = goldeneyes.autohandover,
        split_strategy = goldeneyes.split_strategy,
        party_alerts = goldeneyes.party_alerts,
        accountant = goldeneyes.accountant,
        starttime = goldeneyes.starttime,
        container = goldeneyes.container
    }
    table.save(save_path, data)
end

-- Restores state from file
goldeneyes.load = function()
    local save_path = goldeneyes.get_save_path()
    if io.exists(save_path) then
        local data = {}
        table.load(save_path, data)
        
        goldeneyes.enabled = data.enabled
        if goldeneyes.pickup == nil then goldeneyes.pickup = data.pickup end
        goldeneyes.names = data.names or goldeneyes.names
        goldeneyes.paused = data.paused or goldeneyes.paused
        goldeneyes.total = data.total or goldeneyes.total
        goldeneyes.org = data.org or goldeneyes.org
        goldeneyes.ledger = data.ledger or goldeneyes.ledger
        goldeneyes.unknown_ledger = data.unknown_ledger or goldeneyes.unknown_ledger
        goldeneyes.baseline = data.baseline or goldeneyes.baseline
        goldeneyes.expenses = data.expenses or goldeneyes.expenses
        if data.autohandover ~= nil then goldeneyes.autohandover = data.autohandover end
        goldeneyes.split_strategy = data.split_strategy or goldeneyes.split_strategy
        if data.party_alerts ~= nil then goldeneyes.party_alerts = data.party_alerts end
        goldeneyes.accountant = data.accountant or goldeneyes.accountant
        goldeneyes.starttime = data.starttime or goldeneyes.starttime
        goldeneyes.container = data.container or goldeneyes.container
    end
end

-- =========================================================== --
-- SECTION 3: LEDGER & MATH LOGIC                              --
-- =========================================================== --

-- Calculates current shares based on active strategy
goldeneyes.get_shares = function()
    local shares = {}
    local count = goldeneyes.count(goldeneyes.names)
    if count == 0 then return shares end
    
    if goldeneyes.split_strategy == "even" then
        local net_pool = goldeneyes.total - goldeneyes.org.gold
        local even_share = net_pool / count
        for k, _ in pairs(goldeneyes.names) do
            shares[k] = even_share
        end
    else 
        for k, v in pairs(goldeneyes.names) do
            shares[k] = v
        end
    end
    return shares
end

-- Manually add gold to the total pool
goldeneyes.plus = function(amt, noecho)
    local original_amt = amt
    local x = goldeneyes

    if x.org.name then
        x.org.gold = x.org.gold + original_amt * (x.org.percent/100)
        amt = original_amt * ( 1 - x.org.percent/100)
    end

    local num = goldeneyes.count(x.names)
    if num > 0 then
        local split_share = amt / num
        for k, v in pairs (x.names) do
            x.names[k] = v + split_share
        end
    end

    x.total = x.total + original_amt
    if not noecho then x.echo("<geGold>" .. goldeneyes.format(original_amt) .. " <geSilver>gold added.") end
    x.showprompt()
end

-- Manually subtract gold from the total pool
goldeneyes.minus = function(amt)
    local x = goldeneyes
    local i = amt
    if x.org.name then
        x.org.gold =  x.org.gold - i * (x.org.percent/100)
        i = i * ( 1 - x.org.percent/100)
    end

    local num = x.count(x.names)
    if num > 0 then
        local split_share = i / num
        for k, v in pairs (x.names) do x.names[k] = v - split_share end
    end

    x.total = x.total - amt
    x.echo("<geGold>" .. goldeneyes.format(amt) .. " <geSilver>gold removed.")
    x.showprompt()
end

-- Quick external math calculator
goldeneyes.calc = function(amount, people)
    if type(amount) == "string" then amount = amount:gsub(",", "") end
    
    amount = tonumber(amount)
    people = tonumber(people)

    if not amount or not people or people <= 0 then
        cecho("\n<geSilver>Usage: <geGold>goldeneyes calc <amount> <number of people>\n")
        return
    end

    local share = math.floor(amount / people)
    local remainder = amount % people

    local msg = string.format("Splitting <geGold>%s<geSilver> gold among <geGold>%d<geSilver> people results in <geGold>%s<geSilver> gold each.", 
        goldeneyes.format(amount), people, goldeneyes.format(share))

    if remainder > 0 then
        msg = msg .. string.format(" <geSilver>(Remainder: <orange>%s<geSilver>)", goldeneyes.format(remainder))
    end
    goldeneyes.echo(msg)
end

-- Log known expenses (e.g. shop purchases) for the snapshot checker
goldeneyes.add_expense = function(amt)
    if goldeneyes.enabled then
        goldeneyes.expenses = goldeneyes.expenses + amt
        goldeneyes.echo("Tracked expense of <orange>" .. goldeneyes.format(amt) .. "<geSilver> gold.")
    end
end

-- =========================================================== --
-- SECTION 4: PARTY & TRACKER MANAGEMENT                       --
-- =========================================================== --

-- Add an individual to the split
goldeneyes.add = function(name)
    name = name:lower()
    if goldeneyes.names[name] == nil then
        goldeneyes.echo("Added <geGold>" .. name:title() .. " <geSilver>to tracking.")
        goldeneyes.names[name] = 0
    else
        goldeneyes.echo("<geGold>" .. name:title() .. " <geSilver>is already being tracked.")
    end
    goldeneyes.showprompt()
end

-- Remove an individual from the split
goldeneyes.remove = function(name)
    name = name:lower()
    if goldeneyes.names[name] ~= nil then
        goldeneyes.echo("Removed <geGold>" .. name:title() .. " <geSilver>from tracking.")
        goldeneyes.echo("<geGold>" .. name:title() .. " <geSilver>was at <geGold>" .. goldeneyes.format(goldeneyes.names[name]) .. " <geSilver>gold.")
        goldeneyes.names[name] = nil
    else
        goldeneyes.echo("<geGold>" .. name .. " <geSilver>is not currently being tracked.")
    end
    goldeneyes.showprompt()
end

-- Pause a tracked member (preserves their current share)
goldeneyes.pause = function(name)
    name = name:lower()
    if goldeneyes.names[name] ~= nil then
        goldeneyes.echo("Gold tracking for <geGold>" .. name:title() .. " <geSilver>paused.")
        goldeneyes.paused[name] = goldeneyes.names[name]
        goldeneyes.names[name] = nil
    end
    goldeneyes.showprompt()
end

-- Unpause a tracked member
goldeneyes.unpause = function(name)
    name = name:lower()
    if goldeneyes.paused[name] then
        goldeneyes.echo("Gold tracking for <geGold>" .. name:title() .. " <geSilver>unpaused.")
        goldeneyes.names[name] = goldeneyes.paused[name]
        goldeneyes.paused[name] = nil
    end
    goldeneyes.showprompt()
end

-- Trigger an in-game scan for Party, Group, and Intrepid members
goldeneyes.scan_group = function()
    goldeneyes.echo("Scanning party, group, and intrepid members...")
    -- Fire all three commands; the game will just ignore/error the ones not in use!
    send("party members", false)
    send("group", false)
    send("intrepid", false)

    goldeneyes.scan_triggers = goldeneyes.scan_triggers or {}

    -- 1. Catch standard Party members and indented Group members
    table.insert(goldeneyes.scan_triggers, tempRegexTrigger("^\\s+([A-Z][a-z]+)", function()
        local name = matches[2]
        if name ~= "Party" and name ~= "The" and name ~= "Your" then goldeneyes.add(name) end
    end))

    -- 2. Catch single group followers or leaders
    table.insert(goldeneyes.scan_triggers, tempRegexTrigger("^You are following ([A-Z][a-z]+)\\.", function()
        goldeneyes.add(matches[2])
    end))
    table.insert(goldeneyes.scan_triggers, tempRegexTrigger("^([A-Z][a-z]+) is following you\\.", function()
        goldeneyes.add(matches[2])
    end))

    -- 3. Catch Intrepid Leader
    table.insert(goldeneyes.scan_triggers, tempRegexTrigger("^Leader\\s*:\\s*([A-Z][a-z]+)", function()
        goldeneyes.add(matches[2])
    end))

    -- 4. Catch Intrepid Members (comma separated list)
    table.insert(goldeneyes.scan_triggers, tempRegexTrigger("^Members\\s*:\\s*(.*)", function()
        local members_str = matches[2]
        for name in string.gmatch(members_str, "([A-Z][a-z]+)") do
            if name ~= "And" and name ~= "You" then goldeneyes.add(name) end
        end
    end))

    -- Clean up triggers after 1.5 seconds
    tempTimer(1.5, function()
        if goldeneyes.scan_triggers then
            for _, id in ipairs(goldeneyes.scan_triggers) do killTrigger(id) end
            goldeneyes.scan_triggers = {}
        end
        goldeneyes.echo("Group scan complete.")
        goldeneyes.showprompt()
    end)
end

-- Accept untracked gold handed to you (via interactive prompt)
goldeneyes.accept_pending = function(name)
    local name_key = name:lower()
    local amount = goldeneyes.pending_gold[name_key]
    
    if amount then
        goldeneyes.add(name)
        goldeneyes.plus(amount)
        goldeneyes.pending_gold[name_key] = nil
    else
        goldeneyes.echo("No pending gold found for " .. name:title() .. ".")
    end
end

-- Ignore untracked gold handed to you
goldeneyes.ignore_pending = function(name)
    local name_key = name:lower()
    if goldeneyes.pending_gold[name_key] then
        goldeneyes.pending_gold[name_key] = nil
        goldeneyes.echo("Ignored gold from " .. name:title() .. ".")
    end
end

-- =========================================================== --
-- SECTION 5: INVENTORY & LOOT MANAGEMENT                      --
-- =========================================================== --

-- Set physical container for gold storage
goldeneyes.setcontainer = function(name)
    goldeneyes.container = name
    goldeneyes.echo("Loot container set to: <geGold>" .. name)
    goldeneyes.save()
end

-- Move all loose gold to container
goldeneyes.stash = function()
    local cont = goldeneyes.container or "pack"
    send("queue add eqbal put gold in " .. cont)
    goldeneyes.echo("Attempting to stash gold in your <geGold>" .. cont)
end

-- Toggle automatic scooping
goldeneyes.togglepickup = function(val)
    local state = val:lower() == "on"
    goldeneyes.pickup = state
    goldeneyes.echo("Auto-pickup is now " .. (state and "<green>ENABLED<geSilver>" or "<red>DISABLED<geSilver>"))
end

-- Toggle sending picked up gold to the accountant
goldeneyes.toggle_handover = function(val)
    if val == "on" then
        goldeneyes.autohandover = true
        goldeneyes.echo("Auto-Handover <green>ENABLED<geSilver>. I will give gold to " .. goldeneyes.accountant)
    else
        goldeneyes.autohandover = false
        goldeneyes.echo("Auto-Handover <red>DISABLED<geSilver>.")
    end
end

-- Process incoming gold pick-ups
goldeneyes.handle_loot = function(amt)
    if not goldeneyes.enabled then return end
    local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
    local my_name_lower = my_name:lower()
    local acc = goldeneyes.accountant or my_name
    local cont = goldeneyes.container or "pack"

    -- Always add to our local total so the display is useful for everyone!
    goldeneyes.plus(amt, true)

    if acc:lower() == my_name_lower then
        goldeneyes.echo("Gold added to ledger. New total is <geGold>" .. goldeneyes.format(goldeneyes.total) .. "<geSilver> gold.")
        
        if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
            send("queue add eqbal put " .. amt .. " gold in " .. cont, false)
        end
    else
        -- We are NOT the accountant. Add to our local debt until we successfully hand it over.
        goldeneyes.ledger[my_name_lower] = (goldeneyes.ledger[my_name_lower] or 0) + amt

        if goldeneyes.autohandover then
            send("queue add eqbal give " .. amt .. " gold to " .. acc)
            goldeneyes.echo("Looted <geGold>"..goldeneyes.format(amt).."<geSilver>. Attempting to hand over to <geGold>"..acc)
        else
            send("pt I picked up " .. goldeneyes.format(amt) .. " gold.")
            goldeneyes.echo("Looted <geGold>"..goldeneyes.format(amt).."<geSilver>. Kept locally (Added to Debt).")
            if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
                send("queue add eqbal put " .. amt .. " gold in " .. cont, false)
            end
        end
    end
end

-- =========================================================== --
-- SECTION 6: SNAPSHOTS & REWARDS (MATH CHECKS)                --
-- =========================================================== --

-- Alias wrapper to set baseline
goldeneyes.start_snapshot = function()
    goldeneyes.set_baseline()
end

-- Execute in-game 'show gold' to establish baseline
goldeneyes.set_baseline = function()
    goldeneyes.baseline.set = false
    goldeneyes.capture_mode = "baseline"
    send("show gold")
end

-- Check physical gold against expected ledger gold
goldeneyes.check_reward = function()
    if not goldeneyes.baseline.set then
        goldeneyes.echo("<yellow>Warning:<geSilver> No baseline established yet. Establishing now. Type <geGold>goldeneyes check<geSilver> after your next reward.")
        goldeneyes.set_baseline()
        return
    end
    goldeneyes.capture_mode = "check"
    send("show gold")
end

-- Process the captured 'show gold' string
goldeneyes.process_gold_capture = function(hand, bank)
    if type(goldeneyes.baseline) ~= "table" then goldeneyes.baseline = {hand = 0, bank = 0, set = false} end
    
    if type(hand) == "string" then hand = tonumber((string.gsub(hand, ",", ""))) end
    if type(bank) == "string" then bank = tonumber((string.gsub(bank, ",", ""))) end
    hand = hand or 0
    bank = bank or 0
    
    if goldeneyes.capture_mode == "baseline" then
        goldeneyes.baseline.hand = hand
        goldeneyes.baseline.bank = bank
        goldeneyes.baseline.total = goldeneyes.total or 0 
        goldeneyes.baseline.set = true
        goldeneyes.echo("Baseline set. Hand: " .. goldeneyes.format(hand) .. ", Bank: " .. goldeneyes.format(bank))
        
    elseif goldeneyes.capture_mode == "check" then
        local wealth_change = (hand + bank) - ((goldeneyes.baseline.hand or 0) + (goldeneyes.baseline.bank or 0))
        local tracked_change = (goldeneyes.total or 0) - (goldeneyes.baseline.total or 0)
        local hidden_profit = wealth_change + goldeneyes.expenses - tracked_change
        
        if hidden_profit > 0 then
            goldeneyes.echo("<orange>Hidden Reward Detected!<geSilver> You gained <geGold>" .. goldeneyes.format(hidden_profit) .. "<geSilver> gold.")
            goldeneyes.plus(hidden_profit)
        elseif hidden_profit < 0 then
             goldeneyes.echo("Math check negative (" .. goldeneyes.format(hidden_profit) .. "). Did you spend gold we missed?")
        else
             goldeneyes.echo("No hidden rewards found (Math is balanced).")
        end
        
        -- Update the baseline for the next check
        goldeneyes.baseline.hand = hand
        goldeneyes.baseline.bank = bank
        goldeneyes.baseline.total = goldeneyes.total
        goldeneyes.expenses = 0 
    end
    goldeneyes.capture_mode = nil
end

-- =========================================================== --
-- SECTION 7: UI & COMMANDS                                    --
-- =========================================================== --

-- Master display layout
goldeneyes.display = function()
    local status = goldeneyes.enabled and "<geGold>enabled" or "<geSilver>disabled"
    local current_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
    local accountant = goldeneyes.accountant or current_name
    local role = (accountant:lower() == current_name:lower()) and "<green>(Me)" or "<yellow>(" .. accountant .. ")"
    local strat_text = (goldeneyes.split_strategy == "even") and "<green>Even" or "<yellow>Fair"
    local cont = goldeneyes.container or "pack"

    local elapsed = os.time() - goldeneyes.starttime
    if elapsed < 1 then elapsed = 1 end
    local gph = math.floor((goldeneyes.total / elapsed) * 3600)

    cecho("\n<geGold>Goldeneyes Gold Tracking Ledger\n")
    cecho("<geSilver>  Enter <geGold>goldeneyes help <geSilver>for commands and settings.\n\n")
    cecho("  <geSilver>Gold Tracking: <green>" .. status .. "\n")
    cecho("  <geSilver>Accountant: " .. role .. "\n")
    cecho("  <geSilver>Strategy: " .. strat_text .. "\n")
    cecho("  <geSilver>Container:  <geGold>" .. cont .. "\n\n")
    
    cecho("  <geSilver>Gold Collected: <geGold>" .. goldeneyes.format(goldeneyes.total) .. "\n")
    cecho("  <geSilver>Gold per hour:  <geGold>" .. goldeneyes.format(gph) .. "\n")

    if goldeneyes.org.name then
        cecho("\n  <geSilver>" .. string.format ("%14s", goldeneyes.org.name:title()) ..
               ": <geGold>" .. string.format ("%-8s", goldeneyes.format(goldeneyes.org.gold)) ..
               " <geSilver>(" .. goldeneyes.org.percent ..  "%)\n")
    end

    if goldeneyes.count(goldeneyes.names) > 0 then 
        cecho("\n  <orange>Currently Tracking:\n") 
    end
    
    local shares = goldeneyes.get_shares()
    for k, v in pairs(shares) do
        cecho("  <geSilver>" .. string.format("%14s", k:title()) .. ": <geGold>" .. goldeneyes.format(v) .. "\n")
    end

    local ledger_count = goldeneyes.count(goldeneyes.ledger)
    local unknown_count = goldeneyes.count(goldeneyes.unknown_ledger)

    if ledger_count > 0 or unknown_count > 0 then
        cecho("\n<orange>Gold Held by Others:\n")
        local all_holders = {}
        for k,v in pairs(goldeneyes.ledger) do all_holders[k] = true end
        for k,v in pairs(goldeneyes.unknown_ledger) do all_holders[k] = true end

        for k, _ in pairs(all_holders) do
            local debt = goldeneyes.ledger[k] or 0
            local unknown = goldeneyes.unknown_ledger[k] or 0
            local str = string.format("  <geSilver>%14s: ", k:title())

            if debt > 0 then str = str .. "<orange>" .. goldeneyes.format(debt) .. " gold " end
            if unknown > 0 then str = str .. "<red>(+" .. unknown .. " unknown piles!)" end
            cecho(str .. "\n")
        end
    end
    cecho("<reset>\n")
    goldeneyes.showprompt()
end

-- Help menu
goldeneyes.help = function()
    cecho("\n<geGold>Goldeneyes Gold Tracking Ledger - Help Information\n")
    cecho("<geSilver>Commands work with <geGold>goldeneyes<geSilver> or <geGold>gold<geSilver>\n")
    cecho("<geSilver>----------------------------------------------------------------------\n")
    cecho("<geGold>BASIC CONTROLS\n")
    cecho("  <geGold>goldeneyes <on|off>             <geSilver>- Turn tracker on/off.\n")
    cecho("  <geGold>goldeneyes reset                <geSilver>- Reset all totals (enter twice to confirm).\n")
    cecho("  <geGold>goldeneyes report [channel]     <geSilver>- Announce totals (Channels: party, intrepid, say).\n")
    cecho("\n<geGold>GROUP\n")
    cecho("  <geGold>goldeneyes strategy <even|fair> <geSilver>- Set split method (Default: even).\n")
    cecho("  <geGold>goldeneyes group                <geSilver>- Auto-add party, group, and intrepid members.\n")
    cecho("  <geGold>goldeneyes add <name>           <geSilver>- Add a person to the split list.\n")
    cecho("  <geGold>goldeneyes remove <name>        <geSilver>- Remove a person from the list.\n")
    cecho("  <geGold>goldeneyes pause <name>         <geSilver>- Pause tracking for a member.\n")
    cecho("  <geGold>goldeneyes unpause <name>       <geSilver>- Resume tracking for a member.\n")
    cecho("\n<geGold>ACCOUNTING\n")
    cecho("  <geGold>goldeneyes alerts <on|off>      <geSilver>- Toggle clickable party join/leave prompts.\n")
    cecho("  <geGold>goldeneyes accountant <name>    <geSilver>- Designate the collector (Default: You).\n")
    cecho("  <geGold>goldeneyes autohandover <on|off><geSilver>- Automatically give loot to collector.\n")
    cecho("\n<geGold>LOOT & AUTOMATION\n")
    cecho("  <geGold>goldeneyes autoloot <on|off>    <geSilver>- Toggle auto-looting.\n")
    cecho("  <geGold>goldeneyes container <name>     <geSilver>- Set gold container (e.g., 'pack').\n")
    cecho("  <geGold>goldeneyes stash                <geSilver>- Move all carried gold to container.\n")
    cecho("  <geGold>goldeneyes distribute [channel] <geSilver>- Empty container and share gold.\n")
    cecho("\n<geGold>ADVANCED\n")
    cecho("  <geGold>goldeneyes calc <amt> <#>       <geSilver>- Quick math to split an amount of gold.\n")
    cecho("  <geGold>goldeneyes check                <geSilver>- Capture 'Show Gold' to find hidden rewards.\n")
    cecho("  <geGold>goldeneyes plus <amount>        <geSilver>- Manually add to Total.\n")
    cecho("  <geGold>goldeneyes minus <amount>       <geSilver>- Manually subtract from Total.\n")
    goldeneyes.showprompt()
end

-- Announce the current progress
goldeneyes.announce = function(channel)
    channel = channel and channel:lower() or "party"
    local cmd, message = "pt", ""
    
    if channel == "intrepid" then
        cmd = "it"
        message = "We have collected a total of " .. goldeneyes.format(goldeneyes.total) .. " gold so far."
    elseif channel == "say" then
        cmd = "say"
        message = "By my calculations, we have collected a total of " .. goldeneyes.format(goldeneyes.total) .. " gold sovereigns thus far."
    else
        cmd = "pt"
        message = "We have collected a total of " .. goldeneyes.format(goldeneyes.total) .. " gold so far."
    end
    send(cmd .. " " .. message)
end

-- Change split methodology
goldeneyes.set_strategy = function(strat)
    strat = strat and strat:lower() or "even"
    if strat == "even" or strat == "fair" then
        goldeneyes.split_strategy = strat
        goldeneyes.echo("Split strategy set to: <geGold>" .. strat:title())
        cecho("\n<geGold>Even <geSilver>split will divide the total gold pool equally among members at distribution time, regardless of when a member joined.\n")
        cecho("\n<geGold>Fair <geSilver>split will distribute gold based on when each person joined the party, at distribution time.\n")
        goldeneyes.showprompt()
    else
        cecho("\n<geSilver>Usage: <geGold>goldeneyes strategy <even|fair>")
    end
end

-- Designate the collector
goldeneyes.set_accountant = function(name)
    goldeneyes.accountant = name:title()
    goldeneyes.echo("Collector set to <geGold>" .. name)
    goldeneyes.showprompt()
end

-- Toggle click-to-add UI alerts
goldeneyes.togglealerts = function(val)
    local state = val:lower() == "on"
    goldeneyes.party_alerts = state
    goldeneyes.echo("Party alerts are now " .. (state and "<green>ENABLED<geSilver>" or "<red>DISABLED<geSilver>"))
end

-- Toggle the entire tracker
goldeneyes.toggle = function(enabled)
    local state = enabled:lower() == "on"
    goldeneyes.enabled = state

    if state and goldeneyes.count(goldeneyes.names) == 0 and gmcp.Char and gmcp.Char.Name then
        goldeneyes.add(gmcp.Char.Name.name:lower())
    end
    goldeneyes.echo("tracking " .. (state and "<geGold>enabled" or "<geSilver>disabled"))
    goldeneyes.showprompt()
end

-- Double-tap reset logic
goldeneyes.reset = function()
    if goldeneyes.reset_pending then
        goldeneyes.confirm_reset()
        goldeneyes.save()
        if goldeneyes.reset_timer then killTimer(goldeneyes.reset_timer) end
        goldeneyes.reset_pending = false
    else
        goldeneyes.reset_pending = true
        cecho("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: <red>WARNING!<geSilver> This will wipe ALL data (Total: " .. goldeneyes.format(goldeneyes.total) .. ").\n")
        cecho("<geSilver>Type <geGold>goldeneyes reset<geSilver> again within 6 seconds to confirm.\n")
        goldeneyes.reset_timer = tempTimer(6, function()
            goldeneyes.reset_pending = false
            cecho("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: Reset cancelled.\n")
        end)
    end
end

-- Wipes the memory arrays
goldeneyes.confirm_reset = function()
    goldeneyes.names = {}
    goldeneyes.paused = {}
    goldeneyes.ledger = {}
    goldeneyes.unknown_ledger = {}
    goldeneyes.org = {name = false, percent = 0, gold = 0}
    goldeneyes.total = 0
    goldeneyes.expenses = 0
    goldeneyes.starttime = os.time()
    goldeneyes.pending_gold = {}

    if gmcp.Char and gmcp.Char.Name then goldeneyes.add(gmcp.Char.Name.name) end
    goldeneyes.set_baseline()
    goldeneyes.echo("<red>Tracker has been reset.<reset>")
    goldeneyes.showprompt()
end

-- Final payout command
goldeneyes.distribute = function(channel)
    local cont = goldeneyes.container or "pack"
    
    if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
        send("queue add eqbal get gold from " .. cont)
    end
    
    local shares = goldeneyes.get_shares()
    local members = goldeneyes.count(goldeneyes.names)
    
    channel = channel and channel:lower() or "party"
    local cmd = "pt"
    local message = ""
    local silent = (channel == "none")
    
    if goldeneyes.split_strategy == "even" then
        local single_share = 0
        for _, v in pairs(shares) do single_share = math.floor(v); break end
        
        if channel == "intrepid" then
            cmd = "it"
            message = string.format("Distributing %s gold across %d members. Expected even share: %s gold.", goldeneyes.format(goldeneyes.total), members, goldeneyes.format(single_share))
        elseif channel == "say" then
            cmd = "say"
            message = string.format("I'll distribute our collected %s gold sovereigns now. Split evenly among the %d of us, we should each receive %s gold.", goldeneyes.format(goldeneyes.total), members, goldeneyes.format(single_share))
        else
            cmd = "pt"
            message = string.format("Distributing %s gold across %d members. Expected even share: %s gold.", goldeneyes.format(goldeneyes.total), members, goldeneyes.format(single_share))
        end
    else
        if channel == "intrepid" then
            cmd = "it"
            message = string.format("Distributing %s gold across %d members. Shares are prorated based on hunt participation.", goldeneyes.format(goldeneyes.total), members)
        elseif channel == "say" then
            cmd = "say"
            message = string.format("I'll distribute our collected %s gold sovereigns now across the %d of us, distributed fairly based on when you joined.", goldeneyes.format(goldeneyes.total), members)
        else
            cmd = "pt"
            message = string.format("Distributing %s gold across %d members. Shares are prorated based on hunt participation.", goldeneyes.format(goldeneyes.total), members)
        end
    end
    
    if not silent then
        send(cmd .. " " .. message)
    end

    local delay = 0.5
    for k, v in pairs(shares) do
        if k ~= gmcp.Char.Name.name:lower() then
            v = math.floor(v)
            if v > 0 then 
                tempTimer(delay, function() send("queue add eqbal give " .. v .. " gold to " .. k) end)
                delay = delay + 0.5
            end
        end
    end

    goldeneyes.echo("Distributed gold from <geGold>" .. cont)
    cecho("\n\n<geSilver>Distribution complete. Verify everyone received their share, then type <geGold>goldeneyes reset<geSilver>.\n")
end


-- =========================================================== --
-- SECTION 8: EVENT HANDLERS                                   --
-- =========================================================== --

-- Hooks on user character load to configure initial states
function goldeneyes_login_check()
    if not gmcp or not gmcp.Char or not gmcp.Char.Name then return end
    local my_name = gmcp.Char.Name.name:title()

    if goldeneyes.enabled and goldeneyes.count(goldeneyes.names) == 0 then
        goldeneyes.add(my_name)
    end
    
    if goldeneyes.accountant == "Unknown" or goldeneyes.accountant == "Solina" then
        goldeneyes.accountant = my_name
    end

    if goldeneyes.pickup then
        goldeneyes.echo("Auto-pickup is <geGold>ENABLED<geSilver>.")
    end

    if not goldeneyes.login_prompted and goldeneyes.total > 0 then
        goldeneyes.login_prompted = true
        cecho("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: <yellow>Welcome back! You have an active hunting ledger with " .. goldeneyes.format(goldeneyes.total) .. " gold.<reset>\n")
        cecho("       ")
        cechoLink("<red>[Start Fresh]", "goldeneyes.confirm_reset()", "Wipe all data for a new hunt", true)
        cecho(" <geSilver>| ")
        cechoLink("<green>[Keep Data]", "goldeneyes.echo('Ledger preserved. Type \\'gold\\' to view.')", "Resume previous hunt", true)
        cecho("\n")
    end
end

if goldeneyes.login_handler then killAnonymousEventHandler(goldeneyes.login_handler) end
goldeneyes.login_handler = registerAnonymousEventHandler("gmcp.Char.Name", "goldeneyes_login_check")

-- Save hooks for application exit / game disconnection
if goldeneyes.save_exit_handler then killAnonymousEventHandler(goldeneyes.save_exit_handler) end
goldeneyes.save_exit_handler = registerAnonymousEventHandler("sysExitEvent", "goldeneyes.save")

if goldeneyes.save_dc_handler then killAnonymousEventHandler(goldeneyes.save_dc_handler) end
goldeneyes.save_dc_handler = registerAnonymousEventHandler("sysDisconnectionEvent", "goldeneyes.save")


-- =========================================================== --
-- SECTION 9: DYNAMIC TRIGGERS & ALIASES                       --
-- =========================================================== --

goldeneyes.trigger_ids = goldeneyes.trigger_ids or {}
goldeneyes.alias_ids = goldeneyes.alias_ids or {}

goldeneyes.create_triggers = function()
    -- Clean up existing triggers/aliases to prevent duplicates on reload
    for _, id in pairs(goldeneyes.trigger_ids) do killTrigger(id) end
    for _, id in pairs(goldeneyes.alias_ids) do killAlias(id) end
    goldeneyes.trigger_ids = {}
    goldeneyes.alias_ids = {}

    -- Trigger: Mystery Gold Pickups (Artifacts)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^Some gold falls from the corpse and automatically flies into the hands of (\\w+)\\.", 
    [[
        local name_key = matches[2]:lower()
        if goldeneyes.names[name_key] then
            goldeneyes.unknown_ledger[name_key] = (goldeneyes.unknown_ledger[name_key] or 0) + 1
            cecho(string.format("\n<red>[ALERT]: %s picked up a MYSTERY pile of gold! (Auto-loot artifact detected)", matches[2]))
            cecho("\n<red>       Please ask them how much they got and use 'goldeneyes plus <amount>'.")
        end
    ]]))

    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^.*sovereigns spills from the corpse, flying into the hands of.*", 
    [[
        cecho("\n<red>[ALERT]: Someone's artifact just auto-looted a MYSTERY pile of gold!<reset>")
    ]]))

    -- Trigger: Shop Purchases & Bribes (Expenses)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You pay ([\\d,]+) gold sovereigns\\.$", [[ goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You buy .* for ([\\d,]+) gold\\.$", [[ goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    
    -- Trigger: Gold Given Away (Handover resolution)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You give ([\\d,]+) gold to (\\w+)", 
    [[ 
        local amount = tonumber((matches[2]:gsub(",", "")))
        local target = matches[3]:lower()
        local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"
        
        -- If we successfully gave gold to the accountant, clear it from our local debt
        if goldeneyes.accountant and target == goldeneyes.accountant:lower() then
            if goldeneyes.ledger[my_name] then
                goldeneyes.ledger[my_name] = goldeneyes.ledger[my_name] - amount
                if goldeneyes.ledger[my_name] <= 0 then goldeneyes.ledger[my_name] = nil end
            end
            goldeneyes.echo("Successfully handed over <geGold>" .. goldeneyes.format(amount) .. "<geSilver> to accountant.")
        end
    ]]))

    -- Trigger: Handover Failure (Accountant left room/logged off)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^(?:Ahh, I am truly sorry, but I do not see anyone by that name here\\.|You cannot see that being here\\.|You cannot find anyone by that name here\\.)$", 
    [[
        local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"
        local acc = goldeneyes.accountant and goldeneyes.accountant:lower() or my_name
        
        -- If we have a local debt and we aren't the accountant, a failure message means our handover missed.
        if goldeneyes.autohandover and acc ~= my_name and goldeneyes.ledger[my_name] and goldeneyes.ledger[my_name] > 0 then
            goldeneyes.echo("<red>Handover failed! <geSilver>The accountant isn't here. Stashing gold safely.")
            local cont = goldeneyes.container or "pack"
            if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
                send("queue add eqbal put gold in " .. cont, false)
            end
            -- Note: We intentionally leave the debt in our ledger so the UI reminds us we have it!
        end
    ]]))

    -- Trigger: Gold Picked Up (You)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You (?:pick|scoop) up ([\\d,]+) gold", 
    [[
        local amount = tonumber((matches[2]:gsub(",", "")))
        if amount then goldeneyes.handle_loot(amount) end
    ]]))

    -- Trigger: Gold Dropped (Grab It)
    local grab_script = [[ 
        if goldeneyes.enabled and goldeneyes.pickup then 
            goldeneyes.echo("Scooping loose gold.")
            send("queue add eqbal get gold", false) 
        end 
    ]]
    local grab_regex = "(?:^A.*sovereigns? spills? from the corpse|A pile of golden sovereigns twinkles and gleams\\.|There is.*pile of golden sovereigns here\\.|pile of .*sovereigns?)"
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger(grab_regex, grab_script))

    -- Trigger: Gold Received (Handover/Watchdog Resolution)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^(\\w+) gives you ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if goldeneyes.names[name_key] then
            -- They are tracked, handle normally
            goldeneyes.plus(amount)
            if goldeneyes.ledger[name_key] then
                goldeneyes.ledger[name_key] = goldeneyes.ledger[name_key] - amount
                cecho(string.format("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: %s paid off %s (Remaining: %s).", name, goldeneyes.format(amount), goldeneyes.format(goldeneyes.ledger[name_key])))
                if goldeneyes.ledger[name_key] <= 0 then
                    goldeneyes.ledger[name_key] = nil
                    cecho(string.format("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: %s has settled their debt.", name))
                end
            else
                cecho(string.format("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: Accepted %s gold from %s (No prior debt).", goldeneyes.format(amount), name))
            end
        else
            -- They are NOT tracked. Hold the gold and ask!
            goldeneyes.pending_gold = goldeneyes.pending_gold or {}
            goldeneyes.pending_gold[name_key] = (goldeneyes.pending_gold[name_key] or 0) + amount
            
            cecho(string.format("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: <yellow>Received %s gold from an UNTRACKED person: %s.<reset>\n", goldeneyes.format(amount), name))
            cecho("       ")
            cechoLink("<green>[Add to Tracker & Pot]", 'goldeneyes.accept_pending("' .. name .. '")', "Track " .. name .. " and add " .. goldeneyes.pending_gold[name_key] .. " to pot", true)
            cecho(" <geSilver>| ")
            cechoLink("<red>[Ignore]", 'goldeneyes.ignore_pending("' .. name .. '")', "Ignore this gold", true)
            cecho("\n")
        end
    ]]))

    -- Trigger: Gold Tracking Watchdog (Others)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^(\\w+) (?:picks|scoops) up ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if goldeneyes.names[name_key] then
            goldeneyes.plus(amount, true) -- Silently add to local total so UI matches reality
            goldeneyes.ledger[name_key] = (goldeneyes.ledger[name_key] or 0) + amount
            cecho(string.format("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: <orange>ALERT<geSilver>: <geGold>%s<geSilver> picked up <orange>%s<geSilver> gold!", name, goldeneyes.format(amount)))
        end
    ]]))
    -- 8. Capture Gold (Start of message)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You have [%d,]+ gold sovereign.*", 
    [[
        if goldeneyes.capture_mode then
            -- Start a buffer with the first line
            goldeneyes.gold_buffer = matches[1]

            -- Set a tiny 0.2 second delay to wait for any trailing lines to arrive
            if goldeneyes.gold_capture_timer then killTimer(goldeneyes.gold_capture_timer) end
            goldeneyes.gold_capture_timer = tempTimer(0.2, function()
                local total_hand = 0
                local total_bank = 0

                for amount_str, context in string.gmatch(goldeneyes.gold_buffer, "([%d,]+)%s+gold sovereigns? in([^0-9,]+)") do
                    local clean_amt = tonumber((string.gsub(amount_str, ",", "")))
                    if clean_amt then
                        if string.match(context, "inventory") or string.match(context, "container") then
                            total_hand = total_hand + clean_amt
                        elseif string.match(context, "bank") then
                            total_bank = total_bank + clean_amt
                        end
                    end
                end
                
                goldeneyes.process_gold_capture(total_hand, total_bank)
                goldeneyes.gold_buffer = nil
            end)
        end
    ]]))

    -- 8b. Capture trailing wrapped lines (The Spillover)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^gold sovereigns? in.*", 
    [[
        if goldeneyes.capture_mode and goldeneyes.gold_buffer then
            -- Append the broken line to our buffer
            goldeneyes.gold_buffer = goldeneyes.gold_buffer .. " " .. matches[1]
        end
    ]]))
    
    -- Triggers: Interactive Party Prompts
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You have joined .+'s party\\.$", 
    [[
        if goldeneyes.party_alerts then
            cecho("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: You joined a party. ")
            cechoLink("<green>[Scan Group]", "goldeneyes.scan_group()", "Auto-add party/group to ledger", true)
            cecho(" <geSilver>| ")
            cechoLink("<yellow>[Set Accountant]", 'clearCmdLine() appendCmdLine("goldeneyes accountant ")', "Designate the collector", true)
            cecho("\n")
        end
    ]]))

    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You have left your party\\.$", 
    [[
        if goldeneyes.party_alerts then
            cecho("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: You left the party. ")
            cechoLink("<red>[Reset Tracker]", "goldeneyes.reset()", "Wipe all current ledger data", true)
            cecho("\n")
        end
    ]]))

    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^\\(Party\\): (\\w+) has joined your party\\.$", 
    [[
        if goldeneyes.party_alerts then
            local name = matches[2]
            cecho("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: <geGold>" .. name .. " <geSilver>joined the party. ")
            cechoLink("<green>[Add to Tracker]", 'goldeneyes.add("' .. name .. '")', "Add " .. name .. " to the gold split", true)
            cecho("\n")
        end
    ]]))

    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^\\(Party\\): (\\w+) has left your party\\.$", 
    [[
        local name = matches[2]
        if goldeneyes.party_alerts and goldeneyes.names[name:lower()] then
            cecho("\n<geSilver>[<geGold>Goldeneyes<geSilver>]: <geGold>" .. name .. " <geSilver>left the party. ")
            cechoLink("<orange>[Remove from Tracker]", 'goldeneyes.remove("' .. name .. '")', "Remove " .. name .. " from the gold split", true)
            cecho("\n")
        end
    ]]))
    
    -- Master Alias: Route all user commands to functions
    table.insert(goldeneyes.alias_ids, tempAlias("^(?:goldeneyes|gold)(?:\\s+(.*))?$", 
    [[
        local args_str = matches[2] or ""
        local args = args_str:split(" ")
        local cmd = args[1] and args[1]:lower() or ""

        if cmd == "" then goldeneyes.display()
        elseif cmd == "help" then goldeneyes.help()
        elseif cmd == "on" or cmd == "off" then goldeneyes.toggle(cmd)
        elseif cmd == "autoloot" then goldeneyes.togglepickup(args[2] or "")
        elseif cmd == "container" then 
            if args[2] then goldeneyes.setcontainer(args[2]) else cecho("\n<geSilver>Usage: <geGold>goldeneyes container <name>") end
        elseif cmd == "stash" then goldeneyes.stash()
        elseif cmd == "add" then if args[2] then goldeneyes.add(args[2]) end
        elseif cmd == "party" or cmd == "group" then goldeneyes.scan_group()
        elseif cmd == "remove" then if args[2] then goldeneyes.remove(args[2]) end
        elseif cmd == "plus" then local amt = tonumber(args[2]); if amt then goldeneyes.plus(amt) end
        elseif cmd == "minus" then local amt = tonumber(args[2]); if amt then goldeneyes.minus(amt) end
        elseif cmd == "pause" then if args[2] then goldeneyes.pause(args[2]) end
        elseif cmd == "unpause" then if args[2] then goldeneyes.unpause(args[2]) end
        elseif cmd == "reset" then goldeneyes.reset()
        elseif cmd == "distribute" then goldeneyes.distribute(args[2])
        elseif cmd == "snapshot" then goldeneyes.start_snapshot()
        elseif cmd == "check" then goldeneyes.check_reward()
        elseif cmd == "report" then goldeneyes.announce(args[2])
        elseif cmd == "accountant" then 
            if args[2] then goldeneyes.set_accountant(args[2]) else cecho("\n<geSilver>Current Accountant: <geGold>" .. goldeneyes.accountant) end
        elseif cmd == "loot" then 
            local amt = tonumber(args[2]); if amt then goldeneyes.handle_loot(amt) else cecho("\n<geSilver>Usage: <geGold>goldeneyes loot <amount>") end
        elseif cmd == "autohandover" then goldeneyes.toggle_handover(args[2] or "")
        elseif cmd == "strategy" then goldeneyes.set_strategy(args[2])
        elseif cmd == "alerts" then goldeneyes.togglealerts(args[2] or "")
        elseif cmd == "calc" then goldeneyes.calc(args[2], args[3])
        else cecho("\n<geSilver>Unknown command. Try <geGold>goldeneyes help<geSilver>.") end
    ]]))

    goldeneyes.echo("Dynamic triggers and aliases loaded.")
end

-- =========================================================== --
-- SECTION 10: SCRIPT STARTUP                                  --
-- =========================================================== --

-- Initialize the triggers
goldeneyes.create_triggers()

-- Load the saved configuration to overwrite defaults
goldeneyes.load()

-- Inform user it successfully loaded
cecho("\n<green>Goldeneyes Core Loaded Successfully!<reset>\n")