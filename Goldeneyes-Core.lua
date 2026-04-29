-- =========================================================================
-- GOLDENEYES: Gold Tracking & Distribution Utility
-- A robust Mudlet ledger for Achaean hunting parties.
-- Author: Solina (https://github.com/solina-the-hawk/Goldeneyes/)
-- Version: 1.1.0
-- =========================================================================
Goldeneyes = Goldeneyes or {}

-- =========================================================================
-- Configuration
-- These are default preferences you can safely edit if you
-- wish. After you've set them in game, your own settings will save and load with
-- your profile.
-- =========================================================================
Goldeneyes.config = Goldeneyes.config or {
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
for name, rgb in pairs(Goldeneyes.config.colors) do
    color_table[name] = rgb
end

-- =========================================================================
 -- Runtime States
 -- Internal variables used for math and tracking. Do not edit!
 -- =========================================================================
if Goldeneyes.enabled == nil then Goldeneyes.enabled = true end
Goldeneyes.names = Goldeneyes.names or {}
Goldeneyes.paused = Goldeneyes.paused or {}
Goldeneyes.total = Goldeneyes.total or 0
Goldeneyes.org = Goldeneyes.org or {name = false, percent = 0, gold = 0}
Goldeneyes.starttime = Goldeneyes.starttime or os.time()
Goldeneyes.ledger = Goldeneyes.ledger or {}
Goldeneyes.unknown_ledger = Goldeneyes.unknown_ledger or {}
Goldeneyes.snapshot = Goldeneyes.snapshot or {hand = 0, bank = 0, phase = nil}
Goldeneyes.baseline = Goldeneyes.baseline or {hand = 0, bank = 0, set = false}
Goldeneyes.expenses = Goldeneyes.expenses or 0
Goldeneyes.reset_pending = false
Goldeneyes.pending_gold = Goldeneyes.pending_gold or {}

local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
Goldeneyes.accountant = Goldeneyes.accountant or my_name

-- =========================================================================
-- Helper Functions
-- Several simple functions to help format numbers, count elements in a table,
-- and echo package related messages in a clean and reliable way.
-- =========================================================================

-- Counts elements in a table.
function Goldeneyes.count(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Standardized script echo.
function Goldeneyes.echo(x)
    cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: " .. x .. "<reset>")
end

-- Formats numbers with commas (e.g., 10000 -> 10,000).
function Goldeneyes.format(amount)
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
function Goldeneyes.showprompt() end

-- =========================================================================
-- Profile Management
-- This section saves and loads your configuration state to a file, so that
-- you don't lose all your data if you crash or disconnect. It also allows you
-- to transfer your settings between computers by copying the saved file.
-- =========================================================================
-- Returns cross-platform compatible save path
function Goldeneyes.get_save_path()
    return getMudletHomeDir() .. "/Goldeneyes-Data.lua"
end

function Goldeneyes.save()
    -- Check and create the master Goldeneyes folder before saving
    local baseDir = getMudletHomeDir() .. "/Goldeneyes"
    if not lfs.attributes(baseDir) then lfs.mkdir(baseDir) end
    
    local filepath = baseDir .. "/Goldeneyes_Profile.json"
    
    -- Create a copy of the config table that EXCLUDES colors
    local export_config = {}
    for k, v in pairs(Goldeneyes.config) do
        if k ~= "colors" then export_config[k] = v end
    end

    local data = {
        enabled = Goldeneyes.enabled,
        config = export_config, -- Save the filtered config
        names = Goldeneyes.names,
        paused = Goldeneyes.paused,
        total = Goldeneyes.total,
        org = Goldeneyes.org,
        ledger = Goldeneyes.ledger,
        unknown_ledger = Goldeneyes.unknown_ledger,
        baseline = Goldeneyes.baseline,
        expenses = Goldeneyes.expenses,
        accountant = Goldeneyes.accountant,
        starttime = Goldeneyes.starttime,
    }
    
    -- Use io.open and yajl to write true JSON data
    local file = io.open(filepath, "w")
    if file then
        file:write(yajl.to_string(data))
        file:close()
    end
end

-- Restores state from file
function Goldeneyes.load()
    local filepath = getMudletHomeDir() .. "/Goldeneyes/Goldeneyes_Profile.json"
    local file = io.open(filepath, "r")
    
    if not file then
        Goldeneyes.echo("<red>(Error)<reset>: No Goldeneyes_Profile.json found to load! Type <yellow>Goldeneyes profile save<reset> to create one.")
        return 
    end

    -- Read the JSON file and convert it back to a Lua table
    local contents = file:read("*a")
    file:close()
    
    local success, data = pcall(yajl.to_value, contents)
    if not success or type(data) ~= "table" then
        Goldeneyes.echo("<red>(Error)<reset>: Your Goldeneyes_Profile.json has a formatting error!")
        return
    end
        
    Goldeneyes.enabled = data.enabled
    Goldeneyes.names = data.names or Goldeneyes.names
    Goldeneyes.paused = data.paused or Goldeneyes.paused
    Goldeneyes.total = data.total or Goldeneyes.total
    Goldeneyes.org = data.org or Goldeneyes.org
    Goldeneyes.ledger = data.ledger or Goldeneyes.ledger
    Goldeneyes.unknown_ledger = data.unknown_ledger or Goldeneyes.unknown_ledger
    Goldeneyes.baseline = data.baseline or Goldeneyes.baseline
    Goldeneyes.expenses = data.expenses or Goldeneyes.expenses
    Goldeneyes.accountant = data.accountant or Goldeneyes.accountant
    Goldeneyes.starttime = data.starttime or Goldeneyes.starttime
    
    -- Safely overwrite config if saved values exist
    if data.config then
        for k, v in pairs(data.config) do
            if k ~= "colors" then -- Ignore saved colors so the Lua file is always the master!
                Goldeneyes.config[k] = v
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
function Goldeneyes.get_shares()
    local shares = {}
    local count = Goldeneyes.count(Goldeneyes.names)
    if count == 0 then return shares end
    
    if Goldeneyes.config.split_strategy == "even" then
        local net_pool = Goldeneyes.total - Goldeneyes.org.gold
        local even_share = net_pool / count
        for k, _ in pairs(Goldeneyes.names) do
            shares[k] = even_share
        end
    else 
        for k, v in pairs(Goldeneyes.names) do
            shares[k] = v
        end
    end
    return shares
end

-- Manually add gold to the total pool.
function Goldeneyes.plus(amt, noecho)
    local original_amt = amt
    local x = Goldeneyes

    if x.org.name then
        x.org.gold = x.org.gold + original_amt * (x.org.percent/100)
        amt = original_amt * ( 1 - x.org.percent/100)
    end

    local num = Goldeneyes.count(x.names)
    if num > 0 then
        local split_share = amt / num
        for k, v in pairs (x.names) do
            x.names[k] = v + split_share
        end
    end

    x.total = x.total + original_amt
    if not noecho then x.echo("<goldeneyesGold>" .. Goldeneyes.format(original_amt) .. " <goldeneyesSilver>gold added.") end
    if type(x.showprompt) == "function" then x.showprompt() end
end

-- Manually subtract gold from the total pool.
function Goldeneyes.minus(amt)
    local x = Goldeneyes
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
    x.echo("<goldeneyesGold>" .. Goldeneyes.format(amt) .. " <goldeneyesSilver>gold removed.")
    if type(x.showprompt) == "function" then x.showprompt() end
end

-- Quick external math calculator.
function Goldeneyes.calc(amount, people)
    if type(amount) == "string" then amount = amount:gsub(",", "") end
    
    amount = tonumber(amount)
    people = tonumber(people)

    if not amount or not people or people <= 0 then
        Goldeneyes.echo("<goldeneyesSilver>Usage: <goldeneyesGold>Goldeneyes calc <amount> <number of people>")
        return
    end

    local share = math.floor(amount / people)
    local remainder = amount % people

    local msg = string.format("Splitting <goldeneyesGold>%s<goldeneyesSilver> gold among <goldeneyesGold>%d<goldeneyesSilver> people results in <goldeneyesGold>%s<goldeneyesSilver> gold each.", 
        Goldeneyes.format(amount), people, Goldeneyes.format(share))

    if remainder > 0 then
        msg = msg .. string.format(" <goldeneyesSilver>(Remainder: <orange>%s<goldeneyesSilver>)", Goldeneyes.format(remainder))
    end
    Goldeneyes.echo(msg)
end

-- Log known expenses (e.g. shop purchases) for the snapshot checker.
function Goldeneyes.add_expense(amt)
    if Goldeneyes.enabled then
        Goldeneyes.expenses = Goldeneyes.expenses + amt
        Goldeneyes.echo("Tracked expense of <orange>" .. Goldeneyes.format(amt) .. "<goldeneyesSilver> gold.")
    end
end

-- =========================================================================
-- Party & Group Management
-- Tracks party members and their shares, allows you to quickly add/remove 
-- people from the split.
-- =========================================================================

-- Add an individual to the split
function Goldeneyes.add(name)
    name = name:lower()
    if Goldeneyes.names[name] == nil then
        Goldeneyes.echo("Added <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>to tracking.")
        Goldeneyes.names[name] = 0
    else
        Goldeneyes.echo("<goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>is already being tracked.")
    end
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- Remove an individual from the split
function Goldeneyes.remove(name)
    name = name:lower()
    if Goldeneyes.names[name] ~= nil then
        Goldeneyes.echo("Removed <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>from tracking.")
        Goldeneyes.echo("<goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>was at <goldeneyesGold>" .. Goldeneyes.format(Goldeneyes.names[name]) .. " <goldeneyesSilver>gold.")
        Goldeneyes.names[name] = nil
    else
        Goldeneyes.echo("<goldeneyesGold>" .. name .. " <goldeneyesSilver>is not currently being tracked.")
    end
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- Pause a tracked member (preserves their current share)
function Goldeneyes.pause(name)
    name = name:lower()
    if Goldeneyes.names[name] ~= nil then
        Goldeneyes.echo("Gold tracking for <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>paused.")
        Goldeneyes.paused[name] = Goldeneyes.names[name]
        Goldeneyes.names[name] = nil
    end
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- Unpause a tracked member
function Goldeneyes.unpause(name)
    name = name:lower()
    if Goldeneyes.paused[name] then
        Goldeneyes.echo("Gold tracking for <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>unpaused.")
        Goldeneyes.names[name] = Goldeneyes.paused[name]
        Goldeneyes.paused[name] = nil
    end
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- Trigger an in-game scan for Party, Group, and Intrepid members
function Goldeneyes.scan_group()
    Goldeneyes.echo("Scanning party, group, and intrepid members...")
    -- Fire all three commands; the game will just ignore/error the ones not in use!
    send("party members", false)
    send("group", false)
    send("intrepid", false)

    Goldeneyes.scan_triggers = Goldeneyes.scan_triggers or {}

    -- 1. Catch standard Party members and indented Group members
    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^\\s+([A-Z][a-z]+)", function()
        local name = matches[2]
        if name ~= "Party" and name ~= "The" and name ~= "Your" then Goldeneyes.add(name) end
    end))

    -- 2. Catch single group followers or leaders
    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^You are following ([A-Z][a-z]+)\\.", function()
        Goldeneyes.add(matches[2])
    end))
    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^([A-Z][a-z]+) is following you\\.", function()
        Goldeneyes.add(matches[2])
    end))

    -- 3. Catch Intrepid Leader
    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^Leader\\s*:\\s*([A-Z][a-z]+)", function()
        Goldeneyes.add(matches[2])
    end))

    -- 4. Catch Intrepid Members (comma separated list)
    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^Members\\s*:\\s*(.*)", function()
        local members_str = matches[2]
        for name in string.gmatch(members_str, "([A-Z][a-z]+)") do
            if name ~= "And" and name ~= "You" then Goldeneyes.add(name) end
        end
    end))

    -- Clean up triggers after 1.5 seconds
    tempTimer(1.5, function()
        if Goldeneyes.scan_triggers then
            for _, id in ipairs(Goldeneyes.scan_triggers) do killTrigger(id) end
            Goldeneyes.scan_triggers = {}
        end
        Goldeneyes.echo("Group scan complete.")
        if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
    end)
