-- =========================================================================
-- GOLDENEYES: Gold Tracking & Distribution Utility
-- A robust Mudlet ledger for Achaean hunting parties.
-- Author: Solina (https://github.com/solina-the-hawk/Goldeneyes/)
-- Version: 1.3.0
-- =========================================================================
Goldeneyes = Goldeneyes or {}

-- =========================================================================
-- Configuration
-- These are default preferences you can safely edit if you wish. After you've 
-- set them in game, your own settings will save and load with your profile.
-- =========================================================================
Goldeneyes.config = Goldeneyes.config or {
    -- stash: The default container into which to stash group gold. 
    -- (Recommendation: Use a dedicated container separate from your personal gold!)
    stash = "pack",
    -- wallet: Optional container to automatically store your personal cut of the gold.
    wallet = "pouch",
    -- pickup: Whether or not to default to picking up gold that we see automatically.
    pickup = true,
    -- autohandover: Whether or not to default to handing gold over immediately to the accountant.
    autohandover = false,
    -- loot_delay: How many seconds to wait before auto-looting to avoid bashing script queue-clears.
    loot_delay = 0.5,
    -- split_strategy: What split strategy we prefer for distributing earned gold. Even is most common.
    split_strategy = "even",
    -- party_alerts: Whether to alert you with clickable prompts when party members join/leave.
    party_alerts = true,
    -- colors: What colors to use to highlight different elements of the Goldeneyes display.
    colors = {
        goldeneyesGold   = {255, 215, 0},
        goldeneyesSilver = {248, 248, 255},
        goldeneyesCopper = {184, 115, 51},
    }
}

for name, rgb in pairs(Goldeneyes.config.colors) do
    color_table[name] = rgb
end

-- =========================================================================
-- Runtime States
-- Internal variables used for math and tracking.
-- =========================================================================
if Goldeneyes.enabled == nil then Goldeneyes.enabled = true end
Goldeneyes.names = Goldeneyes.names or {}
Goldeneyes.paused = Goldeneyes.paused or {}
Goldeneyes.total = Goldeneyes.total or 0
Goldeneyes.starttime = Goldeneyes.starttime or os.time()
Goldeneyes.ledger = Goldeneyes.ledger or {}
Goldeneyes.unknown_ledger = Goldeneyes.unknown_ledger or {}
Goldeneyes.snapshot = Goldeneyes.snapshot or {hand = 0, bank = 0, phase = nil}
Goldeneyes.baseline = Goldeneyes.baseline or {hand = 0, bank = 0, set = false}
Goldeneyes.expenses = Goldeneyes.expenses or 0
Goldeneyes.reset_pending = false
Goldeneyes.pending_gold = Goldeneyes.pending_gold or {}
Goldeneyes.org = Goldeneyes.org or {name = false, percent = 0, gold = 0, mode = "pot", taxable_base = 0}
Goldeneyes.org_debts = Goldeneyes.org_debts or {}

local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
Goldeneyes.accountant = Goldeneyes.accountant or my_name

-- =========================================================================
-- Helper Functions
-- =========================================================================

function Goldeneyes.count(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function Goldeneyes.echo(x)
    cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: " .. x .. "<reset>")
end

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

function Goldeneyes.showprompt() end

-- =========================================================================
-- Profile Management
-- Saves and loads configuration state to protect against client crashes.
-- =========================================================================

function Goldeneyes.get_save_path()
    return getMudletHomeDir() .. "/Goldeneyes-Data.lua"
end

function Goldeneyes.save()
    local baseDir = getMudletHomeDir() .. "/Goldeneyes"
    if not lfs.attributes(baseDir) then lfs.mkdir(baseDir) end
    
    local filepath = baseDir .. "/Goldeneyes_Profile.json"
    
    local export_config = {}
    for k, v in pairs(Goldeneyes.config) do
        if k ~= "colors" then export_config[k] = v end
    end

    local data = {
        enabled = Goldeneyes.enabled,
        config = export_config,
        names = Goldeneyes.names,
        paused = Goldeneyes.paused,
        total = Goldeneyes.total,
        org = Goldeneyes.org,
        org_debts = Goldeneyes.org_debts,
        ledger = Goldeneyes.ledger,
        unknown_ledger = Goldeneyes.unknown_ledger,
        baseline = Goldeneyes.baseline,
        expenses = Goldeneyes.expenses,
        accountant = Goldeneyes.accountant,
        starttime = Goldeneyes.starttime,
    }
    
    local file = io.open(filepath, "w")
    if file then
        file:write(yajl.to_string(data))
        file:close()
    end
end

function Goldeneyes.load()
    local filepath = getMudletHomeDir() .. "/Goldeneyes/Goldeneyes_Profile.json"
    local file = io.open(filepath, "r")
    
    if not file then
        Goldeneyes.echo("<red>(Error)<reset>: No Goldeneyes_Profile.json found to load! Type <yellow>Goldeneyes profile save<reset> to create one.")
        return 
    end

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
    Goldeneyes.org_debts = data.org_debts or Goldeneyes.org_debts or {}
    
    -- Legacy data migration handling
    if Goldeneyes.org and Goldeneyes.org.held and Goldeneyes.org.name then
        Goldeneyes.org_debts[Goldeneyes.org.name] = (Goldeneyes.org_debts[Goldeneyes.org.name] or 0) + Goldeneyes.org.held
    end
    if Goldeneyes.org then Goldeneyes.org.held = nil end
    
    Goldeneyes.ledger = data.ledger or Goldeneyes.ledger
    Goldeneyes.unknown_ledger = data.unknown_ledger or Goldeneyes.unknown_ledger
    Goldeneyes.baseline = data.baseline or Goldeneyes.baseline
    Goldeneyes.expenses = data.expenses or Goldeneyes.expenses
    Goldeneyes.accountant = data.accountant or Goldeneyes.accountant
    Goldeneyes.starttime = data.starttime or Goldeneyes.starttime
    
    if data.config then
        for k, v in pairs(data.config) do
            if k ~= "colors" then 
                Goldeneyes.config[k] = v
            end
        end
    end
end

-- =========================================================================
-- Ledger & Math Logic
-- =========================================================================

function Goldeneyes.get_shares()
    local shares = {}
    local count = Goldeneyes.count(Goldeneyes.names)
    if count == 0 then return shares end
    
    local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"

    if Goldeneyes.config.split_strategy == "even" then
        if Goldeneyes.org.name then
            local taxable = Goldeneyes.org.taxable_base or 0
            if Goldeneyes.org.mode == "pot" then
                Goldeneyes.org.gold = taxable * (Goldeneyes.org.percent / 100)
            elseif Goldeneyes.org.mode == "personal" and Goldeneyes.names[my_name] then
                local base_even_share = taxable / count
                Goldeneyes.org.gold = base_even_share * (Goldeneyes.org.percent / 100)
            else
                Goldeneyes.org.gold = 0
            end
        else
            Goldeneyes.org.gold = 0
        end

        local player_pool = 0
        for k, v in pairs(Goldeneyes.names) do 
            player_pool = player_pool + v 
        end
        
        if Goldeneyes.org.name and Goldeneyes.org.mode == "personal" then
            player_pool = player_pool + Goldeneyes.org.gold
        end

        local even_share = player_pool / count
        for k, _ in pairs(Goldeneyes.names) do
            if k == my_name and Goldeneyes.org.name and Goldeneyes.org.mode == "personal" then
                shares[k] = even_share - Goldeneyes.org.gold
            else
                shares[k] = even_share
            end
        end
    else 
        for k, v in pairs(Goldeneyes.names) do
            shares[k] = v
        end
    end
    return shares
end

function Goldeneyes.plus(amt, noecho)
    local original_amt = amt
    local x = Goldeneyes
    local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"

    local pot_cut = 0
    if x.org.name and x.org.mode == "pot" then
        pot_cut = original_amt * (x.org.percent/100)
        x.org.gold = x.org.gold + pot_cut
        amt = original_amt - pot_cut
    end

    local num = Goldeneyes.count(x.names)
    if num > 0 then
        local split_share = amt / num
        for k, v in pairs(x.names) do
            if k == my_name and x.org.name and x.org.mode == "personal" then
                local personal_cut = split_share * (x.org.percent/100)
                x.org.gold = x.org.gold + personal_cut
                x.names[k] = v + (split_share - personal_cut)
            else
                x.names[k] = v + split_share
            end
        end
    end

    x.total = x.total + original_amt
    x.org.taxable_base = (x.org.taxable_base or 0) + original_amt 
    
    x.pickup_count = (x.pickup_count or 0) + 1
    x.first_pickup_time = x.first_pickup_time or os.time()
    
    if not noecho then x.echo("<goldeneyesGold>" .. Goldeneyes.format(original_amt) .. " <goldeneyesSilver>gold added.") end
    if type(x.showprompt) == "function" then x.showprompt() end
end

function Goldeneyes.minus(amt)
    local original_amt = amt
    local x = Goldeneyes
    local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"

    local pot_cut = 0
    if x.org.name and x.org.mode == "pot" then
        pot_cut = original_amt * (x.org.percent/100)
        x.org.gold = x.org.gold - pot_cut
        amt = original_amt - pot_cut
    end

    local num = x.count(x.names)
    if num > 0 then
        local split_share = amt / num
        for k, v in pairs (x.names) do 
            if k == my_name and x.org.name and x.org.mode == "personal" then
                local personal_cut = split_share * (x.org.percent/100)
                x.org.gold = x.org.gold - personal_cut
                x.names[k] = v - (split_share - personal_cut)
            else
                x.names[k] = v - split_share 
            end
        end
    end

    x.total = x.total - original_amt
    x.org.taxable_base = (x.org.taxable_base or 0) - original_amt 
    
    x.echo("<goldeneyesGold>" .. Goldeneyes.format(original_amt) .. " <goldeneyesSilver>gold removed.")
    if type(x.showprompt) == "function" then x.showprompt() end
end

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

function Goldeneyes.add_expense(amt)
    if Goldeneyes.enabled then
        Goldeneyes.expenses = Goldeneyes.expenses + amt
        Goldeneyes.echo("Tracked expense of <orange>" .. Goldeneyes.format(amt) .. "<goldeneyesSilver> gold.")
    end
end

-- =========================================================================
-- Party & Group Management
-- =========================================================================

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

function Goldeneyes.pause(name)
    name = name:lower()
    if Goldeneyes.names[name] ~= nil then
        Goldeneyes.echo("Gold tracking for <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>paused.")
        Goldeneyes.paused[name] = Goldeneyes.names[name]
        Goldeneyes.names[name] = nil
    end
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

function Goldeneyes.unpause(name)
    name = name:lower()
    if Goldeneyes.paused[name] then
        Goldeneyes.echo("Gold tracking for <goldeneyesGold>" .. name:title() .. " <goldeneyesSilver>unpaused.")
        Goldeneyes.names[name] = Goldeneyes.paused[name]
        Goldeneyes.paused[name] = nil
    end
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

function Goldeneyes.scan_group()
    Goldeneyes.echo("Scanning party, group, and intrepid members...")
    send("party members", false)
    send("group", false)
    send("intrepid", false)

    Goldeneyes.scan_triggers = Goldeneyes.scan_triggers or {}

    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^\\s+([A-Z][a-z]+)", function()
        local name = matches[2]
        if name ~= "Party" and name ~= "The" and name ~= "Your" then Goldeneyes.add(name) end
    end))

    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^You are following ([A-Z][a-z]+)\\.", function()
        Goldeneyes.add(matches[2])
    end))
    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^([A-Z][a-z]+) is following you\\.", function()
        Goldeneyes.add(matches[2])
    end))

    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^Leader\\s*:\\s*([A-Z][a-z]+)", function()
        Goldeneyes.add(matches[2])
    end))

    table.insert(Goldeneyes.scan_triggers, tempRegexTrigger("^Members\\s*:\\s*(.*)", function()
        local members_str = matches[2]
        for name in string.gmatch(members_str, "([A-Z][a-z]+)") do
            if name ~= "And" and name ~= "You" then Goldeneyes.add(name) end
        end
    end))

    tempTimer(1.5, function()
        if Goldeneyes.scan_triggers then
            for _, id in ipairs(Goldeneyes.scan_triggers) do killTrigger(id) end
            Goldeneyes.scan_triggers = {}
        end
        Goldeneyes.echo("Group scan complete.")
        if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
    end)
