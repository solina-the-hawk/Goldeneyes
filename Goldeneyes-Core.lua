-- =========================================================================
-- GOLDENEYES: Gold Tracking & Distribution Utility
-- A robust Mudlet ledger for Achaean hunting parties.
-- Author: Solina (https://github.com/solina-the-hawk/goldeneyes/)
-- Version: 1.1.0
-- =========================================================================
goldeneyes = goldeneyes or {}

-- =========================================================================
-- Configuration
-- These are default preferences you can safely edit if you
-- wish. After you've set them in game, your own settings will save and load with
-- your profile.
-- =========================================================================
goldeneyes.config = goldeneyes.config or {
    -- container: The default container into which to stash gold.
    container = "pouch",
    -- pickup: Whether or not to default to picking up gold that we see automatically.
    pickup = true,
    -- autohandover: Whether or not to default to handing gold over immediately to the accountant.
    autohandover = false,
    -- split_strategy: What split strategy we prefer for distributing earned gold. Even is most common.
    split_strategy = "even",
    -- party_alerts:Whether to alert you with clickable prompts when party members join/leave 
    -- (to quickly add/remove them from tracking).
    party_alerts = true,
    -- colors: What colors to use to highlight different elements of the Goldeneyes 
    -- display (using RGB values).
    colors = {
        goldeneyesGold   = {255, 215, 0},
        goldeneyesSilver = {248, 248, 255},
        goldeneyesCopper = {184, 115, 51},
    }
}
-- Register custom colors above with Mudlet's cecho engine.
for name, rgb in pairs(goldeneyes.config.colors) do
    color_table[name] = rgb
end

-- =========================================================================
 -- Runtime States
 -- Internal variables used for math and tracking. Do not edit!
 -- =========================================================================
if goldeneyes.enabled == nil then goldeneyes.enabled = true end
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
goldeneyes.reset_pending = false
goldeneyes.pending_gold = goldeneyes.pending_gold or {}

local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
goldeneyes.accountant = goldeneyes.accountant or my_name

-- =========================================================================
-- Helper Functions
-- Several simple functions to help format numbers, count elements in a table,
-- and echo package related messages in a clean and reliable way.
-- =========================================================================

-- Counts elements in a table.
function goldeneyes.count(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Standardized script echo.
function goldeneyes.echo(x)
    cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: " .. x .. "<reset>")
end

-- Formats numbers with commas (e.g., 10000 -> 10,000).
function goldeneyes.format(amount)
    if not amount then return "0" end
    local formatted = tostring(math.floor(tonumber(amount) or 0))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k == 0) then break end
    end
    return formatted
end

-- Empty placeholder for custom prompt hooks (prevents nil errors).
function goldeneyes.showprompt() end

-- =========================================================================
-- Profile Management
-- This section saves and loads your configuration state to a file, so that
-- you don't lose all your data if you crash or disconnect. It also allows you
-- to transfer your settings between computers by copying the saved file.
-- =========================================================================
-- Returns cross-platform compatible save path
function goldeneyes.get_save_path()
    return getMudletHomeDir() .. "/Goldeneyes-Data.lua"
end

function goldeneyes.save()
    -- Check and create the master Goldeneyes folder before saving
    local baseDir = getMudletHomeDir() .. "/Goldeneyes"
    if not lfs.attributes(baseDir) then lfs.mkdir(baseDir) end
    
    local filepath = baseDir .. "/Goldeneyes_Profile.json"
    
    -- Create a copy of the config table that EXCLUDES colors
    local export_config = {}
    for k, v in pairs(goldeneyes.config) do
        if k ~= "colors" then export_config[k] = v end
    end

    local data = {
        enabled = goldeneyes.enabled,
        config = export_config, -- Save the filtered config
        names = goldeneyes.names,
        paused = goldeneyes.paused,
        total = goldeneyes.total,
        org = goldeneyes.org,
        ledger = goldeneyes.ledger,
        unknown_ledger = goldeneyes.unknown_ledger,
        baseline = goldeneyes.baseline,
        expenses = goldeneyes.expenses,
        accountant = goldeneyes.accountant,
        starttime = goldeneyes.starttime,
    }
    
    -- Use io.open and yajl to write true JSON data
    local file = io.open(filepath, "w")
    if file then
        file:write(yajl.to_string(data))
        file:close()
    end
end

-- Restores state from file
function goldeneyes.load()
    local filepath = getMudletHomeDir() .. "/Goldeneyes/Goldeneyes_Profile.json"
    local file = io.open(filepath, "r")
    
    if not file then
        goldeneyes.echo("<red>(Error)<reset>: No Goldeneyes_Profile.json found to load! Type <yellow>goldeneyes profile save<reset> to create one.")
        return 
    end

    -- Read the JSON file and convert it back to a Lua table
    local contents = file:read("*a")
    file:close()
    
    local success, data = pcall(yajl.to_value, contents)
    if not success or type(data) ~= "table" then
        goldeneyes.echo("<red>(Error)<reset>: Your Goldeneyes_Profile.json has a formatting error!")
        return
    end
        
    goldeneyes.enabled = data.enabled
    goldeneyes.names = data.names or goldeneyes.names
    goldeneyes.paused = data.paused or goldeneyes.paused
    goldeneyes.total = data.total or goldeneyes.total
    goldeneyes.org = data.org or goldeneyes.org
    goldeneyes.ledger = data.ledger or goldeneyes.ledger
    goldeneyes.unknown_ledger = data.unknown_ledger or goldeneyes.unknown_ledger
    goldeneyes.baseline = data.baseline or goldeneyes.baseline
    goldeneyes.expenses = data.expenses or goldeneyes.expenses
    goldeneyes.accountant = data.accountant or goldeneyes.accountant
    goldeneyes.starttime = data.starttime or goldeneyes.starttime
    
    -- Safely overwrite config if saved values exist
    if data.config then
        for k, v in pairs(data.config) do
            if k ~= "colors" then -- Ignore saved colors so the Lua file is always the master!
                goldeneyes.config[k] = v
            end
        end
    end
end

-- =========================================================================
-- Ledger & Math Logic
-- Does the mathematics for calculating shares, adding amounts and updating totals,
-- etc. This is the core of the package and where most of the "magic" happens.
-- =========================================================================

-- Calculates current shares based on active strategy.
function goldeneyes.get_shares()
    local shares = {}
    local count = goldeneyes.count(goldeneyes.names)
    if count == 0 then return shares end
    
    if goldeneyes.config.split_strategy == "even" then
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

-- Manually add gold to the total pool.
function goldeneyes.plus(amt, noecho)
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
    if not noecho then x.echo("<goldeneyesGold>" .. goldeneyes.format(original_amt) .. " <goldeneyesSilver>gold added.") end
    if type(x.showprompt) == "function" then x.showprompt() end
end

-- Manually subtract gold from the total pool.
function goldeneyes.minus(amt)
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
    x.echo("<goldeneyesGold>" .. goldeneyes.format(amt) .. " <goldeneyesSilver>gold removed.")
    if type(x.showprompt) == "function" then x.showprompt() end
end

-- Quick external math calculator.
function goldeneyes.calc(amount, people)
    if type(amount) == "string" then amount = amount:gsub(",", "") end
    
    amount = tonumber(amount)
    people = tonumber(people)

    if not amount or not people or people <= 0 then
        goldeneyes.echo("<goldeneyesSilver>Usage: <goldeneyesGold>goldeneyes calc <amount> <number of people>")
        return
    end

    local share = math.floor(amount / people)
    local remainder = amount % people

    local msg = string.format("Splitting <goldeneyesGold>%s<goldeneyesSilver> gold among <goldeneyesGold>%d<goldeneyesSilver> people results in <goldeneyesGold>%s<goldeneyesSilver> gold each.", 
        goldeneyes.format(amount), people, goldeneyes.format(share))

    if remainder > 0 then
        msg = msg .. string.format(" <goldeneyesSilver>(Remainder: <orange>%s<goldeneyesSilver>)", goldeneyes.format(remainder))
    end
    goldeneyes.echo(msg)
end

-- Log known expenses (e.g. shop purchases) for the snapshot checker.
function goldeneyes.add_expense(amt)
    if goldeneyes.enabled then
        goldeneyes.expenses = goldeneyes.expenses + amt
        goldeneyes.echo("Tracked expense of <orange>" .. goldeneyes.format(amt) .. "<goldeneyesSilver> gold.")
    end
end

-- =========================================================================
-- Party & Group Management
-- Tracks party members and their shares, allows you to quickly add/remove 
-- people from the split.
-- =========================================================================

-- Add an individual to the split
function goldeneyes.add(name)
    name = name:lower()
    if goldeneyes.names[name] == nil then
        goldeneyes.echo("Added <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>to tracking.")
        goldeneyes.names[name] = 0
    else
        goldeneyes.echo("<goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>is already being tracked.")
    end
    if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
end

-- Remove an individual from the split
function goldeneyes.remove(name)
    name = name:lower()
    if goldeneyes.names[name] ~= nil then
        goldeneyes.echo("Removed <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>from tracking.")
        goldeneyes.echo("<goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>was at <goldeneyesGold>" .. goldeneyes.format(goldeneyes.names[name]) .. " <goldeneyesSilver>gold.")
        goldeneyes.names[name] = nil
    else
        goldeneyes.echo("<goldeneyesGold>" .. name .. " <goldeneyesSilver>is not currently being tracked.")
    end
    if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
end

-- Pause a tracked member (preserves their current share)
function goldeneyes.pause(name)
    name = name:lower()
    if goldeneyes.names[name] ~= nil then
        goldeneyes.echo("Gold tracking for <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>paused.")
        goldeneyes.paused[name] = goldeneyes.names[name]
        goldeneyes.names[name] = nil
    end
    if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
end

-- Unpause a tracked member
function goldeneyes.unpause(name)
    name = name:lower()
    if goldeneyes.paused[name] then
        goldeneyes.echo("Gold tracking for <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>unpaused.")
        goldeneyes.names[name] = goldeneyes.paused[name]
        goldeneyes.paused[name] = nil
    end
    if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
end

-- Trigger an in-game scan for Party, Group, and Intrepid members
function goldeneyes.scan_group()
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
        if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
    end)