end

-- Accept untracked gold handed to you (via interactive prompt)
function Goldeneyes.accept_pending(name)
    local name_key = name:lower()
    local amount = Goldeneyes.pending_gold[name_key]
    
    if amount then
        Goldeneyes.add(name)
        Goldeneyes.plus(amount)
        Goldeneyes.pending_gold[name_key] = nil
    else
        Goldeneyes.echo("No pending gold found for " .. name:title() .. ".")
    end
end

-- Ignore untracked gold handed to you
function Goldeneyes.ignore_pending(name)
    local name_key = name:lower()
    if Goldeneyes.pending_gold[name_key] then
        Goldeneyes.pending_gold[name_key] = nil
        Goldeneyes.echo("Ignored gold from " .. name:title() .. ".")
    end
end

-- =========================================================================
-- Inventory & Loot Management
-- Controls movement of gold around the inventory, where to stash things, and
-- automatically picking up gold and handing it over to the accountant if desired.
-- =========================================================================

-- Set physical container for gold storage
function Goldeneyes.setcontainer(name)
    Goldeneyes.config.container = name
    Goldeneyes.echo("Loot container set to: <goldeneyesGold>" .. name)
    Goldeneyes.save()
end

-- Move all loose gold to container
function Goldeneyes.stash()
    local cont = Goldeneyes.config.container or "pack"
    send("queue add eqbal put gold in " .. cont)
    Goldeneyes.echo("Attempting to stash gold in your <goldeneyesGold>" .. cont)