end

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

function Goldeneyes.ignore_pending(name)
    local name_key = name:lower()
    if Goldeneyes.pending_gold[name_key] then
        Goldeneyes.pending_gold[name_key] = nil
        Goldeneyes.echo("Ignored gold from " .. name:title() .. ".")
    end
end

function Goldeneyes.set_org(name, percent, mode)
    local is_disable = (not name or name:lower() == "off" or name:lower() == "none")
    
    -- Mid-hunt switch handling: Flush active tax to debts and physicalize withdrawal
    if Goldeneyes.org.name and Goldeneyes.org.gold > 0 then
        local old_name = Goldeneyes.org.name
        local is_changing = is_disable or (name and old_name:lower() ~= name:lower())
        
        if is_changing then
            local old_gold = math.floor(Goldeneyes.org.gold)
            if old_gold > 0 then
                Goldeneyes.org_debts[old_name] = (Goldeneyes.org_debts[old_name] or 0) + old_gold
                
                local cont = Goldeneyes.config.stash or "pack"
                local wallet = Goldeneyes.config.wallet or "none"
                
                if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
                    send("queue add eqbal get " .. old_gold .. " gold from " .. cont)
                    if wallet:lower() ~= "none" and wallet:lower() ~= "inventory" then
                        if wallet:find("/") then
                            Goldeneyes.store_custom(wallet, old_gold)
                        else
                            send("queue add eqbal put " .. old_gold .. " gold in " .. wallet)
                        end
                    end
                end
                Goldeneyes.echo("Secured active un-distributed tax (<goldeneyesGold>" .. Goldeneyes.format(old_gold) .. "<goldeneyesSilver> gold) for <goldeneyesGold>" .. old_name .. "<goldeneyesSilver>.")
            end
            Goldeneyes.org.gold = 0
            Goldeneyes.org.taxable_base = 0 
        end
    end

    if is_disable then
        Goldeneyes.org = {name = false, percent = 0, gold = 0, mode = "pot", taxable_base = 0} 
        Goldeneyes.echo("Organization share <red>DISABLED<goldeneyesSilver>.")
        Goldeneyes.save()
        return
    end

    percent = tonumber(percent)
    if not percent or percent <= 0 or percent > 100 then
        Goldeneyes.echo("<goldeneyesSilver>Usage: <goldeneyesGold>gold org <name> <percent> [pot|personal]")
        return
    end

    mode = mode and mode:lower() or "pot"
    if mode ~= "pot" and mode ~= "personal" then mode = "pot" end

    Goldeneyes.org.name = name:title()
    Goldeneyes.org.percent = percent
    Goldeneyes.org.mode = mode

    local mode_text = (mode == "personal") and "Personal Share" or "Total Pot"

    Goldeneyes.echo(string.format("Organization share set for <goldeneyesGold>%s<goldeneyesSilver>.", name:title()))
    cecho(string.format("\n  <goldeneyesSilver>Deducting <goldeneyesGold>%d%%<goldeneyesSilver> from the <goldeneyesGold>%s<goldeneyesSilver>.", percent, mode_text))
    Goldeneyes.save()