end

-- Accept untracked gold handed to you (via interactive prompt)
function goldeneyes.accept_pending(name)
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
function goldeneyes.ignore_pending(name)
    local name_key = name:lower()
    if goldeneyes.pending_gold[name_key] then
        goldeneyes.pending_gold[name_key] = nil
        goldeneyes.echo("Ignored gold from " .. name:title() .. ".")
    end
end

-- =========================================================================
-- Inventory & Loot Management
-- Controls movement of gold around the inventory, where to stash things, and
-- automatically picking up gold and handing it over to the accountant if desired.
-- =========================================================================

-- Set physical container for gold storage
function goldeneyes.setcontainer(name)
    goldeneyes.config.container = name
    goldeneyes.echo("Loot container set to: <goldeneyesGold>" .. name)
    goldeneyes.save()
end

-- Move all loose gold to container
function goldeneyes.stash()
    local cont = goldeneyes.config.container or "pack"
    send("queue add eqbal put gold in " .. cont)
    goldeneyes.echo("Attempting to stash gold in your <goldeneyesGold>" .. cont)
end

-- Toggle automatic scooping
function goldeneyes.togglepickup(val)
    local state = val:lower() == "on"
    goldeneyes.config.pickup = state
    goldeneyes.echo("Auto-pickup is now " .. (state and "<green>ENABLED<goldeneyesSilver>" or "<red>DISABLED<goldeneyesSilver>"))