end

-- Toggle automatic scooping
function Goldeneyes.togglepickup(val)
    local state = val:lower() == "on"
    Goldeneyes.config.pickup = state
    Goldeneyes.echo("Auto-pickup is now " .. (state and "<green>ENABLED<goldeneyesSilver>" or "<red>DISABLED<goldeneyesSilver>"))
end

-- Toggle sending picked up gold to the accountant
function Goldeneyes.toggle_handover(val)
    if val == "on" then
        Goldeneyes.config.autohandover = true
        Goldeneyes.echo("Auto-Handover <green>ENABLED<goldeneyesSilver>. I will give gold to " .. Goldeneyes.accountant)
    else
        Goldeneyes.config.autohandover = false
        Goldeneyes.echo("Auto-Handover <red>DISABLED<goldeneyesSilver>.")
    end
end

-- Process incoming gold pick-ups
function Goldeneyes.handle_loot(amt)
    if not Goldeneyes.enabled then return end
    local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
    local my_name_lower = my_name:lower()
    local acc = Goldeneyes.accountant or my_name
    local cont = Goldeneyes.config.container or "pack"

    -- Always add to our local total so the display is useful for everyone!
    Goldeneyes.plus(amt, true)

    if acc:lower() == my_name_lower then
        Goldeneyes.echo("Gold added to ledger. New total is <goldeneyesGold>" .. Goldeneyes.format(Goldeneyes.total) .. "<goldeneyesSilver> gold.")
        
        if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
            send("queue add eqbal put " .. amt .. " gold in " .. cont, false)
        end
    else
        -- We are NOT the accountant. Add to our local debt until we successfully hand it over.
        Goldeneyes.ledger[my_name_lower] = (Goldeneyes.ledger[my_name_lower] or 0) + amt

        if Goldeneyes.config.autohandover then
            send("queue add eqbal give " .. amt .. " gold to " .. acc)
            Goldeneyes.echo("Looted <goldeneyesGold>"..Goldeneyes.format(amt).."<goldeneyesSilver>. Attempting to hand over to <goldeneyesGold>"..acc)
        else
            send("pt I picked up " .. Goldeneyes.format(amt) .. " gold.")
            Goldeneyes.echo("Looted <goldeneyesGold>"..Goldeneyes.format(amt).."<goldeneyesSilver>. Kept locally (Added to Debt).")
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
function Goldeneyes.start_snapshot()
    Goldeneyes.set_baseline()
end

-- Execute in-game 'show gold' to establish baseline
function Goldeneyes.set_baseline()
    Goldeneyes.baseline.set = false
    Goldeneyes.capture_mode = "baseline"
    send("show gold")
end

-- Check physical gold against expected ledger gold
function Goldeneyes.check_reward()
    if not Goldeneyes.baseline.set then
        Goldeneyes.echo("<yellow>Warning:<goldeneyesSilver> No baseline established yet. Establishing now. Type <goldeneyesGold>Goldeneyes check<goldeneyesSilver> after your next reward.")
        Goldeneyes.set_baseline()
        return
    end
    Goldeneyes.capture_mode = "check"
    send("show gold")
end

-- Process the captured 'show gold' string
function Goldeneyes.process_gold_capture(hand, bank)
    if type(Goldeneyes.baseline) ~= "table" then Goldeneyes.baseline = {hand = 0, bank = 0, set = false} end
    
    if type(hand) == "string" then hand = tonumber((string.gsub(hand, ",", ""))) end
    if type(bank) == "string" then bank = tonumber((string.gsub(bank, ",", ""))) end
    hand = hand or 0
    bank = bank or 0
    
    if Goldeneyes.capture_mode == "baseline" then
        Goldeneyes.baseline.hand = hand
        Goldeneyes.baseline.bank = bank
        Goldeneyes.baseline.total = Goldeneyes.total or 0 
        Goldeneyes.baseline.set = true
        Goldeneyes.echo("Baseline set. Hand: " .. Goldeneyes.format(hand) .. ", Bank: " .. Goldeneyes.format(bank))
        
    elseif Goldeneyes.capture_mode == "check" then
        local wealth_change = (hand + bank) - ((Goldeneyes.baseline.hand or 0) + (Goldeneyes.baseline.bank or 0))
        local tracked_change = (Goldeneyes.total or 0) - (Goldeneyes.baseline.total or 0)
        local hidden_profit = wealth_change + Goldeneyes.expenses - tracked_change
        
        if hidden_profit > 0 then
            Goldeneyes.echo("<orange>Hidden Reward Detected!<goldeneyesSilver> You gained <goldeneyesGold>" .. Goldeneyes.format(hidden_profit) .. "<goldeneyesSilver> gold.")
            Goldeneyes.plus(hidden_profit)
        elseif hidden_profit < 0 then
             Goldeneyes.echo("Math check negative (" .. Goldeneyes.format(hidden_profit) .. "). Did you spend gold we missed?")
        else
             Goldeneyes.echo("No hidden rewards found (Math is balanced).")
        end
        
        -- Update the baseline for the next check
        Goldeneyes.baseline.hand = hand
        Goldeneyes.baseline.bank = bank
        Goldeneyes.baseline.total = Goldeneyes.total
        Goldeneyes.expenses = 0 
    end
    Goldeneyes.capture_mode = nil