end

function Goldeneyes.pay_org(target)
    if target and target:lower() == "all" then
        for k, v in pairs(Goldeneyes.org_debts) do
            Goldeneyes.echo("Cleared <goldeneyesGold>" .. Goldeneyes.format(v) .. "<goldeneyesSilver> held gold for <goldeneyesGold>" .. k .. "<goldeneyesSilver>.")
        end
        Goldeneyes.org_debts = {}
        Goldeneyes.save()
    elseif target and target ~= "" then
        local t_lower = target:lower()
        local found = false
        for k, v in pairs(Goldeneyes.org_debts) do
            if k:lower() == t_lower then
                Goldeneyes.echo("Cleared <goldeneyesGold>" .. Goldeneyes.format(v) .. "<goldeneyesSilver> held gold for <goldeneyesGold>" .. k .. "<goldeneyesSilver>.")
                Goldeneyes.org_debts[k] = nil
                found = true
                break
            end
        end
        if not found then Goldeneyes.echo("No held funds found for '" .. target .. "'.") end
        Goldeneyes.save()
    else
        if Goldeneyes.org.name and Goldeneyes.org_debts[Goldeneyes.org.name] then
            local amt = Goldeneyes.org_debts[Goldeneyes.org.name]
            Goldeneyes.echo("Cleared <goldeneyesGold>" .. Goldeneyes.format(amt) .. "<goldeneyesSilver> held gold for <goldeneyesGold>" .. Goldeneyes.org.name .. "<goldeneyesSilver>.")
            Goldeneyes.org_debts[Goldeneyes.org.name] = nil
            Goldeneyes.save()
        else
            Goldeneyes.echo("No held funds for your active org. Use <goldeneyesGold>gold org deposit <name><goldeneyesSilver> or <goldeneyesGold>all<goldeneyesSilver>.")
        end
    end
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- =========================================================================
-- Inventory & Loot Management
-- =========================================================================

function Goldeneyes.setstash(input)
    Goldeneyes.config.stash = input
    if input:find("/") then
        Goldeneyes.echo("Group stash set to custom sequence.")
        cecho("\n  <grey>Sequence: <goldeneyesGold>" .. input .. "\n")
    else
        Goldeneyes.echo("Group stash set to: <goldeneyesGold>" .. input)
    end
    cecho("\n<goldeneyesSilver>  (Tip: For accurate payouts, use a dedicated container separate from your personal gold!)\n")
    Goldeneyes.save()
end

function Goldeneyes.setwallet(input)
    Goldeneyes.config.wallet = input
    if input:find("/") then
        Goldeneyes.echo("Personal wallet set to custom sequence.")
        cecho("\n  <grey>Sequence: <goldeneyesGold>" .. input .. "\n")
    else
        Goldeneyes.echo("Personal wallet set to: <goldeneyesGold>" .. input)
    end
    Goldeneyes.save()
end

function Goldeneyes.store_custom(sequence, amount)
    amount = amount or "gold"
    local parsed_sequence = sequence:gsub("<amount>", tostring(amount))
    local commands = parsed_sequence:split("/")
    
    for _, cmd in ipairs(commands) do
        cmd = cmd:gsub("^%s+", ""):gsub("%s+$", "")
        send("queue add eqbal " .. cmd)
    end