end

-- Toggle sending picked up gold to the accountant
function goldeneyes.toggle_handover(val)
    if val == "on" then
        goldeneyes.config.autohandover = true
        goldeneyes.echo("Auto-Handover <green>ENABLED<goldeneyesSilver>. I will give gold to " .. goldeneyes.accountant)
    else
        goldeneyes.config.autohandover = false
        goldeneyes.echo("Auto-Handover <red>DISABLED<goldeneyesSilver>.")
    end
end

-- Process incoming gold pick-ups
function goldeneyes.handle_loot(amt)
    if not goldeneyes.enabled then return end
    local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
    local my_name_lower = my_name:lower()
    local acc = goldeneyes.accountant or my_name
    local cont = goldeneyes.config.container or "pack"

    -- Always add to our local total so the display is useful for everyone!
    goldeneyes.plus(amt, true)

    if acc:lower() == my_name_lower then
        goldeneyes.echo("Gold added to ledger. New total is <goldeneyesGold>" .. goldeneyes.format(goldeneyes.total) .. "<goldeneyesSilver> gold.")
        
        if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
            send("queue add eqbal put " .. amt .. " gold in " .. cont, false)
        end
    else
        -- We are NOT the accountant. Add to our local debt until we successfully hand it over.
        goldeneyes.ledger[my_name_lower] = (goldeneyes.ledger[my_name_lower] or 0) + amt

        if goldeneyes.config.autohandover then
            send("queue add eqbal give " .. amt .. " gold to " .. acc)
            goldeneyes.echo("Looted <goldeneyesGold>"..goldeneyes.format(amt).."<goldeneyesSilver>. Attempting to hand over to <goldeneyesGold>"..acc)
        else
            send("pt I picked up " .. goldeneyes.format(amt) .. " gold.")
            goldeneyes.echo("Looted <goldeneyesGold>"..goldeneyes.format(amt).."<goldeneyesSilver>. Kept locally (Added to Debt).")
            if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
                send("queue add eqbal put " .. amt .. " gold in " .. cont, false)
            end
        end
    end
end

-- =========================================================================
-- Snapshots & Checks
-- Used to snapshot current gold amounts and watch for changes not caught in
-- gold drop and looting messages, such as quest rewards.
-- =========================================================================

-- Alias wrapper to set baseline
function goldeneyes.start_snapshot()
    goldeneyes.set_baseline()
end