end

-- =========================================================================
-- UI & Display
-- Controls the help menu and the informational displays.
-- =========================================================================

-- Master display layout
-- Master display layout
function Goldeneyes.display()
    local status = Goldeneyes.enabled and "<green>ON<goldeneyesSilver>" or "<red>OFF<goldeneyesSilver>"
    local current_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
    local accountant = Goldeneyes.accountant or current_name
    local role = (accountant:lower() == current_name:lower()) and "<green>Me<goldeneyesSilver>" or ("<goldeneyesGold>" .. accountant:title() .. "<goldeneyesSilver>")
    local strat_text = (Goldeneyes.config.split_strategy == "even") and "<green>Even<goldeneyesSilver>" or "<yellow>Fair<goldeneyesSilver>"
    local cont = Goldeneyes.config.container or "pack"

    local elapsed = os.time() - Goldeneyes.starttime
    if elapsed < 1 then elapsed = 1 end
    local gph = math.floor((Goldeneyes.total / elapsed) * 3600)

    -- Header & Status Bar
    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho("\n<goldeneyesGold>                   G O L D E N E Y E S   L E D G E R                   <reset>")
    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho(string.format("\n<goldeneyesSilver>  Tracker: [%s] | Split: [%s] | Stash: [<goldeneyesGold>%s<goldeneyesSilver>] | Collector: [%s]", status, strat_text, cont:title(), role))
    cecho(string.format("\n"))
    cecho(string.format("\n<goldeneyesCopper>  Total Gold: <goldeneyesGold>%-15s <goldeneyesCopper>Gold/Hour: <goldeneyesGold>%s\n", Goldeneyes.format(Goldeneyes.total), Goldeneyes.format(gph)))

    if Goldeneyes.org.name then
        cecho(string.format("  <goldeneyesCopper>City/Org Tax  (<goldeneyesGold>%d%%<goldeneyesSilver>): <goldeneyesGold>%s\n", Goldeneyes.org.percent, Goldeneyes.format(Goldeneyes.org.gold)))
    end

    -- Active Shares Section
    if Goldeneyes.count(Goldeneyes.names) > 0 then 
        cecho("\n<goldeneyesCopper>  Active Shares:<reset>\n") 
        local shares = Goldeneyes.get_shares()
        for k, v in pairs(shares) do
            cecho("  <goldeneyesSilver>" .. string.format("%14s", k:title()) .. ": <goldeneyesGold>" .. Goldeneyes.format(v) .. "\n")
        end
    else
        cecho("\n<goldeneyesSilver>  No members currently tracked. Use <goldeneyesGold>gold group<goldeneyesSilver> to add.\n")
    end

    -- Debts & Unknowns Section
    local ledger_count = Goldeneyes.count(Goldeneyes.ledger)
    local unknown_count = Goldeneyes.count(Goldeneyes.unknown_ledger)

    if ledger_count > 0 or unknown_count > 0 then
        cecho("\n<goldeneyesCopper>  Pending Debts & Held Gold:<reset>\n")
        local all_holders = {}
        for k,v in pairs(Goldeneyes.ledger) do all_holders[k] = true end
        for k,v in pairs(Goldeneyes.unknown_ledger) do all_holders[k] = true end

        for k, _ in pairs(all_holders) do
            local debt = Goldeneyes.ledger[k] or 0
            local unknown = Goldeneyes.unknown_ledger[k] or 0
            local str = string.format("  <goldeneyesSilver>%14s: ", k:title())

            if debt > 0 then str = str .. "<orange>" .. Goldeneyes.format(debt) .. " gold " end
            if unknown > 0 then str = str .. "<red>(+" .. unknown .. " unknown piles!)" end
            cecho(str .. "\n")
        end
    end

    -- Footer
    cecho("<goldeneyesGold>=======================================================================<reset>\n")
    
    -- Safe trigger for custom prompts
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- Announce the current progress
function Goldeneyes.announce(channel)
    channel = channel and channel:lower() or "party"
    local cmd, message = "pt", ""
    
    if channel == "intrepid" then
        cmd = "it"
        message = "We have collected a total of " .. Goldeneyes.format(Goldeneyes.total) .. " gold so far."
    elseif channel == "say" then
        cmd = "say"
        message = "By my calculations, we have collected a total of " .. Goldeneyes.format(Goldeneyes.total) .. " gold sovereigns thus far."
    else
        cmd = "pt"
        message = "We have collected a total of " .. Goldeneyes.format(Goldeneyes.total) .. " gold so far."
    end
    send(cmd .. " " .. message)
end

-- Change split methodology
function Goldeneyes.set_strategy(strat)
    strat = strat and strat:lower() or "even"
    if strat == "even" or strat == "fair" then
        Goldeneyes.config.split_strategy = strat
        Goldeneyes.echo("Split strategy set to: <goldeneyesGold>" .. strat:title() .. "\n")
        cecho("  <goldeneyesGold>Even <goldeneyesSilver>split will divide the total gold pool equally among current members at distribution time.\n")
        cecho("  <goldeneyesGold>Fair <goldeneyesSilver>split will distribute gold based on when each person joined the party.\n")
        if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
    else
        Goldeneyes.echo("<goldeneyesSilver>Usage: <goldeneyesGold>Goldeneyes strategy <even|fair>")
    end
end

-- Designate the collector
function Goldeneyes.set_accountant(name)
    Goldeneyes.accountant = name:title()
    cecho("Collector set to <goldeneyesGold>" .. name)
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- Toggle click-to-add UI alerts
function Goldeneyes.togglealerts(val)
    local state = val:lower() == "on"
    Goldeneyes.config.party_alerts = state
    cecho("Party alerts are now " .. (state and "<green>ENABLED<goldeneyesSilver>" or "<red>DISABLED<goldeneyesSilver>"))