end

function Goldeneyes.stash_gold()
    local cont = Goldeneyes.config.stash or "pack"
    if cont:find("/") then
        Goldeneyes.store_custom(cont, "gold")
        Goldeneyes.echo("Attempting to stash gold using custom sequence.")
    else
        send("queue add eqbal put gold in " .. cont)
        Goldeneyes.echo("Attempting to stash gold in your <goldeneyesGold>" .. cont)
    end
end

function Goldeneyes.wallet_stash()
    local wallet = Goldeneyes.config.wallet or "none"
    if wallet:lower() == "none" or wallet:lower() == "inventory" then
        Goldeneyes.echo("No personal wallet configured. Use <goldeneyesGold>gold wallet <name><goldeneyesSilver> to set one.")
        return
    end

    if wallet:find("/") then
        Goldeneyes.store_custom(wallet, "gold")
        Goldeneyes.echo("Attempting to stow loose gold using your wallet sequence.")
    else
        send("queue add eqbal put gold in " .. wallet)
        Goldeneyes.echo("Attempting to stow loose gold in your <goldeneyesGold>" .. wallet)
    end
end

function Goldeneyes.togglepickup(val)
    local state = val:lower() == "on"
    Goldeneyes.config.pickup = state
    Goldeneyes.echo("Auto-pickup is now " .. (state and "<green>ENABLED<goldeneyesSilver>" or "<red>DISABLED<goldeneyesSilver>"))
end

function Goldeneyes.toggle_handover(val)
    if val == "on" then
        Goldeneyes.config.autohandover = true
        Goldeneyes.echo("Auto-Handover <green>ENABLED<goldeneyesSilver>. I will give gold to " .. Goldeneyes.accountant)
    else
        Goldeneyes.config.autohandover = false
        Goldeneyes.echo("Auto-Handover <red>DISABLED<goldeneyesSilver>.")
    end
end

function Goldeneyes.handle_loot(amt)
    if not Goldeneyes.enabled then return end
    local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
    local my_name_lower = my_name:lower()
    local acc = Goldeneyes.accountant or my_name
    local cont = Goldeneyes.config.stash or "pack"

    Goldeneyes.plus(amt, true)

    if acc:lower() == my_name_lower then
        Goldeneyes.echo("Gold added to ledger. New total is <goldeneyesGold>" .. Goldeneyes.format(Goldeneyes.total) .. "<goldeneyesSilver> gold.")
        
        if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
            if cont:find("/") then
                Goldeneyes.store_custom(cont, amt)
            else
                send("queue add eqbal put " .. amt .. " gold in " .. cont, false)
            end
        end
    else
        Goldeneyes.ledger[my_name_lower] = (Goldeneyes.ledger[my_name_lower] or 0) + amt

        if Goldeneyes.config.autohandover then
            send("queue add eqbal give " .. amt .. " gold to " .. acc)
            Goldeneyes.echo("Looted <goldeneyesGold>"..Goldeneyes.format(amt).."<goldeneyesSilver>. Attempting to hand over to <goldeneyesGold>"..acc)
        else
            send("pt I picked up " .. Goldeneyes.format(amt) .. " gold.")
            Goldeneyes.echo("Looted <goldeneyesGold>"..Goldeneyes.format(amt).."<goldeneyesSilver>. Kept locally (Added to Debt).")
            if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
                if cont:find("/") then
                    Goldeneyes.store_custom(cont, amt)
                else
                    send("queue add eqbal put " .. amt .. " gold in " .. cont, false)
                end
            end
        end
    end
end

function Goldeneyes.set_delay(val)
    local delay = tonumber(val)
    if delay and delay >= 0 then
        Goldeneyes.config.loot_delay = delay
        Goldeneyes.echo("Auto-loot delay set to <goldeneyesGold>" .. delay .. "<goldeneyesSilver> seconds.")
        Goldeneyes.save()
    else
        Goldeneyes.echo("<goldeneyesSilver>Usage: <goldeneyesGold>gold delay <seconds><goldeneyesSilver> (e.g., gold delay 0.8)")
    end
end

-- =========================================================================
-- Snapshots & Checks
-- =========================================================================

function Goldeneyes.start_snapshot()
    Goldeneyes.set_baseline()
end

function Goldeneyes.set_baseline()
    Goldeneyes.baseline.set = false
    Goldeneyes.capture_mode = "baseline"
    send("show gold")
end

function Goldeneyes.check_reward()
    if not Goldeneyes.baseline.set then
        Goldeneyes.echo("<yellow>Warning:<goldeneyesSilver> No baseline established yet. Establishing now. Type <goldeneyesGold>Goldeneyes check<goldeneyesSilver> after your next reward.")
        Goldeneyes.set_baseline()
        return
    end
    Goldeneyes.capture_mode = "check"
    send("show gold")
end

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
        
        Goldeneyes.baseline.hand = hand
        Goldeneyes.baseline.bank = bank
        Goldeneyes.baseline.total = Goldeneyes.total
        Goldeneyes.expenses = 0 
    end
    Goldeneyes.capture_mode = nil
end

-- =========================================================================
-- UI & Display
-- =========================================================================