-- Execute in-game 'show gold' to establish baseline
function goldeneyes.set_baseline()
    goldeneyes.baseline.set = false
    goldeneyes.capture_mode = "baseline"
    send("show gold")
end

-- Check physical gold against expected ledger gold
function goldeneyes.check_reward()
    if not goldeneyes.baseline.set then
        goldeneyes.echo("<yellow>Warning:<goldeneyesSilver> No baseline established yet. Establishing now. Type <goldeneyesGold>goldeneyes check<goldeneyesSilver> after your next reward.")
        goldeneyes.set_baseline()
        return
    end
    goldeneyes.capture_mode = "check"
    send("show gold")
end

-- Process the captured 'show gold' string
function goldeneyes.process_gold_capture(hand, bank)
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
            goldeneyes.echo("<orange>Hidden Reward Detected!<goldeneyesSilver> You gained <goldeneyesGold>" .. goldeneyes.format(hidden_profit) .. "<goldeneyesSilver> gold.")
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

-- =========================================================================
-- UI & Display
-- Controls the help menu and the informational displays.
-- =========================================================================

-- Master display layout
-- Master display layout
function goldeneyes.display()
    local status = goldeneyes.enabled and "<green>ON<goldeneyesSilver>" or "<red>OFF<goldeneyesSilver>"
    local current_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
    local accountant = goldeneyes.accountant or current_name
    local role = (accountant:lower() == current_name:lower()) and "<green>Me<goldeneyesSilver>" or ("<goldeneyesGold>" .. accountant:title() .. "<goldeneyesSilver>")
    local strat_text = (goldeneyes.config.split_strategy == "even") and "<green>Even<goldeneyesSilver>" or "<yellow>Fair<goldeneyesSilver>"
    local cont = goldeneyes.config.container or "pack"

    local elapsed = os.time() - goldeneyes.starttime
    if elapsed < 1 then elapsed = 1 end
    local gph = math.floor((goldeneyes.total / elapsed) * 3600)

    -- Header & Status Bar
    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho("\n<goldeneyesGold>                   G O L D E N E Y E S   L E D G E R                   <reset>")
    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho(string.format("\n<goldeneyesSilver>  Tracker: [%s] | Split: [%s] | Stash: [<goldeneyesGold>%s<goldeneyesSilver>] | Collector: [%s]", status, strat_text, cont:title(), role))
    cecho(string.format("\n"))
    cecho(string.format("\n<goldeneyesCopper>  Total Gold: <goldeneyesGold>%-15s <goldeneyesCopper>Gold/Hour: <goldeneyesGold>%s\n", goldeneyes.format(goldeneyes.total), goldeneyes.format(gph)))

    if goldeneyes.org.name then
        cecho(string.format("  <goldeneyesCopper>City/Org Tax  (<goldeneyesGold>%d%%<goldeneyesSilver>): <goldeneyesGold>%s\n", goldeneyes.org.percent, goldeneyes.format(goldeneyes.org.gold)))
    end

    -- Active Shares Section
    if goldeneyes.count(goldeneyes.names) > 0 then 
        cecho("\n<goldeneyesCopper>  Active Shares:<reset>\n") 
        local shares = goldeneyes.get_shares()
        for k, v in pairs(shares) do
            cecho("  <goldeneyesSilver>" .. string.format("%14s", k:title()) .. ": <goldeneyesGold>" .. goldeneyes.format(v) .. "\n")
        end
    else
        cecho("\n<goldeneyesSilver>  No members currently tracked. Use <goldeneyesGold>gold group<goldeneyesSilver> to add.\n")
    end

    -- Debts & Unknowns Section
    local ledger_count = goldeneyes.count(goldeneyes.ledger)
    local unknown_count = goldeneyes.count(goldeneyes.unknown_ledger)

    if ledger_count > 0 or unknown_count > 0 then
        cecho("\n<goldeneyesCopper>  Pending Debts & Held Gold:<reset>\n")
        local all_holders = {}
        for k,v in pairs(goldeneyes.ledger) do all_holders[k] = true end
        for k,v in pairs(goldeneyes.unknown_ledger) do all_holders[k] = true end

        for k, _ in pairs(all_holders) do
            local debt = goldeneyes.ledger[k] or 0
            local unknown = goldeneyes.unknown_ledger[k] or 0
            local str = string.format("  <goldeneyesSilver>%14s: ", k:title())

            if debt > 0 then str = str .. "<orange>" .. goldeneyes.format(debt) .. " gold " end
            if unknown > 0 then str = str .. "<red>(+" .. unknown .. " unknown piles!)" end
            cecho(str .. "\n")
        end
    end

    -- Footer
    cecho("<goldeneyesGold>=======================================================================<reset>\n")
    
    -- Safe trigger for custom prompts
    if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