end

-- Toggle the entire tracker
function Goldeneyes.toggle(toggle_cmd)
    -- Check if the command was "on" OR "enabled"
    local state = (toggle_cmd:lower() == "on" or toggle_cmd:lower() == "enabled")
    Goldeneyes.enabled = state

    if state and Goldeneyes.count(Goldeneyes.names) == 0 and gmcp.Char and gmcp.Char.Name then
        Goldeneyes.add(gmcp.Char.Name.name:lower())
    end
    Goldeneyes.echo("Tracking " .. (state and "<goldeneyesGold>enabled" or "<red>disabled"))
    
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- Double-tap reset logic
-- Warning prompt for manual reset
function Goldeneyes.reset()
    cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <red>WARNING!<goldeneyesSilver> This will wipe ALL data (Total: " .. Goldeneyes.format(Goldeneyes.total) .. ").\n")
    cecho("<goldeneyesSilver>To proceed, type <goldeneyesGold>Goldeneyes reset confirm<reset>\n")
end

-- Wipes the memory arrays
function Goldeneyes.confirm_reset()
    Goldeneyes.names = {}
    Goldeneyes.paused = {}
    Goldeneyes.ledger = {}
    Goldeneyes.unknown_ledger = {}
    Goldeneyes.org = {name = false, percent = 0, gold = 0}
    Goldeneyes.total = 0
    Goldeneyes.expenses = 0
    Goldeneyes.starttime = os.time()
    Goldeneyes.pending_gold = {}

    if gmcp.Char and gmcp.Char.Name then Goldeneyes.add(gmcp.Char.Name.name) end
    Goldeneyes.set_baseline()
    Goldeneyes.save() -- Immediately commit the wipe to the JSON file
    Goldeneyes.echo("<red>Tracker has been reset.<reset>")
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- Final payout command
function Goldeneyes.distribute(channel)
    local cont = Goldeneyes.config.container or "pack"
    local shares = Goldeneyes.get_shares()
    local members = Goldeneyes.count(Goldeneyes.names)
    local my_name = gmcp.Char.Name.name:lower()
    
    -- Calculate the exact total of all shares (plus org tax) to withdraw from the container
    local total_withdraw = 0
    for k, v in pairs(shares) do
        total_withdraw = total_withdraw + math.floor(v)
    end
    
    -- Ensure we also pull out the org tax if one is set
    if Goldeneyes.org and Goldeneyes.org.name then
        total_withdraw = total_withdraw + math.floor(Goldeneyes.org.gold)
    end
    
    -- Withdraw the full hunt yield so your cut and org tax land in your inventory
    if cont:lower() ~= "none" and cont:lower() ~= "inventory" and total_withdraw > 0 then
        send("queue add eqbal get " .. total_withdraw .. " gold from " .. cont)
    end
    
    channel = channel and channel:lower() or "party"
    local cmd = "pt"
    local message = ""
    local silent = (channel == "none")
    
    if Goldeneyes.config.split_strategy == "even" then
        local single_share = 0
        for _, v in pairs(shares) do single_share = math.floor(v); break end
        
        if channel == "intrepid" then
            cmd = "it"
            message = string.format("Distributing %s gold across %d members. Expected even share: %s gold.", Goldeneyes.format(Goldeneyes.total), members, Goldeneyes.format(single_share))
        elseif channel == "say" then
            cmd = "say"
            message = string.format("I'll distribute our collected %s gold sovereigns now. Split evenly among the %d of us, we should each receive %s gold.", Goldeneyes.format(Goldeneyes.total), members, Goldeneyes.format(single_share))
        else
            cmd = "pt"
            message = string.format("Distributing %s gold across %d members. Expected even share: %s gold.", Goldeneyes.format(Goldeneyes.total), members, Goldeneyes.format(single_share))
        end
    else
        if channel == "intrepid" then
            cmd = "it"
            message = string.format("Distributing %s gold across %d members. Shares are prorated based on hunt participation.", Goldeneyes.format(Goldeneyes.total), members)
        elseif channel == "say" then
            cmd = "say"
            message = string.format("I'll distribute our collected %s gold sovereigns now across the %d of us, distributed fairly based on when you joined.", Goldeneyes.format(Goldeneyes.total), members)
        else
            cmd = "pt"
            message = string.format("Distributing %s gold across %d members. Shares are prorated based on hunt participation.", Goldeneyes.format(Goldeneyes.total), members)
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

    Goldeneyes.echo("Distributed gold from <goldeneyesGold>" .. cont)
    cecho("\n\n<goldeneyesSilver>Distribution commands queued. Auto-resetting tracker to prevent double payouts.\n")
    Goldeneyes.confirm_reset()
end

-- =========================================================================
-- Event Handlers & Hooks
-- =========================================================================
-- Hooks on user character load to configure initial states
function Goldeneyes_login_check()
    if not gmcp or not gmcp.Char or not gmcp.Char.Name then return end
    local my_name = gmcp.Char.Name.name:title()

    if Goldeneyes.enabled and Goldeneyes.count(Goldeneyes.names) == 0 then
        Goldeneyes.add(my_name)
    end
    
    if Goldeneyes.accountant == "Unknown" or Goldeneyes.accountant == "Solina" then
        Goldeneyes.accountant = my_name
    end

    if Goldeneyes.config.pickup then
        Goldeneyes.echo("Auto-pickup is <goldeneyesGold>ENABLED<goldeneyesSilver>.")
    end

    if not Goldeneyes.login_prompted and Goldeneyes.total > 0 then
        Goldeneyes.login_prompted = true
        cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <yellow>Welcome back! You have an active hunting ledger with " .. Goldeneyes.format(Goldeneyes.total) .. " gold.<reset>\n")
        cecho("       ")
        cechoLink("<red>[Start Fresh]", "Goldeneyes.confirm_reset()", "Wipe all data for a new hunt", true)
        cecho(" <goldeneyesSilver>| ")
        cechoLink("<green>[Keep Data]", "Goldeneyes.echo('Ledger preserved. Type \\'gold\\' to view.')", "Resume previous hunt", true)
        cecho("\n")
    end