function Goldeneyes.display()
    local status = Goldeneyes.enabled and "<green>ON<goldeneyesSilver>" or "<red>OFF<goldeneyesSilver>"
    local current_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
    local accountant = Goldeneyes.accountant or current_name
    local role = (accountant:lower() == current_name:lower()) and "<green>Me<goldeneyesSilver>" or ("<goldeneyesGold>" .. accountant:title() .. "<goldeneyesSilver>")
    local strat_text = (Goldeneyes.config.split_strategy == "even") and "<green>Even<goldeneyesSilver>" or "<yellow>Fair<goldeneyesSilver>"
    local cont = Goldeneyes.config.stash or "pack"
    local wallet = Goldeneyes.config.wallet or "Pouch"

    local unknown_count = Goldeneyes.count(Goldeneyes.unknown_ledger)

    local gph_display = "<yellow>Calculating..."
    if (Goldeneyes.pickup_count or 0) >= 2 and Goldeneyes.first_pickup_time then
        local elapsed = os.time() - Goldeneyes.first_pickup_time
        if elapsed >= 60 then
            local gph = math.floor((Goldeneyes.total / elapsed) * 3600)
            gph_display = "<goldeneyesGold>" .. Goldeneyes.format(gph)
        end
    end

    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho("\n<goldeneyesGold>                   G O L D E N E Y E S   L E D G E R                   <reset>")
    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho(string.format("\n<goldeneyesSilver>  Tracker: [%s] | Split: [%s] | Collector: [%s]", status, strat_text, role))
    
    local cont_display = cont:find("/") and "Custom Sequence" or cont:title()
    local wallet_display = wallet:find("/") and "Custom Sequence" or wallet:title()
    
    cecho(string.format("\n<goldeneyesSilver>  Group Stash: [<goldeneyesGold>%s<goldeneyesSilver>] | Personal Wallet: [<goldeneyesGold>%s<goldeneyesSilver>]", cont_display, wallet_display))
    
    if cont:find("/") or wallet:find("/") then
        cecho("\n<grey>  (Use <goldeneyesGold>gold stash <name><grey> or <goldeneyesGold>gold wallet <name><grey> to edit custom sequences)")
    end

    cecho("\n\n<goldeneyesCopper>  Group Pot: <goldeneyesGold>" .. Goldeneyes.format(Goldeneyes.total))
    if unknown_count > 0 then
        cecho(" <red>(+ Unknown Piles!)")
    end
    cecho("   <goldeneyesCopper>Gold/Hour: " .. gph_display .. "\n")

    if Goldeneyes.org.name then
        local mode_text = (Goldeneyes.org.mode == "personal") and "Personal Share" or "Total Pot"
        cecho(string.format("  <goldeneyesCopper>%s Share  (<goldeneyesGold>%d%%<goldeneyesSilver> of %s): <goldeneyesGold>%s\n", Goldeneyes.org.name, Goldeneyes.org.percent, mode_text, Goldeneyes.format(Goldeneyes.org.gold)))
    end

    for org_name, amt in pairs(Goldeneyes.org_debts) do
        if amt > 0 then
            cecho(string.format("  <goldeneyesCopper>Held %s Funds (Requires Deposit): <orange>%s\n", org_name, Goldeneyes.format(amt)))
        end
    end

    if Goldeneyes.count(Goldeneyes.names) > 0 then 
        cecho("\n<goldeneyesCopper>  Current Share Breakdown:<reset>\n") 
        local shares = Goldeneyes.get_shares()
        for k, v in pairs(shares) do
            cecho("  <goldeneyesSilver>" .. string.format("%14s", k:title()) .. ": <goldeneyesGold>" .. Goldeneyes.format(v) .. "\n")
        end
    else
        cecho("\n<goldeneyesSilver>  No members currently tracked. Use <goldeneyesGold>gold group<goldeneyesSilver> to add.\n")
    end

    local ledger_count = Goldeneyes.count(Goldeneyes.ledger)

    if ledger_count > 0 or unknown_count > 0 then
        cecho("\n<goldeneyesCopper>  Uncollected Group Gold (Held by Members):<reset>\n")
        local all_holders = {}
        for k,v in pairs(Goldeneyes.ledger) do all_holders[k] = true end
        for k,v in pairs(Goldeneyes.unknown_ledger) do all_holders[k] = true end

        for k, _ in pairs(all_holders) do
            local debt = Goldeneyes.ledger[k] or 0
            local unknown = Goldeneyes.unknown_ledger[k] or 0
            local str = string.format("  <goldeneyesSilver>%14s: ", k:title())

            if debt > 0 then str = str .. "<orange>" .. Goldeneyes.format(debt) .. " gold " end
            if unknown > 0 then 
                if debt > 0 then str = str .. "<goldeneyesSilver>and " end
                str = str .. "<red>" .. unknown .. " unknown pile(s)" 
            end
            cecho(str .. "\n")
        end
    end

    cecho("<goldeneyesGold>=======================================================================<reset>\n")
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

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

function Goldeneyes.set_accountant(name)
    Goldeneyes.accountant = name:title()
    cecho("Collector set to <goldeneyesGold>" .. name)
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

function Goldeneyes.togglealerts(val)
    local state = val:lower() == "on"
    Goldeneyes.config.party_alerts = state
    cecho("Party alerts are now " .. (state and "<green>ENABLED<goldeneyesSilver>" or "<red>DISABLED<goldeneyesSilver>"))
end

function Goldeneyes.toggle(toggle_cmd)
    local state = (toggle_cmd:lower() == "on" or toggle_cmd:lower() == "enabled")
    Goldeneyes.enabled = state

    if state and Goldeneyes.count(Goldeneyes.names) == 0 and gmcp.Char and gmcp.Char.Name then
        Goldeneyes.add(gmcp.Char.Name.name:lower())
    end
    Goldeneyes.echo("Tracking " .. (state and "<goldeneyesGold>enabled" or "<red>disabled"))
    
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

function Goldeneyes.reset()
    cecho("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <red>WARNING!<goldeneyesSilver> You are about to reset the tracker (Total: " .. Goldeneyes.format(Goldeneyes.total) .. " gold).\n")
    cecho("  <goldeneyesSilver>Type <goldeneyesGold>gold reset confirm<reset> to wipe gold totals but KEEP your party roster.\n")
    cecho("  <goldeneyesSilver>Type <goldeneyesGold>gold reset full<reset> to wipe gold totals AND CLEAR the party roster.\n")
end

function Goldeneyes.confirm_reset(skip_baseline, clear_roster)
    if clear_roster then
        Goldeneyes.names = {}
        Goldeneyes.paused = {}
        Goldeneyes.org = {name = false, percent = 0, gold = 0, mode = "pot", taxable_base = 0} 
        Goldeneyes.org_debts = {}
        if gmcp.Char and gmcp.Char.Name then Goldeneyes.add(gmcp.Char.Name.name:lower()) end
    else
        for k, _ in pairs(Goldeneyes.names) do Goldeneyes.names[k] = 0 end
        for k, _ in pairs(Goldeneyes.paused) do Goldeneyes.paused[k] = 0 end
        if Goldeneyes.org then 
            Goldeneyes.org.gold = 0 
            Goldeneyes.org.taxable_base = 0 
        end
    end

    Goldeneyes.ledger = {}
    Goldeneyes.unknown_ledger = {}
    Goldeneyes.total = 0
    Goldeneyes.expenses = 0
    Goldeneyes.starttime = os.time()
    Goldeneyes.pending_gold = {}
    Goldeneyes.pickup_count = 0
    Goldeneyes.first_pickup_time = nil

    if not skip_baseline then
        Goldeneyes.set_baseline()
    end
    
    Goldeneyes.save() 
    
    if clear_roster then
        Goldeneyes.echo("<red>Tracker and party roster have been fully wiped.<reset>")
    else
        Goldeneyes.echo("<red>Gold totals have been reset (Party roster preserved).<reset>")
    end
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