end

-- Announce the current progress
function goldeneyes.announce(channel)
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
function goldeneyes.set_strategy(strat)
    strat = strat and strat:lower() or "even"
    if strat == "even" or strat == "fair" then
        goldeneyes.config.split_strategy = strat
        goldeneyes.echo("Split strategy set to: <goldeneyesGold>" .. strat:title() .. "\n")
        cecho("  <goldeneyesGold>Even <goldeneyesSilver>split will divide the total gold pool equally among current members at distribution time.\n")
        cecho("  <goldeneyesGold>Fair <goldeneyesSilver>split will distribute gold based on when each person joined the party.\n")
        if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
    else
        goldeneyes.echo("<goldeneyesSilver>Usage: <goldeneyesGold>goldeneyes strategy <even|fair>")
    end
end

-- Designate the collector
function goldeneyes.set_accountant(name)
    goldeneyes.accountant = name:title()
    cecho("Collector set to <goldeneyesGold>" .. name)
    if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
end

-- Toggle click-to-add UI alerts
function goldeneyes.togglealerts(val)
    local state = val:lower() == "on"
    goldeneyes.config.party_alerts = state
    cecho("Party alerts are now " .. (state and "<green>ENABLED<goldeneyesSilver>" or "<red>DISABLED<goldeneyesSilver>"))
end

-- Toggle the entire tracker
function goldeneyes.toggle(toggle_cmd)
    -- Check if the command was "on" OR "enabled"
    local state = (toggle_cmd:lower() == "on" or toggle_cmd:lower() == "enabled")
    goldeneyes.enabled = state

    if state and goldeneyes.count(goldeneyes.names) == 0 and gmcp.Char and gmcp.Char.Name then
        goldeneyes.add(gmcp.Char.Name.name:lower())
    end
    goldeneyes.echo("Tracking " .. (state and "<goldeneyesGold>enabled" or "<red>disabled"))
    
    if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
end

-- Double-tap reset logic
-- Warning prompt for manual reset
function goldeneyes.reset()
    cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <red>WARNING!<goldeneyesSilver> This will wipe ALL data (Total: " .. goldeneyes.format(goldeneyes.total) .. ").\n")
    cecho("<goldeneyesSilver>To proceed, type <goldeneyesGold>goldeneyes reset confirm<reset>\n")
end

-- Wipes the memory arrays
function goldeneyes.confirm_reset()
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
    goldeneyes.save() -- Immediately commit the wipe to the JSON file
    goldeneyes.echo("<red>Tracker has been reset.<reset>")
    if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
end

-- Final payout command
function goldeneyes.distribute(channel)
    local cont = goldeneyes.config.container or "pack"
    local shares = goldeneyes.get_shares()
    local members = goldeneyes.count(goldeneyes.names)
    local my_name = gmcp.Char.Name.name:lower()
    
    -- Calculate the exact total of all shares (plus org tax) to withdraw from the container
    local total_withdraw = 0
    for k, v in pairs(shares) do
        total_withdraw = total_withdraw + math.floor(v)
    end
    
    -- Ensure we also pull out the org tax if one is set
    if goldeneyes.org and goldeneyes.org.name then
        total_withdraw = total_withdraw + math.floor(goldeneyes.org.gold)
    end
    
    -- Withdraw the full hunt yield so your cut and org tax land in your inventory
    if cont:lower() ~= "none" and cont:lower() ~= "inventory" and total_withdraw > 0 then
        send("queue add eqbal get " .. total_withdraw .. " gold from " .. cont)
    end
    
    channel = channel and channel:lower() or "party"
    local cmd = "pt"
    local message = ""
    local silent = (channel == "none")
    
    if goldeneyes.config.split_strategy == "even" then
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
        if k ~= my_name then
            v = math.floor(v)
            if v > 0 then 
                tempTimer(delay, function() send("queue add eqbal give " .. v .. " gold to " .. k) end)
                delay = delay + 0.5
            end
        end
    end

    goldeneyes.echo("Distributed gold from <goldeneyesGold>" .. cont)
    cecho("\n\n<goldeneyesSilver>Distribution commands queued. Auto-resetting tracker to prevent double payouts.\n")
    goldeneyes.confirm_reset()
end

-- =========================================================================
-- Event Handlers & Hooks
-- =========================================================================
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

    if goldeneyes.config.pickup then
        goldeneyes.echo("Auto-pickup is <goldeneyesGold>ENABLED<goldeneyesSilver>.")
    end

    if not goldeneyes.login_prompted and goldeneyes.total > 0 then
        goldeneyes.login_prompted = true
        cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <yellow>Welcome back! You have an active hunting ledger with " .. goldeneyes.format(goldeneyes.total) .. " gold.<reset>\n")
        cecho("       ")
        cechoLink("<red>[Start Fresh]", "goldeneyes.confirm_reset()", "Wipe all data for a new hunt", true)
        cecho(" <goldeneyesSilver>| ")
        cechoLink("<green>[Keep Data]", "goldeneyes.echo('Ledger preserved. Type \\'gold\\' to view.')", "Resume previous hunt", true)
        cecho("\n")
    end