end

-- Ensure we don't register multiple handlers on reload
if Goldeneyes.login_handler then killAnonymousEventHandler(Goldeneyes.login_handler) end
Goldeneyes.login_handler = registerAnonymousEventHandler("gmcp.Char.Name", "Goldeneyes_login_check")

-- Save hooks for application exit / game disconnection
if Goldeneyes.save_exit_handler then killAnonymousEventHandler(Goldeneyes.save_exit_handler) end
Goldeneyes.save_exit_handler = registerAnonymousEventHandler("sysExitEvent", "Goldeneyes.save")

if Goldeneyes.save_dc_handler then killAnonymousEventHandler(Goldeneyes.save_dc_handler) end
Goldeneyes.save_dc_handler = registerAnonymousEventHandler("sysDisconnectionEvent", "Goldeneyes.save")

-- =========================================================================
-- Dynamic Triggers & Aliases
-- These are used for all in-game event detection, such as gold pickups, 
-- expenses, and similar events.
-- =========================================================================
Goldeneyes.trigger_ids = Goldeneyes.trigger_ids or {}
Goldeneyes.alias_ids = Goldeneyes.alias_ids or {}

function Goldeneyes.create_triggers()
    -- Clean up existing triggers/aliases to prevent duplicates on reload
    for _, id in pairs(Goldeneyes.trigger_ids) do killTrigger(id) end
    for _, id in pairs(Goldeneyes.alias_ids) do killAlias(id) end
    Goldeneyes.trigger_ids = {}
    Goldeneyes.alias_ids = {}

    -- Trigger: Mystery Gold Pickups (Artifacts)
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^Some gold falls from the corpse and automatically flies into the hands of (\\w+)\\.", 
    [[
        local name_key = matches[2]:lower()
        if Goldeneyes.names[name_key] then
            Goldeneyes.unknown_ledger[name_key] = (Goldeneyes.unknown_ledger[name_key] or 0) + 1
            cecho(string.format("\n<red>[ALERT]: %s picked up a MYSTERY pile of gold! (Auto-loot artifact detected)", matches[2]))
            cecho("\n<red>       Please ask them how much they got and use 'Goldeneyes plus <amount>'.")
        end
    ]]))

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^.*sovereigns spills from the corpse, flying into the hands of.*", 
    [[
        cecho("\n<red>[ALERT]: Someone's artifact just auto-looted a MYSTERY pile of gold!<reset>")
    ]]))

    -- Trigger: Shop Purchases & Expenses
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You pay ([\\d,]+) gold sovereigns\\.$", [[ Goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You buy .* for ([\\d,]+) gold\\.$", [[ Goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    
    -- Trigger: Gold Given Away (Handover Resolution)
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You give ([\\d,]+) gold to (\\w+)", 
    [[ 
        local amount = tonumber((matches[2]:gsub(",", "")))
        local target = matches[3]:lower()
        local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"
        
        -- If we successfully gave gold to the accountant, clear it from our local debt
        if Goldeneyes.accountant and target == Goldeneyes.accountant:lower() then
            if Goldeneyes.ledger[my_name] then
                Goldeneyes.ledger[my_name] = Goldeneyes.ledger[my_name] - amount
                if Goldeneyes.ledger[my_name] <= 0 then Goldeneyes.ledger[my_name] = nil end
            end
            Goldeneyes.echo("Successfully handed over <goldeneyesGold>" .. Goldeneyes.format(amount) .. "<goldeneyesSilver> to accountant.")
        end
    ]]))

    -- Trigger: Handover Failure (Accountant Unavailable)
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^(?:Ahh, I am truly sorry, but I do not see anyone by that name here\\.|You cannot see that being here\\.|You cannot find anyone by that name here\\.)$", 
    [[
        local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"
        local acc = Goldeneyes.accountant and Goldeneyes.accountant:lower() or my_name
        
        -- If we have a local debt and we aren't the accountant, a failure message means our handover missed.
        if Goldeneyes.config.autohandover and acc ~= my_name and Goldeneyes.ledger[my_name] and Goldeneyes.ledger[my_name] > 0 then
            Goldeneyes.echo("<red>Handover failed! <goldeneyesSilver>The accountant isn't here. Stashing gold safely.")
            local cont = Goldeneyes.config.container or "pack"
            if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
                send("queue add eqbal put gold in " .. cont, false)
            end
            -- Note: We intentionally leave the debt in our ledger so the UI reminds us we have it!
        end
    ]]))

    -- Trigger: Gold Picked Up (You)
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You (?:pick|scoop) up ([\\d,]+) gold", 
    [[
        local amount = tonumber((matches[2]:gsub(",", "")))
        if amount then Goldeneyes.handle_loot(amount) end
    ]]))

    -- Trigger: Gold Dropped (Grab It)
    local grab_script = [[ 
        if Goldeneyes.enabled and Goldeneyes.config.pickup then 
            Goldeneyes.echo("Scooping loose gold.")
            send("queue add eqbal get gold", false) 
        end 
    ]]
    local grab_regex = "(?:^A.*sovereigns? spills? from the corpse|A pile of golden sovereigns twinkles and gleams\\.|There is.*pile of golden sovereigns here\\.|pile of .*sovereigns?)"
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger(grab_regex, grab_script))

    -- Trigger: Gold Received (Handover Resolution)
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^(\\w+) gives you ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if Goldeneyes.names[name_key] then
            -- They are tracked, handle normally
            Goldeneyes.plus(amount)
            if Goldeneyes.ledger[name_key] then
                Goldeneyes.ledger[name_key] = Goldeneyes.ledger[name_key] - amount
                cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: %s paid off %s (Remaining: %s).", name, Goldeneyes.format(amount), Goldeneyes.format(Goldeneyes.ledger[name_key])))
                if Goldeneyes.ledger[name_key] <= 0 then
                    Goldeneyes.ledger[name_key] = nil
                    cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: %s has settled their debt.", name))
                end
            else
                cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: Accepted %s gold from %s (No prior debt).", Goldeneyes.format(amount), name))
            end
        else
            -- They are NOT tracked. Hold the gold and ask!
            Goldeneyes.pending_gold = Goldeneyes.pending_gold or {}
            Goldeneyes.pending_gold[name_key] = (Goldeneyes.pending_gold[name_key] or 0) + amount
            
            cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <yellow>Received %s gold from an UNTRACKED person: %s.<reset>\n", Goldeneyes.format(amount), name))
            cecho("       ")
            cechoLink("<green>[Add to Tracker & Pot]", 'Goldeneyes.accept_pending("' .. name .. '")', "Track " .. name .. " and add " .. Goldeneyes.pending_gold[name_key] .. " to pot", true)
            cecho(" <goldeneyesSilver>| ")
            cechoLink("<red>[Ignore]", 'Goldeneyes.ignore_pending("' .. name .. '")', "Ignore this gold", true)
            cecho("\n")
        end
    ]]))

    -- Trigger: Gold Tracking Watchdog (Others)
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^(\\w+) (?:picks|scoops) up ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if Goldeneyes.names[name_key] then
            Goldeneyes.plus(amount, true) -- Silently add to local total so UI matches reality
            Goldeneyes.ledger[name_key] = (Goldeneyes.ledger[name_key] or 0) + amount
            cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <orange>ALERT<goldeneyesSilver>: <goldeneyesGold>%s<goldeneyesSilver> picked up <orange>%s<goldeneyesSilver> gold!", name, Goldeneyes.format(amount)))
        end
    ]]))
    -- 8a. Capture Gold (Start of message)
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You have [%d,]+ gold sovereign.*", 
    [[
        if Goldeneyes.capture_mode then
            -- Start a buffer with the first line
            Goldeneyes.gold_buffer = matches[1]

            -- Set a tiny 0.2 second delay to wait for any trailing lines to arrive
            if Goldeneyes.gold_capture_timer then killTimer(Goldeneyes.gold_capture_timer) end
            Goldeneyes.gold_capture_timer = tempTimer(0.2, function()
                local total_hand = 0
                local total_bank = 0

                for amount_str, context in string.gmatch(Goldeneyes.gold_buffer, "([%d,]+)%s+gold sovereigns? in([^0-9,]+)") do
                    local clean_amt = tonumber((string.gsub(amount_str, ",", "")))
                    if clean_amt then
                        if string.match(context, "inventory") or string.match(context, "container") then
                            total_hand = total_hand + clean_amt
                        elseif string.match(context, "bank") then
                            total_bank = total_bank + clean_amt
                        end
                    end
                end
                
                Goldeneyes.process_gold_capture(total_hand, total_bank)
                Goldeneyes.gold_buffer = nil
            end)
        end
    ]]))

    -- 8b. Capture trailing wrapped lines (The Spillover)
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^gold sovereigns? in.*", 
    [[
        if Goldeneyes.capture_mode and Goldeneyes.gold_buffer then
            -- Append the broken line to our buffer
            Goldeneyes.gold_buffer = Goldeneyes.gold_buffer .. " " .. matches[1]
        end
    ]]))
    
    -- Triggers: Interactive Party Prompts
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You have joined .+'s party\\.$", 
    [[
        if Goldeneyes.config.party_alerts then
            cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: You joined a party. ")
            cechoLink("<green>[Scan Group]", "Goldeneyes.scan_group()", "Auto-add party/group to ledger", true)
            cecho(" <goldeneyesSilver>| ")
            cechoLink("<yellow>[Set Accountant]", 'clearCmdLine() appendCmdLine("Goldeneyes accountant ")', "Designate the collector", true)
            cecho("\n")
        end
    ]]))

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You have left your party\\.$", 
    [[
        if Goldeneyes.config.party_alerts then
            cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: You left the party. ")
            cechoLink("<red>[Reset Tracker]", "Goldeneyes.reset()", "Wipe all current ledger data", true)
            cecho("\n")
        end
    ]]))

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^\\(Party\\): (\\w+) has joined your party\\.$", 
    [[
        if Goldeneyes.config.party_alerts then
            local name = matches[2]
            cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <goldeneyesGold>" .. name .. " <goldeneyesSilver>joined the party. ")
            cechoLink("<green>[Add to Tracker]", 'Goldeneyes.add("' .. name .. '")', "Add " .. name .. " to the gold split", true)
            cecho("\n")
        end
    ]]))

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^\\(Party\\): (\\w+) has left your party\\.$", 
    [[
        local name = matches[2]
        if Goldeneyes.config.party_alerts and Goldeneyes.names[name:lower()] then
            cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <goldeneyesGold>" .. name .. " <goldeneyesSilver>left the party. ")
            cechoLink("<orange>[Remove from Tracker]", 'Goldeneyes.remove("' .. name .. '")', "Remove " .. name .. " from the gold split", true)
            cecho("\n")
        end
    ]]))