function Goldeneyes.distribute(channel)
    local cont = Goldeneyes.config.stash or "pack"
    local shares = Goldeneyes.get_shares()
    local members = Goldeneyes.count(Goldeneyes.names)
    local my_name = gmcp.Char.Name.name:lower()
    
    local total_withdraw = 0
    for k, v in pairs(shares) do
        total_withdraw = total_withdraw + math.floor(v)
    end
    
    if Goldeneyes.org and Goldeneyes.org.name then
        total_withdraw = total_withdraw + math.floor(Goldeneyes.org.gold)
    end
    
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
            local give_amt = math.floor(v)
            if give_amt > 0 then 
                local give_cmd = "queue add eqbal give " .. give_amt .. " gold to " .. k
                tempTimer(delay, function() send(give_cmd) end)
                delay = delay + 0.5
            end
        end
    end

    local my_cut = 0
    if shares[my_name] then my_cut = math.floor(shares[my_name]) end
    if Goldeneyes.org and Goldeneyes.org.name then
        local org_cut = math.floor(Goldeneyes.org.gold)
        my_cut = my_cut + org_cut
        Goldeneyes.org_debts[Goldeneyes.org.name] = (Goldeneyes.org_debts[Goldeneyes.org.name] or 0) + org_cut
    end

    local wallet = Goldeneyes.config.wallet or "none"
    if wallet:lower() ~= "none" and wallet:lower() ~= "inventory" and my_cut > 0 then
        tempTimer(delay, function() 
            if wallet:find("/") then
                Goldeneyes.store_custom(wallet, my_cut)
            else
                send("queue add eqbal put " .. my_cut .. " gold in " .. wallet)
            end
        end)
        delay = delay + 0.5
    end

    Goldeneyes.echo("Distributed gold from <goldeneyesGold>" .. cont)
    if wallet:lower() ~= "none" and wallet:lower() ~= "inventory" and my_cut > 0 then
        Goldeneyes.echo("Personal cut (" .. Goldeneyes.format(my_cut) .. " gold) routed to <goldeneyesGold>" .. wallet)
    end
    cecho("\n\n<goldeneyesSilver>Distribution commands queued. Auto-resetting tracker to prevent double payouts.\n")
    
    tempTimer(delay, function() Goldeneyes.confirm_reset(true, false) end)
end

-- =========================================================================
-- Event Handlers & Hooks
-- =========================================================================

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

if Goldeneyes.login_handler then killAnonymousEventHandler(Goldeneyes.login_handler) end
Goldeneyes.login_handler = registerAnonymousEventHandler("gmcp.Char.Name", "Goldeneyes_login_check")

if Goldeneyes.save_exit_handler then killAnonymousEventHandler(Goldeneyes.save_exit_handler) end
Goldeneyes.save_exit_handler = registerAnonymousEventHandler("sysExitEvent", "Goldeneyes.save")

if Goldeneyes.save_dc_handler then killAnonymousEventHandler(Goldeneyes.save_dc_handler) end
Goldeneyes.save_dc_handler = registerAnonymousEventHandler("sysDisconnectionEvent", "Goldeneyes.save")

-- =========================================================================
-- Dynamic Triggers & Aliases
-- =========================================================================

Goldeneyes.trigger_ids = Goldeneyes.trigger_ids or {}
Goldeneyes.alias_ids = Goldeneyes.alias_ids or {}