end

-- Ensure we don't register multiple handlers on reload
if goldeneyes.login_handler then killAnonymousEventHandler(goldeneyes.login_handler) end
goldeneyes.login_handler = registerAnonymousEventHandler("gmcp.Char.Name", "goldeneyes_login_check")

-- Save hooks for application exit / game disconnection
if goldeneyes.save_exit_handler then killAnonymousEventHandler(goldeneyes.save_exit_handler) end
goldeneyes.save_exit_handler = registerAnonymousEventHandler("sysExitEvent", "goldeneyes.save")

if goldeneyes.save_dc_handler then killAnonymousEventHandler(goldeneyes.save_dc_handler) end
goldeneyes.save_dc_handler = registerAnonymousEventHandler("sysDisconnectionEvent", "goldeneyes.save")

-- =========================================================================
-- Dynamic Triggers & Aliases
-- These are used for all in-game event detection, such as gold pickups, 
-- expenses, and similar events.
-- =========================================================================
goldeneyes.trigger_ids = goldeneyes.trigger_ids or {}
goldeneyes.alias_ids = goldeneyes.alias_ids or {}

function goldeneyes.create_triggers()
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

    -- Trigger: Shop Purchases & Expenses
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You pay ([\\d,]+) gold sovereigns\\.$", [[ goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You buy .* for ([\\d,]+) gold\\.$", [[ goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    
    -- Trigger: Gold Given Away (Handover Resolution)
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
            goldeneyes.echo("Successfully handed over <goldeneyesGold>" .. goldeneyes.format(amount) .. "<goldeneyesSilver> to accountant.")
        end
    ]]))

    -- Trigger: Handover Failure (Accountant Unavailable)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^(?:Ahh, I am truly sorry, but I do not see anyone by that name here\\.|You cannot see that being here\\.|You cannot find anyone by that name here\\.)$", 
    [[
        local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"
        local acc = goldeneyes.accountant and goldeneyes.accountant:lower() or my_name
        
        -- If we have a local debt and we aren't the accountant, a failure message means our handover missed.
        if goldeneyes.config.autohandover and acc ~= my_name and goldeneyes.ledger[my_name] and goldeneyes.ledger[my_name] > 0 then
            goldeneyes.echo("<red>Handover failed! <goldeneyesSilver>The accountant isn't here. Stashing gold safely.")
            local cont = goldeneyes.config.container or "pack"
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
        if goldeneyes.enabled and goldeneyes.config.pickup then 
            goldeneyes.echo("Scooping loose gold.")
            send("queue add eqbal get gold", false) 
        end 
    ]]
    local grab_regex = "(?:^A.*sovereigns? spills? from the corpse|A pile of golden sovereigns twinkles and gleams\\.|There is.*pile of golden sovereigns here\\.|pile of .*sovereigns?)"
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger(grab_regex, grab_script))

    -- Trigger: Gold Received (Handover Resolution)
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
                cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: %s paid off %s (Remaining: %s).", name, goldeneyes.format(amount), goldeneyes.format(goldeneyes.ledger[name_key])))
                if goldeneyes.ledger[name_key] <= 0 then
                    goldeneyes.ledger[name_key] = nil
                    cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: %s has settled their debt.", name))
                end
            else
                cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: Accepted %s gold from %s (No prior debt).", goldeneyes.format(amount), name))
            end
        else
            -- They are NOT tracked. Hold the gold and ask!
            goldeneyes.pending_gold = goldeneyes.pending_gold or {}
            goldeneyes.pending_gold[name_key] = (goldeneyes.pending_gold[name_key] or 0) + amount
            
            cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <yellow>Received %s gold from an UNTRACKED person: %s.<reset>\n", goldeneyes.format(amount), name))
            cecho("       ")
            cechoLink("<green>[Add to Tracker & Pot]", 'goldeneyes.accept_pending("' .. name .. '")', "Track " .. name .. " and add " .. goldeneyes.pending_gold[name_key] .. " to pot", true)
            cecho(" <goldeneyesSilver>| ")
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
            cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <orange>ALERT<goldeneyesSilver>: <goldeneyesGold>%s<goldeneyesSilver> picked up <orange>%s<goldeneyesSilver> gold!", name, goldeneyes.format(amount)))
        end
    ]]))
    -- 8a. Capture Gold (Start of message)
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
        if goldeneyes.config.party_alerts then
            cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: You joined a party. ")
            cechoLink("<green>[Scan Group]", "goldeneyes.scan_group()", "Auto-add party/group to ledger", true)
            cecho(" <goldeneyesSilver>| ")
            cechoLink("<yellow>[Set Accountant]", 'clearCmdLine() appendCmdLine("goldeneyes accountant ")', "Designate the collector", true)
            cecho("\n")
        end
    ]]))

    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You have left your party\\.$", 
    [[
        if goldeneyes.config.party_alerts then
            cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: You left the party. ")
            cechoLink("<red>[Reset Tracker]", "goldeneyes.reset()", "Wipe all current ledger data", true)
            cecho("\n")
        end
    ]]))

    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^\\(Party\\): (\\w+) has joined your party\\.$", 
    [[
        if goldeneyes.config.party_alerts then
            local name = matches[2]
            cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <goldeneyesGold>" .. name .. " <goldeneyesSilver>joined the party. ")
            cechoLink("<green>[Add to Tracker]", 'goldeneyes.add("' .. name .. '")', "Add " .. name .. " to the gold split", true)
            cecho("\n")
        end
    ]]))

    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^\\(Party\\): (\\w+) has left your party\\.$", 
    [[
        local name = matches[2]
        if goldeneyes.config.party_alerts and goldeneyes.names[name:lower()] then
            cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <goldeneyesGold>" .. name .. " <goldeneyesSilver>left the party. ")
            cechoLink("<orange>[Remove from Tracker]", 'goldeneyes.remove("' .. name .. '")', "Remove " .. name .. " from the gold split", true)
            cecho("\n")
        end
    ]]))