-- =========================================================================
-- In-Game Commands & Help Interface
-- Powers the text that appears when you type "Goldeneyes help" in game, as well as
-- the various toggles and commands you can use on the fly without editing your config.
-- =========================================================================
function Goldeneyes.help()
    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho("\n<goldeneyesGold>                    G O L D E N E Y E S   H E L P                      <reset>")
    cecho("\n<goldeneyesGold>=======================================================================<reset>\n")
    
    cecho("\n<goldeneyesSilver>Goldeneyes is a robust Mudlet ledger for Achaean hunting parties.")
    cecho("\n<goldeneyesSilver>Commands work with either <goldeneyesGold>Goldeneyes<goldeneyesSilver> or <goldeneyesGold>gold<goldeneyesSilver>.")
    cecho("\n<goldeneyesSilver>Permanent settings (like colors and defaults) are configured in the")
    cecho("\n<goldeneyesGold>Goldeneyes.config<goldeneyesSilver> block at the top of the Lua script.<reset>\n")

    cecho("\n<goldeneyesCopper>Basic Controls:<reset>")
    cecho("\n  <goldeneyesGold>gold <on|off>               <reset>- Turn tracker on/off.")
    cecho("\n  <goldeneyesGold>gold reset                  <reset>- Reset all totals (enter twice to confirm).")
    cecho("\n  <goldeneyesGold>gold report [channel]       <reset>- Announce totals (Channels: party, intrepid, say).")

    cecho("\n\n<goldeneyesCopper>Group & Party Management:<reset>")
    cecho("\n  <goldeneyesGold>gold strategy <even|fair>   <reset>- Set split method (Default: even).")
    cecho("\n  <goldeneyesGold>gold group                  <reset>- Auto-add party, group, and intrepid members.")
    cecho("\n  <goldeneyesGold>gold add <name>             <reset>- Add a person to the split list.")
    cecho("\n  <goldeneyesGold>gold remove <name>          <reset>- Remove a person from the list.")
    cecho("\n  <goldeneyesGold>gold pause <name>           <reset>- Pause tracking for a member.")
    cecho("\n  <goldeneyesGold>gold unpause <name>         <reset>- Resume tracking for a member.")

    cecho("\n\n<goldeneyesCopper>Loot & Accounting Automation:<reset>")
    cecho("\n  <goldeneyesGold>gold alerts <on|off>        <reset>- Toggle clickable party join/leave prompts.")
    cecho("\n  <goldeneyesGold>gold accountant <name>      <reset>- Designate the collector (Default: You).")
    cecho("\n  <goldeneyesGold>gold autohandover <on|off>  <reset>- Automatically give loot to collector.")
    cecho("\n  <goldeneyesGold>gold autoloot <on|off>      <reset>- Toggle auto-looting.")
    cecho("\n  <goldeneyesGold>gold container <name>       <reset>- Set gold container (e.g., 'pack').")
    cecho("\n  <goldeneyesGold>gold stash                  <reset>- Move all carried gold to container.")
    cecho("\n  <goldeneyesGold>gold distribute [channel]   <reset>- Empty container and share gold.")

    cecho("\n\n<goldeneyesCopper>Advanced Math & Checks:<reset>")
    cecho("\n  <goldeneyesGold>gold calc <amt> <#>         <reset>- Quick math to split an amount of gold.")
    cecho("\n  <goldeneyesGold>gold check                  <reset>- Capture 'Show Gold' to find hidden rewards.")
    cecho("\n  <goldeneyesGold>gold plus <amount>          <reset>- Manually add to Total.")
    cecho("\n  <goldeneyesGold>gold minus <amount>         <reset>- Manually subtract from Total.")

    cecho("\n<goldeneyesGold>=======================================================================<reset>\n")
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- Master Alias: Route all user commands to functions
    table.insert(Goldeneyes.alias_ids, tempAlias("^(?:Goldeneyes|gold)(?:\\s+(.*))?$", 
    [[
        local args_str = matches[2] or ""
        local args = args_str:split(" ")
        local cmd = args[1] and args[1]:lower() or ""

        if cmd == "" then Goldeneyes.display()
        elseif cmd == "help" then Goldeneyes.help()
        elseif cmd == "on" or cmd == "off" or cmd == "enabled" or cmd == "disabled" then Goldeneyes.toggle(cmd)
        elseif cmd == "autoloot" then Goldeneyes.togglepickup(args[2] or "")
        elseif cmd == "container" then 
            if args[2] then Goldeneyes.setcontainer(args[2]) else cecho("\n<goldeneyesSilver>Usage: <goldeneyesGold>Goldeneyes container <name>") end
        elseif cmd == "stash" then Goldeneyes.stash()
        elseif cmd == "add" then if args[2] then Goldeneyes.add(args[2]) end
        elseif cmd == "party" or cmd == "group" then Goldeneyes.scan_group()
        elseif cmd == "remove" then if args[2] then Goldeneyes.remove(args[2]) end
        elseif cmd == "plus" then local amt = tonumber(args[2]); if amt then Goldeneyes.plus(amt) end
        elseif cmd == "minus" then local amt = tonumber(args[2]); if amt then Goldeneyes.minus(amt) end
        elseif cmd == "pause" then if args[2] then Goldeneyes.pause(args[2]) end
        elseif cmd == "unpause" then if args[2] then Goldeneyes.unpause(args[2]) end
        elseif cmd == "reset" then 
            if args[2] == "confirm" then Goldeneyes.confirm_reset() else Goldeneyes.reset() end
        elseif cmd == "distribute" then Goldeneyes.distribute(args[2])
        elseif cmd == "snapshot" then Goldeneyes.start_snapshot()
        elseif cmd == "check" then Goldeneyes.check_reward()
        elseif cmd == "report" then Goldeneyes.announce(args[2])
        elseif cmd == "accountant" then 
            if args[2] then Goldeneyes.set_accountant(args[2]) else cecho("\n<goldeneyesSilver>Current Accountant: <goldeneyesGold>" .. Goldeneyes.accountant) end
        elseif cmd == "loot" then 
            local amt = tonumber(args[2]); if amt then Goldeneyes.handle_loot(amt) else cecho("\n<goldeneyesSilver>Usage: <goldeneyesGold>Goldeneyes loot <amount>") end
        elseif cmd == "autohandover" then Goldeneyes.toggle_handover(args[2] or "")
        elseif cmd == "strategy" then Goldeneyes.set_strategy(args[2])
        elseif cmd == "alerts" then Goldeneyes.togglealerts(args[2] or "")
        elseif cmd == "profile" then 
            if args[2] == "save" then 
                Goldeneyes.save()
                cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: Profile exported successfully.\n")
            elseif args[2] == "load" then 
                Goldeneyes.load()
                cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: Profile loaded successfully.\n")
            end
        elseif cmd == "calc" then Goldeneyes.calc(args[2], args[3])
        else cecho("\n<goldeneyesSilver>Unknown command. Try <goldeneyesGold>Goldeneyes help<goldeneyesSilver>.") end
    ]]))
end

-- =========================================================================
-- Initialization
-- This section runs once when the script is loaded to set up the initial state,
-- load saved data, and prepare the system for use.
-- =========================================================================
-- Initialize the triggers
Goldeneyes.create_triggers()
-- Load the saved configuration to overwrite defaults
Goldeneyes.load()
-- Inform user it successfully loaded
Goldeneyes.echo("Loaded Successfully!")