function Goldeneyes.create_triggers()
    for _, id in pairs(Goldeneyes.trigger_ids) do killTrigger(id) end
    for _, id in pairs(Goldeneyes.alias_ids) do killAlias(id) end
    Goldeneyes.trigger_ids = {}
    Goldeneyes.alias_ids = {}

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("(?:gold|sovereigns).* fl(?:ies|ying) into the hands of (\\w+)\\.", 
    [[
        local name = matches[1]
        local name_key = name:lower()
        
        if Goldeneyes.names[name_key] then
            Goldeneyes.unknown_ledger[name_key] = (Goldeneyes.unknown_ledger[name_key] or 0) + 1
            cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <red>[ALERT]<reset>: %s picked up a MYSTERY pile of gold! (Attractor artifact)", name))
            cecho(string.format("\n<goldeneyesSilver>       Please ask them how much they got and use '<goldeneyesGold>gold plus <amount><goldeneyesSilver>'.\n"))
        else
            cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <red>[ALERT]<reset>: An untracked person (%s) just auto-looted mystery gold!\n", name))
        end
    ]]))

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You pay ([\\d,]+) gold sovereigns\\.$", [[ Goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You buy .* for ([\\d,]+) gold\\.$", [[ Goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You give ([\\d,]+) gold to (\\w+)", 
    [[ 
        local amount = tonumber((matches[2]:gsub(",", "")))
        local target = matches[3]:lower()
        local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"
        
        if Goldeneyes.accountant and target == Goldeneyes.accountant:lower() then
            if Goldeneyes.ledger[my_name] then
                Goldeneyes.ledger[my_name] = Goldeneyes.ledger[my_name] - amount
                if Goldeneyes.ledger[my_name] <= 0 then Goldeneyes.ledger[my_name] = nil end
            end
            Goldeneyes.echo("Successfully handed over <goldeneyesGold>" .. Goldeneyes.format(amount) .. "<goldeneyesSilver> to accountant.")
        end
    ]]))

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^(?:Ahh, I am truly sorry, but I do not see anyone by that name here\\.|You cannot see that being here\\.|You cannot find anyone by that name here\\.)$", 
    [[
        local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name:lower()) or "unknown"
        local acc = Goldeneyes.accountant and Goldeneyes.accountant:lower() or my_name
        
        if Goldeneyes.config.autohandover and acc ~= my_name and Goldeneyes.ledger[my_name] and Goldeneyes.ledger[my_name] > 0 then
            Goldeneyes.echo("<red>Handover failed! <goldeneyesSilver>The accountant isn't here. Stashing gold safely.")
            local cont = Goldeneyes.config.stash or "pack"
            if cont:lower() ~= "none" and cont:lower() ~= "inventory" then
                send("queue add eqbal put gold in " .. cont, false)
            end
        end
    ]]))

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You (?:pick|scoop) up ([\\d,]+) gold", 
    [[
        local amount = tonumber((matches[2]:gsub(",", "")))
        if amount then Goldeneyes.handle_loot(amount) end
    ]]))

    local grab_script = [[ 
        if Goldeneyes.enabled and Goldeneyes.config.pickup then 
            if Goldeneyes.loot_timer then killTimer(Goldeneyes.loot_timer) end
            Goldeneyes.loot_timer = tempTimer(Goldeneyes.config.loot_delay or 0.8, function()
                Goldeneyes.echo("Scooping loose gold.")
                send("queue add eqbal get gold", false) 
            end)
        end 
    ]]
    local grab_regex = "(?:^A.*sovereigns? spills? from the corpse|A pile of golden sovereigns twinkles and gleams\\.|There is.*pile of golden sovereigns here\\.|pile of .*sovereigns?)"
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger(grab_regex, grab_script))

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^(\\w+) gives you ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if Goldeneyes.names[name_key] then
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

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^(\\w+) (?:picks|scoops) up ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if Goldeneyes.names[name_key] then
            Goldeneyes.plus(amount, true) 
            Goldeneyes.ledger[name_key] = (Goldeneyes.ledger[name_key] or 0) + amount
            cecho(string.format("\n<goldeneyesSilver>[<goldeneyesGold>Goldeneyes<goldeneyesSilver>]: <orange>ALERT<goldeneyesSilver>: <goldeneyesGold>%s<goldeneyesSilver> picked up <orange>%s<goldeneyesSilver> gold!", name, Goldeneyes.format(amount)))
        end
    ]]))
    
    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^You have [%d,]+ gold sovereign.*", 
    [[
        if Goldeneyes.capture_mode then
            Goldeneyes.gold_buffer = matches[1]

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

    table.insert(Goldeneyes.trigger_ids, tempRegexTrigger("^gold sovereigns? in.*", 
    [[
        if Goldeneyes.capture_mode and Goldeneyes.gold_buffer then
            Goldeneyes.gold_buffer = Goldeneyes.gold_buffer .. " " .. matches[1]
        end
    ]]))
    
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
-- In-Game Setup Dashboard
-- =========================================================================
function Goldeneyes.setup()
    local strat = Goldeneyes.config.split_strategy:title()
    local stash = Goldeneyes.config.stash and Goldeneyes.config.stash:title() or "None"
    local wallet = Goldeneyes.config.wallet and Goldeneyes.config.wallet:title() or "None"
    local acc = Goldeneyes.accountant or "Unknown"
    local loot = Goldeneyes.config.pickup and "<green>ON<goldeneyesSilver>" or "<red>OFF<goldeneyesSilver>"

    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho("\n<goldeneyesGold>                 G O L D E N E Y E S   Q U I C K   S E T U P           <reset>")
    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho("\n<goldeneyesSilver>Welcome to Goldeneyes! Let's get your ledger ready for the hunt.")
    cecho("\n<goldeneyesSilver>Click the highlighted links below to configure your core settings.\n\n")

    -- 1. Collector
    cecho("  <goldeneyesCopper>1. Collector:       <goldeneyesGold>" .. acc .. " <goldeneyesSilver>")
    cechoLink("<grey>[Click to Change]", [[clearCmdLine() appendCmdLine("gold accountant ")]], "Designate who physically holds the gold", true)

    -- 2. Strategy
    cecho("\n  <goldeneyesCopper>2. Split Strategy:  ")
    local next_strat = (strat == "Even") and "fair" or "even"
    cechoLink("<goldeneyesGold>[" .. strat .. "]", [[Goldeneyes.set_strategy("]] .. next_strat .. [["); tempTimer(0.1, function() Goldeneyes.setup() end)]], "Toggle between Even and Fair splits", true)
    
    -- 3. Stash
    cecho("\n  <goldeneyesCopper>3. Group Stash:     <goldeneyesGold>" .. stash .. " <goldeneyesSilver>")
    cechoLink("<grey>[Click to Set]", [[clearCmdLine() appendCmdLine("gold stash ")]], "Set the container where un-split gold is kept", true)

    -- 4. Wallet
    cecho("\n  <goldeneyesCopper>4. Personal Wallet: <goldeneyesGold>" .. wallet .. " <goldeneyesSilver>")
    cechoLink("<grey>[Click to Set]", [[clearCmdLine() appendCmdLine("gold wallet ")]], "Set where your personal cut goes after distribution", true)

    -- 5. Auto-Loot
    cecho("\n  <goldeneyesCopper>5. Auto-Looting:    ")
    local next_loot = Goldeneyes.config.pickup and "off" or "on"
    cechoLink("[" .. loot .. "]", [[Goldeneyes.togglepickup("]] .. next_loot .. [["); tempTimer(0.1, function() Goldeneyes.setup() end)]], "Toggle automatic gold scooping", true)

    cecho("\n\n<goldeneyesSilver>When you are ready, type <goldeneyesGold>gold party<goldeneyesSilver> to scan your group,")
    cecho("\n<goldeneyesSilver>or just type <goldeneyesGold>gold<goldeneyesSilver> to view your live ledger!")
    cecho("\n<goldeneyesGold>=======================================================================<reset>\n")
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

-- =========================================================================
-- In-Game Commands & Help Interface
-- =========================================================================
function Goldeneyes.help()
    cecho("\n<goldeneyesGold>=======================================================================<reset>")
    cecho("\n<goldeneyesGold>                    G O L D E N E Y E S   H E L P                      <reset>")
    cecho("\n<goldeneyesGold>=======================================================================<reset>\n")
    
    cecho("\n<goldeneyesSilver>New to Goldeneyes? Type <goldeneyesGold>gold setup<goldeneyesSilver> for a quick, interactive walkthrough!<reset>\n")

    cecho("\n<goldeneyesSilver>Goldeneyes is a robust Mudlet ledger for Achaean hunting parties.")
    cecho("\n<goldeneyesSilver>Commands work with either <goldeneyesGold>goldeneyes<goldeneyesSilver> or <goldeneyesGold>gold<goldeneyesSilver>.")
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
    cecho("\n  <goldeneyesGold>gold org <name> <%> [pot|personal] <reset>- Set an organization share.")
    cecho("\n  <goldeneyesGold>gold org deposit [name|all] <reset>- Clear accumulated org funds after banking.")
    cecho("\n  <goldeneyesGold>gold org off                <reset>- Disable organization share.")

    cecho("\n\n<goldeneyesCopper>Loot & Accounting Automation:<reset>")
    cecho("\n  <goldeneyesGold>gold alerts <on|off>        <reset>- Toggle clickable party join/leave prompts.")
    cecho("\n  <goldeneyesGold>gold accountant <name>      <reset>- Designate the collector (Default: You).")
    cecho("\n  <goldeneyesGold>gold autohandover <on|off>  <reset>- Automatically give loot to collector.")
    cecho("\n  <goldeneyesGold>gold autoloot <on|off>      <reset>- Toggle auto-looting.")
    cecho("\n  <goldeneyesGold>gold delay <seconds>        <reset>- Adjust auto-loot delay (Default: 0.8).")
    cecho("\n  <goldeneyesGold>gold stash <name>           <reset>- Set Group Stash (use a dedicated, empty one).")
    cecho("\n  <goldeneyesGold>gold stash                  <reset>- Move all carried gold to Group Stash.")
    cecho("\n  <goldeneyesGold>gold wallet <name>          <reset>- Set Personal Wallet for your cut (optional).")
    cecho("\n  <grey>  (Tip: Stash & Wallet support custom sequences! Use <amount> as a placeholder.)")
    cecho("\n  <grey>  (e.g., <goldeneyesGold>gold wallet get pouch from pack / put <amount> gold in pouch / put pouch in pack<grey>)")
    cecho("\n  <goldeneyesGold>gold wallet stash           <reset>- Move all carried gold to Personal Wallet.")
    cecho("\n  <grey>  (Tip: Stash & Wallet support custom sequences! Use <amount> as a placeholder.)")    
    cecho("\n  <goldeneyesGold>gold distribute [channel]   <reset>- Empty Group Stash and share gold.")

    cecho("\n\n<goldeneyesCopper>Advanced Math & Checks:<reset>")
    cecho("\n  <goldeneyesGold>gold calc <amt> <#>         <reset>- Quick math to split an amount of gold.")
    cecho("\n  <goldeneyesGold>gold check                  <reset>- Capture 'Show Gold' to find hidden rewards.")
    cecho("\n  <goldeneyesGold>gold plus <amount>          <reset>- Manually add to Total.")
    cecho("\n  <goldeneyesGold>gold minus <amount>         <reset>- Manually subtract from Total.")

    cecho("\n<goldeneyesGold>=======================================================================<reset>\n")
    if type(Goldeneyes.showprompt) == "function" then Goldeneyes.showprompt() end
end

    table.insert(Goldeneyes.alias_ids, tempAlias("^(?:Goldeneyes|gold)(?:\\s+(.*))?$", 
    [[
        local args_str = matches[2] or ""
        local args = args_str:split(" ")
        local cmd = args[1] and args[1]:lower() or ""

        if cmd == "" then Goldeneyes.display()
        elseif cmd == "help" then Goldeneyes.help()
        elseif cmd == "setup" then Goldeneyes.setup()
        elseif cmd == "on" or cmd == "off" or cmd == "enabled" or cmd == "disabled" then Goldeneyes.toggle(cmd)
        elseif cmd == "autoloot" then Goldeneyes.togglepickup(args[2] or "")
        elseif cmd == "delay" then Goldeneyes.set_delay(args[2])
        elseif cmd == "stash" then 
            local input = string.match(args_str, "^stash%s+(.+)$")
            if input then Goldeneyes.setstash(input) else Goldeneyes.stash_gold() end
        elseif cmd == "wallet" then 
            local input = string.match(args_str, "^wallet%s+(.+)$")
            if input == "stash" or input == "store" then
                Goldeneyes.wallet_stash()
            elseif input then 
                Goldeneyes.setwallet(input) 
            else 
                cecho("\n<goldeneyesSilver>Usage: <goldeneyesGold>gold wallet <name or custom string>") 
            end
        elseif cmd == "add" then if args[2] then Goldeneyes.add(args[2]) end
        elseif cmd == "party" or cmd == "group" then Goldeneyes.scan_group()
        elseif cmd == "remove" then if args[2] then Goldeneyes.remove(args[2]) end
        elseif cmd == "plus" then local amt = tonumber(args[2]); if amt then Goldeneyes.plus(amt) end
        elseif cmd == "minus" then local amt = tonumber(args[2]); if amt then Goldeneyes.minus(amt) end
        elseif cmd == "pause" then if args[2] then Goldeneyes.pause(args[2]) end
        elseif cmd == "unpause" then if args[2] then Goldeneyes.unpause(args[2]) end
        elseif cmd == "reset" then 
            if args[2] == "confirm" then Goldeneyes.confirm_reset(false, false) 
            elseif args[2] == "full" then Goldeneyes.confirm_reset(false, true)
            else Goldeneyes.reset() end
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
        elseif cmd == "org" then 
            if args[2] == "pay" or args[2] == "deposit" or args[2] == "clear" then
                Goldeneyes.pay_org(args[3])
            else
                Goldeneyes.set_org(args[2], args[3], args[4])
            end
        elseif cmd == "calc" then Goldeneyes.calc(args[2], args[3])
        else cecho("\n<goldeneyesSilver>Unknown command. Try <goldeneyesGold>Goldeneyes help<goldeneyesSilver>.") end
    ]]))
end

-- =========================================================================
-- Initialization
-- =========================================================================

Goldeneyes.create_triggers()
Goldeneyes.load()
Goldeneyes.echo("Loaded Successfully!")