-- =========================================================================
-- In-Game Commands & Help Interface
-- Powers the text that appears when you type "goldeneyes help" in game, as well as
-- the various toggles and commands you can use on the fly without editing your config.
-- =========================================================================
function goldeneyes.help()
    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho("\n<goldeneyesGold>                    G O L D E N E Y E S   H E L P                      <reset>")
    cecho("\n<goldeneyesGold>=======================================================================<reset>\n")
    
    cecho("\n<goldeneyesSilver>Goldeneyes is a robust Mudlet ledger for Achaean hunting parties.")
    cecho("\nCommands work with either <goldeneyesGold>goldeneyes<goldeneyesSilver> or <goldeneyesGold>gold<goldeneyesSilver>.")
    cecho("\nPermanent settings (like colors and defaults) are configured in the")
    cecho("\n<goldeneyesGold>goldeneyes.config<goldeneyesSilver> block at the top of the Lua script.<reset>\n")

    cecho("\n<goldeneyesCopper>Basic Controls:<reset>")
    cecho("\n  <goldeneyesGold>gold <on|off>               <goldeneyesSilver>- Turn tracker on/off.")
    cecho("\n  <goldeneyesGold>gold reset                  <goldeneyesSilver>- Reset all totals (enter twice to confirm).")
    cecho("\n  <goldeneyesGold>gold report [channel]       <goldeneyesSilver>- Announce totals (Channels: party, intrepid, say).")

    cecho("\n\n<goldeneyesCopper>Group & Party Management:<reset>")
    cecho("\n  <goldeneyesGold>gold strategy <even|fair>   <goldeneyesSilver>- Set split method (Default: even).")
    cecho("\n  <goldeneyesGold>gold group                  <goldeneyesSilver>- Auto-add party, group, and intrepid members.")
    cecho("\n  <goldeneyesGold>gold add <name>             <goldeneyesSilver>- Add a person to the split list.")
    cecho("\n  <goldeneyesGold>gold remove <name>          <goldeneyesSilver>- Remove a person from the list.")
    cecho("\n  <goldeneyesGold>gold pause <name>           <goldeneyesSilver>- Pause tracking for a member.")
    cecho("\n  <goldeneyesGold>gold unpause <name>         <goldeneyesSilver>- Resume tracking for a member.")

    cecho("\n\n<goldeneyesCopper>Loot & Accounting Automation:<reset>")
    cecho("\n  <goldeneyesGold>gold alerts <on|off>        <goldeneyesSilver>- Toggle clickable party join/leave prompts.")
    cecho("\n  <goldeneyesGold>gold accountant <name>      <goldeneyesSilver>- Designate the collector (Default: You).")
    cecho("\n  <goldeneyesGold>gold autohandover <on|off>  <goldeneyesSilver>- Automatically give loot to collector.")
    cecho("\n  <goldeneyesGold>gold autoloot <on|off>      <goldeneyesSilver>- Toggle auto-looting.")
    cecho("\n  <goldeneyesGold>gold container <name>       <goldeneyesSilver>- Set gold container (e.g., 'pack').")
    cecho("\n  <goldeneyesGold>gold stash                  <goldeneyesSilver>- Move all carried gold to container.")
    cecho("\n  <goldeneyesGold>gold distribute [channel]   <goldeneyesSilver>- Empty container and share gold.")

    cecho("\n\n<goldeneyesCopper>Advanced Math & Checks:<reset>")
    cecho("\n  <goldeneyesGold>gold calc <amt> <#>         <goldeneyesSilver>- Quick math to split an amount of gold.")
    cecho("\n  <goldeneyesGold>gold check                  <goldeneyesSilver>- Capture 'Show Gold' to find hidden rewards.")
    cecho("\n  <goldeneyesGold>gold plus <amount>          <goldeneyesSilver>- Manually add to Total.")
    cecho("\n  <goldeneyesGold>gold minus <amount>         <goldeneyesSilver>- Manually subtract from Total.")
    
    cecho("\n<goldeneyesGold>=======================================================================<reset>\n")
    if type(goldeneyes.showprompt) == "function" then goldeneyes.showprompt() end
end

-- Master Alias: Route all user commands to functions
    table.insert(goldeneyes.alias_ids, tempAlias("^(?:goldeneyes|gold)(?:\\s+(.*))?$", 
    [[
        local args_str = matches[2] or ""
        local args = args_str:split(" ")
        local cmd = args[1] and args[1]:lower() or ""

        if cmd == "" then goldeneyes.display()
        elseif cmd == "help" then goldeneyes.help()
        elseif cmd == "on" or cmd == "off" or cmd == "enabled" or cmd == "disabled" then goldeneyes.toggle(cmd)
        elseif cmd == "autoloot" then goldeneyes.togglepickup(args[2] or "")
        elseif cmd == "container" then 
            if args[2] then goldeneyes.setcontainer(args[2]) else cecho("\n<goldeneyesSilver>Usage: <goldeneyesGold>goldeneyes container <name>") end
        elseif cmd == "stash" then goldeneyes.stash()
        elseif cmd == "add" then if args[2] then goldeneyes.add(args[2]) end
        elseif cmd == "party" or cmd == "group" then goldeneyes.scan_group()
        elseif cmd == "remove" then if args[2] then goldeneyes.remove(args[2]) end
        elseif cmd == "plus" then local amt = tonumber(args[2]); if amt then goldeneyes.plus(amt) end
        elseif cmd == "minus" then local amt = tonumber(args[2]); if amt then goldeneyes.minus(amt) end
        elseif cmd == "pause" then if args[2] then goldeneyes.pause(args[2]) end
        elseif cmd == "unpause" then if args[2] then goldeneyes.unpause(args[2]) end
        elseif cmd == "reset" then 
            if args[2] == "confirm" then goldeneyes.confirm_reset() else goldeneyes.reset() end
        elseif cmd == "distribute" then goldeneyes.distribute(args[2])
        elseif cmd == "snapshot" then goldeneyes.start_snapshot()
        elseif cmd == "check" then goldeneyes.check_reward()
        elseif cmd == "report" then goldeneyes.announce(args[2])
        elseif cmd == "accountant" then 
            if args[2] then goldeneyes.set_accountant(args[2]) else cecho("\n<goldeneyesSilver>Current Accountant: <goldeneyesGold>" .. goldeneyes.accountant) end
        elseif cmd == "loot" then 
            local amt = tonumber(args[2]); if amt then goldeneyes.handle_loot(amt) else cecho("\n<goldeneyesSilver>Usage: <goldeneyesGold>goldeneyes loot <amount>") end
        elseif cmd == "autohandover" then goldeneyes.toggle_handover(args[2] or "")
        elseif cmd == "strategy" then goldeneyes.set_strategy(args[2])
        elseif cmd == "alerts" then goldeneyes.togglealerts(args[2] or "")
        elseif cmd == "profile" then 
            if args[2] == "save" then 
                goldeneyes.save()
                cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: Profile exported successfully.\n")
            elseif args[2] == "load" then 
                goldeneyes.load()
                cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: Profile loaded successfully.\n")
            end
        elseif cmd == "calc" then goldeneyes.calc(args[2], args[3])
        else cecho("\n<goldeneyesSilver>Unknown command. Try <goldeneyesGold>goldeneyes help<goldeneyesSilver>.") end
    ]]))
end

-- =========================================================================
-- Initialization
-- This section runs once when the script is loaded to set up the initial state,
-- load saved data, and prepare the system for use.
-- =========================================================================
-- Initialize the triggers
goldeneyes.create_triggers()
-- Load the saved configuration to overwrite defaults
goldeneyes.load()
-- Inform user it successfully loaded
goldeneyes.echo("Loaded Successfully!")