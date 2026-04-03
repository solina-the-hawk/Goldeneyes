---------------------------------------------------------------------------
-- GOLDENEYES: Gold Tracking & Distribution Utility
---------------------------------------------------------------------------

goldeneyes = goldeneyes or {}
goldeneyes.settings = {}

-- =========================================================== --
--                 Gold Tracking Settings                      --
-- =========================================================== --
goldeneyes.settings.commandseparator = ";"
goldeneyes.settings.getalias = false
goldeneyes.settings.container = "box"
goldeneyes.settings.promptfunction = false

if goldeneyes.getsettings then goldeneyes.getsettings() end

-- =========================================================== --
--              Gold Tracking Functions & Logic                --
-- =========================================================== --

-- 1. Initialize Colors
color_table.msGold = {255,215,0}
color_table.msSilver = {160,160,160}

-- 2. Initialize Defaults
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

local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
goldeneyes.accountant = goldeneyes.accountant or my_name

-- =========================================================== --
--                     HELPER FUNCTIONS                        --
-- =========================================================== --
function goldeneyes.count(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end

goldeneyes.echo = function (x)
  cecho ("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: " .. x .. "<reset>")
end

goldeneyes.getsettings = function ()
  if goldeneyes.settings then
      goldeneyes.cs = goldeneyes.settings.commandseparator or ";"
      goldeneyes.getalias = goldeneyes.settings.getalias
      goldeneyes.container = goldeneyes.settings.container or "pack"
      goldeneyes.showprompt = goldeneyes.settings.promptfunction or function() end
  end
end

goldeneyes.format = function(amount)
    if not amount then return "0" end
    -- Force it into a whole number string
    local formatted = tostring(math.floor(tonumber(amount) or 0))
    local k
    while true do
        -- Insert a comma every 3 digits from the right
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k == 0) then break end
    end
    return formatted
end

goldeneyes.get_save_path = function()
    -- Mudlet natively handles "/" for paths on both Windows and Mac/Linux
    return getMudletHomeDir() .. "/Goldeneyes-Data.lua"
end

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
        starttime = goldeneyes.starttime
    }
    table.save(save_path, data)
end

goldeneyes.load = function()
    local save_path = goldeneyes.get_save_path()
    if io.exists(save_path) then
        local data = {}
        table.load(save_path, data)
        
        -- Restore all variables, falling back to current values if missing
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
    end
end

goldeneyes.getsettings()

-- =========================================================== --
--                     CORE FUNCTIONS                          --
-- =========================================================== --
goldeneyes.display = function ()
  local status = goldeneyes.enabled and "<msGold>enabled" or "<msSilver>disabled"
  local current_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
  local accountant = goldeneyes.accountant or current_name
  local role = (accountant:lower() == current_name:lower()) and "<green>(Me)" or "<yellow>(" .. accountant .. ")"
  local strat_text = (goldeneyes.split_strategy == "even") and "<green>Even" or "<yellow>Fair"

  local elapsed = os.time() - goldeneyes.starttime
  if elapsed < 1 then elapsed = 1 end
  local gph = math.floor((goldeneyes.total / elapsed) * 3600)

  cecho ("\n<msGold>Goldeneyes Gold Tracking Ledger\n")
  cecho ("<msSilver>  Enter <msGold>goldeneyes help <green>for commands and settings.\n")
  cecho ("\n")
  cecho ("  <msGold>Gold Tracking: " .. status .. "\n")
  cecho ("  <msSilver>Accountant: " .. role .. "\n")
  cecho ("  <msSilver>Strategy: " .. strat_text .. "\n\n")
  
  cecho ("  <msSilver>Gold Collected: <msGold>" .. goldeneyes.format(goldeneyes.total) .. "\n")
  cecho ("  <msSilver>Gold per hour:  <msGold>" .. goldeneyes.format(gph) .. "\n")

  if goldeneyes.org.name then
    cecho ("\n  <msSilver>" .. string.format ("%14s", goldeneyes.org.name:title ()) ..
           ": <msGold>" .. string.format ("%-8s", goldeneyes.format(goldeneyes.org.gold)) ..
           " <msSilver>(" .. goldeneyes.org.percent ..  "%)\n")
  end

  if goldeneyes.count(goldeneyes.names) > 0 then 
      cecho ("\n  <orange>Currently Tracking:\n") 
  end
  
  -- Use our new dynamic shares calculator for the display
  local shares = goldeneyes.get_shares()
  for k, v in pairs (shares) do
    cecho ("  <msSilver>" .. string.format ("%14s", k:title ()) .. ": <msGold>" .. goldeneyes.format(v) .. "\n")
  end

  local ledger_count = goldeneyes.count(goldeneyes.ledger)
  local unknown_count = goldeneyes.count(goldeneyes.unknown_ledger)

  if ledger_count > 0 or unknown_count > 0 then
      cecho ("\n<orange>Gold Held by Others:\n")
      local all_holders = {}
      for k,v in pairs(goldeneyes.ledger) do all_holders[k] = true end
      for k,v in pairs(goldeneyes.unknown_ledger) do all_holders[k] = true end

      for k, _ in pairs(all_holders) do
          local debt = goldeneyes.ledger[k] or 0
          local unknown = goldeneyes.unknown_ledger[k] or 0
          local str = string.format("  <msSilver>%14s: ", k:title())

          if debt > 0 then str = str .. "<orange>" .. goldeneyes.format(debt) .. " gold " end
          if unknown > 0 then str = str .. "<red>(+" .. unknown .. " unknown piles!)" end
          cecho(str .. "\n")
      end
  end
  cecho ("<reset>\n")
  goldeneyes.showprompt ()
end

goldeneyes.set_accountant = function(name)
    goldeneyes.accountant = name:title()
    goldeneyes.echo("Collector set to <msGold>" .. name)
    goldeneyes.showprompt()
end

goldeneyes.toggle_handover = function(val)
    if val == "on" then
        goldeneyes.autohandover = true
        goldeneyes.echo("Auto-Handover <green>ENABLED<msSilver>. I will give gold to " .. goldeneyes.accountant)
    else
        goldeneyes.autohandover = false
        goldeneyes.echo("Auto-Handover <red>DISABLED<msSilver>.")
    end
end

goldeneyes.get_shares = function()
    local shares = {}
    local count = goldeneyes.count(goldeneyes.names)
    if count == 0 then return shares end
    
    if goldeneyes.split_strategy == "even" then
        -- Error-proof even split: uses the absolute net pool
        local net_pool = goldeneyes.total - goldeneyes.org.gold
        local even_share = net_pool / count
        for k, _ in pairs(goldeneyes.names) do
            shares[k] = even_share
        end
    else 
        -- Fair split: relies on the exact moment-to-moment ledger tracking
        for k, v in pairs(goldeneyes.names) do
            shares[k] = v
        end
    end
    
    return shares
end

goldeneyes.set_strategy = function(strat)
    strat = strat and strat:lower() or "even"
    if strat == "even" or strat == "fair" then
        goldeneyes.split_strategy = strat
        goldeneyes.echo("Split strategy set to: <msGold>" .. strat:title())
        goldeneyes.showprompt()
    else
        cecho("\n<msSilver>Usage: <msGold>goldeneyes strategy <even|fair>")
    end
end

goldeneyes.toggle = function (enabled)
  local state = enabled:lower() == "on"
  goldeneyes.enabled = state

  if state and goldeneyes.count(goldeneyes.names) == 0 and gmcp.Char and gmcp.Char.Name then
      goldeneyes.add(gmcp.Char.Name.name:lower())
  end
  goldeneyes.echo ("tracking " .. (state and "<msGold>enabled" or "<msSilver>disabled"))
  goldeneyes.showprompt ()
end

goldeneyes.plus = function (amt, noecho)
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
  if not noecho then x.echo ("<msGold>" .. goldeneyes.format(original_amt) .. " <msSilver>gold added") end
  x.showprompt ()
end

goldeneyes.minus = function (amt)
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
  x.echo ("<msGold>" .. goldeneyes.format(amt) .. " <msSilver>gold removed.")
  x.showprompt ()
end

goldeneyes.handle_loot = function (amt)
  if not goldeneyes.enabled then return end
  local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
  local acc = goldeneyes.accountant or my_name

  if acc == my_name then
      goldeneyes.plus(amt, true)
  else
      if goldeneyes.autohandover then
          send("give " .. amt .. " gold to " .. acc)
          goldeneyes.echo("Looted <msGold>"..goldeneyes.format(amt).."<msSilver>. Handing over to <msGold>"..acc)
      else
          send("pt I picked up " .. goldeneyes.format(amt) .. " gold.")
          goldeneyes.echo("Looted <msGold>"..goldeneyes.format(amt).."<msSilver>. Reported to party.")
      end
  end
end

goldeneyes.add = function (name)
  name = name:lower()
  if goldeneyes.names[name] == nil then
    goldeneyes.echo ("Added <msGold>" .. name:title () .. " <msSilver>to tracking.")
    goldeneyes.names[name] = 0
  else
    goldeneyes.echo ("<msGold>" .. name:title () .. " <msSilver>is already being tracked.")
  end
  goldeneyes.showprompt ()
end

goldeneyes.add_party = function()
    goldeneyes.echo("Scanning party members...")
    send("party members", false)

    if goldeneyes.party_trigger then killTrigger(goldeneyes.party_trigger) end
    goldeneyes.party_trigger = tempRegexTrigger("^\\s+([A-Z][a-z]+)", function()
        local name = matches[2]
        if name ~= "Party" and name ~= "The" then goldeneyes.add(name) end
    end)

    tempTimer(1.5, function()
        if goldeneyes.party_trigger then
            killTrigger(goldeneyes.party_trigger)
            goldeneyes.party_trigger = nil
            goldeneyes.echo("Party scan complete.")
            goldeneyes.showprompt()
        end
    end)
end

goldeneyes.remove = function (name)
  name = name:lower()
  if goldeneyes.names[name] ~= nil then
    goldeneyes.echo ("removed <msGold>" .. name:title () .. " <msSilver>from tracking")
    goldeneyes.echo ("<msGold>" .. name:title () .. " <msSilver>was at <msGold>" .. goldeneyes.format(goldeneyes.names[name]) .. " <msSilver>gold.")
    goldeneyes.names[name] = nil
  else
    goldeneyes.echo ("<msGold>" .. name .. " <msSilver>is not currently being tracked.")
  end
  goldeneyes.showprompt ()
end

goldeneyes.pause = function (name)
  name = name:lower()
  if goldeneyes.names[name] ~= nil then
    goldeneyes.echo ("Gold tracking for <msGold>" .. name:title () .. " <msSilver>paused.")
    goldeneyes.paused[name] = goldeneyes.names[name]
    goldeneyes.names[name] = nil
  end
  goldeneyes.showprompt ()
end

goldeneyes.unpause = function (name)
  name = name:lower()
  if goldeneyes.paused[name] then
    goldeneyes.echo ("Gold tracking for <msGold>" .. name:title () .. " <msSilver>unpaused.")
    goldeneyes.names[name] = goldeneyes.paused[name]
    goldeneyes.paused[name] = nil
  end
  goldeneyes.showprompt ()
end

goldeneyes.reset = function ()
  if goldeneyes.reset_pending then
      goldeneyes.confirm_reset()
      goldeneyes.save()
      if goldeneyes.reset_timer then killTimer(goldeneyes.reset_timer) end
      goldeneyes.reset_pending = false
  else
      goldeneyes.reset_pending = true
      cecho("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: <red>WARNING!<msSilver> This will wipe ALL data (Total: " .. goldeneyes.format(goldeneyes.total) .. ").\n")
      cecho("<msSilver>Type <msGold>goldeneyes reset<msSilver> again within 6 seconds to confirm.\n")
      goldeneyes.reset_timer = tempTimer(6, function()
          goldeneyes.reset_pending = false
          cecho("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: Reset cancelled.\n")
      end)
  end
end

goldeneyes.confirm_reset = function()
  goldeneyes.names = {}
  goldeneyes.paused = {}
  goldeneyes.ledger = {}
  goldeneyes.unknown_ledger = {}
  goldeneyes.org = {name = false, percent = 0, gold = 0}
  goldeneyes.total = 0
  goldeneyes.expenses = 0
  goldeneyes.starttime = os.time()

  if gmcp.Char and gmcp.Char.Name then goldeneyes.add(gmcp.Char.Name.name) end
  goldeneyes.set_baseline()
  goldeneyes.echo ("<red>Tracker has been reset.<reset>")
  goldeneyes.showprompt ()
end

goldeneyes.distribute = function (channel)
  local cont = goldeneyes.container or "pack"
  send ("get gold from " .. cont)
  
  local shares = goldeneyes.get_shares()
  local members = goldeneyes.count(goldeneyes.names)
  
  channel = channel and channel:lower() or "party"
  local cmd = "pt"
  local message = ""
  
  -- Dynamic announcement based on strategy
  if goldeneyes.split_strategy == "even" then
      local single_share = 0
      for _, v in pairs(shares) do single_share = math.floor(v); break end
      
      if channel == "intrepid" then
          cmd = "it"
          message = string.format("[Goldeneyes]: Distributing %s gold across %d members. Expected even share: %s gold.", goldeneyes.format(goldeneyes.total), members, goldeneyes.format(single_share))
      elseif channel == "say" then
          cmd = "say"
          message = string.format("I'll distribute our collected %s gold sovereigns now. Split evenly among the %d of us, we should each receive %s gold.", goldeneyes.format(goldeneyes.total), members, goldeneyes.format(single_share))
      else
          cmd = "pt"
          message = string.format("[Goldeneyes]: Distributing %s gold across %d members. Expected even share: %s gold.", goldeneyes.format(goldeneyes.total), members, goldeneyes.format(single_share))
      end
  else
      -- "Fair" Strategy Announcement (No expected share is promised since it varies)
      if channel == "intrepid" then
          cmd = "it"
          message = string.format("[Goldeneyes]: Distributing %s gold across %d members. Shares are prorated based on hunt participation.", goldeneyes.format(goldeneyes.total), members)
      elseif channel == "say" then
          cmd = "say"
          message = string.format("I am now distributing our collected %s gold sovereigns across the %d of us, distributed fairly based on when you joined the hunt.", goldeneyes.format(goldeneyes.total), members)
      else
          cmd = "pt"
          message = string.format("[Goldeneyes]: Distributing %s gold across %d members. Shares are prorated based on hunt participation.", goldeneyes.format(goldeneyes.total), members)
      end
  end
  
  send(cmd .. " " .. message)

  local delay = 0.5
  for k, v in pairs (shares) do
    if k ~= gmcp.Char.Name.name:lower () then
      v = math.floor (v)
      if v > 0 then 
          tempTimer(delay, function() send ("give " .. v .. " gold to " .. k) end)
          delay = delay + 0.5
      end
    end
  end

  goldeneyes.echo("Distributed gold from <msGold>" .. cont)
  cecho("\n\n<msSilver>Distribution complete. Verify everyone received their share, then type <msGold>goldeneyes reset<msSilver>.\n")
end

goldeneyes.help = function ()
    cecho ("\n<msGold>Goldeneyes Gold Tracking Ledger Help Information\n")
    cecho ("<msSilver>Commands work with <msGold>goldeneyes<msSilver> or <msGold>gold<msSilver>\n")
    cecho ("<msSilver>----------------------------------------------------------------------\n")
    cecho ("<msGold>BASIC CONTROLS\n")
    cecho ("    <msGold>goldeneyes <on|off>          <msSilver>- Turn tracker on/off.\n")
    cecho ("    <msGold>goldeneyes reset             <msSilver>- Reset all totals (enter twice to confirm).\n")
    cecho ("    <msGold>goldeneyes report [channel]  <msSilver>- Announce totals (Channels: party, intrepid, say).\n")
    cecho ("\n<msGold>GROUP & ACCOUNTING\n")
    cecho ("    <msGold>goldeneyes strategy <even|fair><msSilver>- Set split method (Default: even).\n")
    cecho ("    <msGold>goldeneyes accountant <name> <msSilver>- Designate the collector (Default: You).\n")
    cecho ("    <msGold>goldeneyes autohandover <on|off> <msSilver>- Automatically give loot to Accountant.\n")
    cecho ("    <msGold>goldeneyes party             <msSilver>- Auto-add your current party members.\n")
    cecho ("    <msGold>goldeneyes alerts <on|off>   <msSilver>- Toggle clickable party join/leave prompts.\n")
    cecho ("    <msGold>goldeneyes add <name>        <msSilver>- Add a person to the split list.\n")
    cecho ("    <msGold>goldeneyes remove <name>     <msSilver>- Remove a person from the list.\n")
    cecho ("\n<msGold>LOOT & AUTOMATION\n")
    cecho ("    <msGold>goldeneyes autoloot <on|off> <msSilver>- Toggle auto-looting.\n")
    cecho ("    <msGold>goldeneyes container <name>  <msSilver>- Set loot bag (e.g., 'pack').\n")
    cecho ("    <msGold>goldeneyes stash             <msSilver>- Move all carried gold to container.\n")
    cecho ("    <msGold>goldeneyes distribute [channel]<msSilver>- Empty container and share gold.\n")
    cecho ("\n<msGold>ADVANCED\n")
    cecho ("    <msGold>goldeneyes calc <amt> <#>  <msSilver>- Quick math to split an amount of gold.\n")
    cecho ("    <msGold>goldeneyes snapshot / check  <msSilver>- Capture 'Show Gold' to find hidden rewards.\n")
    cecho ("    <msGold>goldeneyes loot <amount>     <msSilver>- Manually simulate picking up loot.\n")
    cecho ("    <msGold>goldeneyes plus <amount>     <msSilver>- Manually add to Total.\n")
    cecho ("    <msGold>goldeneyes minus <amount>    <msSilver>- Manually subtract from Total.\n\n")
    goldeneyes.showprompt ()
end

-- =========================================================== --
--                  MISSING ALIAS FUNCTIONS                    --
-- =========================================================== --
goldeneyes.togglepickup = function(val)
    local state = val:lower() == "on"
    goldeneyes.pickup = state
    goldeneyes.echo("Auto-pickup is now " .. (state and "<green>ENABLED<msSilver>" or "<red>DISABLED<msSilver>"))
end

goldeneyes.setcontainer = function(name)
    goldeneyes.container = name
    goldeneyes.echo("Loot container set to: <msGold>" .. name)
end

goldeneyes.stash = function()
    local cont = goldeneyes.container or "pack"
    send("put gold in " .. cont)
    goldeneyes.echo("Attempting to stash gold in your <msGold>" .. cont)
end

goldeneyes.add_expense = function(amt)
    if goldeneyes.enabled then
        goldeneyes.expenses = goldeneyes.expenses + amt
        goldeneyes.echo("Tracked expense of <orange>" .. goldeneyes.format(amt) .. "<msSilver> gold.")
    end
end

goldeneyes.togglealerts = function(val)
    local state = val:lower() == "on"
    goldeneyes.party_alerts = state
    goldeneyes.echo("Party alerts are now " .. (state and "<green>ENABLED<msSilver>" or "<red>DISABLED<msSilver>"))
end

goldeneyes.calc = function(amount, people)
    -- Strip commas just in case you typed 'goldeneyes calc 32,512 4'
    if type(amount) == "string" then amount = amount:gsub(",", "") end
    
    amount = tonumber(amount)
    people = tonumber(people)

    if not amount or not people or people <= 0 then
        cecho("\n<msSilver>Usage: <msGold>goldeneyes calc <amount> <number of people>\n")
        return
    end

    local share = math.floor(amount / people)
    local remainder = amount % people

    local msg = string.format("Splitting <msGold>%s<msSilver> gold among <msGold>%d<msSilver> people results in <msGold>%s<msSilver> gold each.", 
        goldeneyes.format(amount), people, goldeneyes.format(share))

    -- Let us know if there's leftover gold that couldn't be divided evenly
    if remainder > 0 then
        msg = msg .. string.format(" <msSilver>(Remainder: <orange>%s<msSilver>)", goldeneyes.format(remainder))
    end

    goldeneyes.echo(msg)
end

goldeneyes.start_snapshot = function()
    goldeneyes.set_baseline()
end

goldeneyes.announce = function(channel)
    -- Default to party if no channel is specified
    channel = channel and channel:lower() or "party"
    
    local cmd = "pt"
    local message = ""
    
    if channel == "intrepid" then
        cmd = "it"
        message = "We have collected a total of " .. goldeneyes.format(goldeneyes.total) .. " gold so far."
    elseif channel == "say" then
        cmd = "say"
        -- RP-friendly, non-spammy verbiage
        message = "By my calculations, we have collected a total of " .. goldeneyes.format(goldeneyes.total) .. " gold sovereigns thus far."
    else
        -- Catch-all defaults to party
        cmd = "pt"
        message = "We have collected a total of " .. goldeneyes.format(goldeneyes.total) .. " gold so far."
    end
    
    send(cmd .. " " .. message)
end

-- =========================================================== --
--                  REWARD/SNAPSHOT LOGIC                      --
-- =========================================================== --
goldeneyes.set_baseline = function()
    goldeneyes.baseline.set = false
    goldeneyes.capture_mode = "baseline"
    send("show gold")
end

goldeneyes.check_reward = function()
    if not goldeneyes.baseline.set then
        goldeneyes.echo("<yellow>Warning:<msSilver> No baseline established yet. Establishing now. Type <msGold>goldeneyes check<msSilver> after your next reward.")
        goldeneyes.set_baseline()
        return
    end
    goldeneyes.capture_mode = "check"
    send("show gold")
end

goldeneyes.process_gold_capture = function(hand, bank)
    if type(hand) == "string" then hand = tonumber((string.gsub(hand, ",", ""))) end
    if type(bank) == "string" then bank = tonumber((string.gsub(bank, ",", ""))) end
    hand = hand or 0
    bank = bank or 0
    
    if goldeneyes.capture_mode == "baseline" then
        goldeneyes.baseline.hand = hand
        goldeneyes.baseline.bank = bank
        goldeneyes.baseline.set = true
        goldeneyes.echo("Baseline set. Hand: " .. goldeneyes.format(hand) .. ", Bank: " .. goldeneyes.format(bank))
        
    elseif goldeneyes.capture_mode == "check" then
        local wealth_change = (hand + bank) - (goldeneyes.baseline.hand + goldeneyes.baseline.bank)
        local hidden_profit = wealth_change + goldeneyes.expenses - goldeneyes.total
        
        if hidden_profit > 0 then
            goldeneyes.echo("<orange>Hidden Reward Detected!<msSilver> You gained <msGold>" .. goldeneyes.format(hidden_profit) .. "<msSilver> gold.")
            goldeneyes.plus(hidden_profit)
        elseif hidden_profit < 0 then
             goldeneyes.echo("Math check negative (" .. goldeneyes.format(hidden_profit) .. "). Did you spend gold we missed?")
        else
             goldeneyes.echo("No hidden rewards found (Math is balanced).")
        end
        goldeneyes.baseline.hand = hand
        goldeneyes.baseline.bank = bank
        goldeneyes.expenses = 0 
    end
    goldeneyes.capture_mode = nil
end

-- =========================================================== --
--                     EVENT HANDLERS                          --
-- =========================================================== --
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
      goldeneyes.echo("Auto-pickup is <msGold>ENABLED<msSilver>.")
  end
end

if goldeneyes.login_handler then killAnonymousEventHandler(goldeneyes.login_handler) end
goldeneyes.login_handler = registerAnonymousEventHandler("gmcp.Char.Name", "goldeneyes_login_check")

-- Save data when Mudlet closes or disconnects from Achaea
if goldeneyes.save_exit_handler then killAnonymousEventHandler(goldeneyes.save_exit_handler) end
goldeneyes.save_exit_handler = registerAnonymousEventHandler("sysExitEvent", "goldeneyes.save")

if goldeneyes.save_dc_handler then killAnonymousEventHandler(goldeneyes.save_dc_handler) end
goldeneyes.save_dc_handler = registerAnonymousEventHandler("sysDisconnectionEvent", "goldeneyes.save")

-- =========================================================== --
--               DYNAMIC TRIGGERS & ALIASES                    --
-- =========================================================== --
goldeneyes.trigger_ids = goldeneyes.trigger_ids or {}
goldeneyes.alias_ids = goldeneyes.alias_ids or {}

goldeneyes.create_triggers = function()
    -- 1. Clean up existing triggers/aliases to prevent duplicates on reload
    for _, id in pairs(goldeneyes.trigger_ids) do killTrigger(id) end
    for _, id in pairs(goldeneyes.alias_ids) do killAlias(id) end
    goldeneyes.trigger_ids = {}
    goldeneyes.alias_ids = {}

    -- 2. Mystery Gold Pickups
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^Some gold falls from the corpse and automatically flies into the hands of (\\w+)\\.", 
    [[
        local name_key = matches[2]:lower()
        if goldeneyes.names[name_key] then
            goldeneyes.unknown_ledger[name_key] = (goldeneyes.unknown_ledger[name_key] or 0) + 1
            cecho(string.format("\n<red>[ALERT]: %s picked up a MYSTERY pile of gold! (Auto-loot artifact detected)", matches[2]))
            cecho("\n<red>       Please ask them how much they got and use 'goldeneyes plus <amount>'.")
        end
    ]]))

    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^.*sovereigns spills from the corpse, flying into the hands of.*before they ", 
    [[
        cecho("\n<red>[ALERT]: Someone's artifact just auto-looted a MYSTERY pile of gold!<reset>")
    ]]))

    -- 3. Shop Purchases & Bribes (Expenses)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You pay ([\\d,]+) gold sovereigns\\.$", [[ goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You buy .* for ([\\d,]+) gold\\.$", [[ goldeneyes.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You give ([\\d,]+) gold to .*$", [[ -- Expense ignored unless explicitly tracked ]]))

    -- 4. Gold Picked Up (You)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You (?:pick|scoop) up ([\\d,]+) gold", 
    [[
        local amount = tonumber((matches[2]:gsub(",", "")))
        if amount then goldeneyes.handle_loot(amount) end
    ]]))

    -- 5. Gold Dropped (Grab It)
    local grab_script = [[ if goldeneyes.enabled and goldeneyes.pickup then send("queue add eqbal get gold", false) end ]]
    local grab_regex = "(?:^A.*sovereigns? spills? from the corpse|A pile of golden sovereigns twinkles and gleams\\.|There is.*pile of golden sovereigns here\\.|pile of .*sovereigns?)"
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger(grab_regex, grab_script))

    -- 6. Gold Received (Handover)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^(\\w+) gives you ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if goldeneyes.names[name_key] then
            goldeneyes.plus(amount)
            if goldeneyes.ledger[name_key] then
                goldeneyes.ledger[name_key] = goldeneyes.ledger[name_key] - amount
                cecho(string.format("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: %s paid off %s (Remaining: %s).", name, goldeneyes.format(amount), goldeneyes.format(goldeneyes.ledger[name_key])))
                if goldeneyes.ledger[name_key] <= 0 then
                    goldeneyes.ledger[name_key] = nil
                    cecho(string.format("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: %s has settled their debt.", name))
                end
            else
                cecho(string.format("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: Accepted %s gold from %s (No prior debt).", goldeneyes.format(amount), name))
            end
        end
    ]]))

    -- 7. Gold Tracking - Watchdog (Others)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^(\\w+) (?:picks|scoops) up ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if goldeneyes.names[name_key] then
            goldeneyes.ledger[name_key] = (goldeneyes.ledger[name_key] or 0) + amount
            cecho(string.format("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: <orange>ALERT<msSilver>: <msGold>%s<msSilver> picked up <orange>%s<msSilver> gold!", name, goldeneyes.format(amount)))
        end
    ]]))

    -- 8. Capture Gold (All Sources)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You have .* gold sovereigns? in your .*", 
    [[
        if goldeneyes.capture_mode then
            local line = matches[1]
            local total_hand = 0
            local total_bank = 0

            for amount_str, location in string.gmatch(line, "([%d,]+) gold sovereigns? in your (%w+)") do
                local clean_str = (string.gsub(amount_str, ",", ""))
                local amount = tonumber(clean_str)

                if location == "inventory" or location == "containers" then
                    total_hand = total_hand + amount
                elseif location == "bank" then
                    total_bank = total_bank + amount
                end
            end
            goldeneyes.process_gold_capture(total_hand, total_bank)
        end
    ]]))
    
    -- 8.5 Interactive Party Prompts
    -- When YOU join a party
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You have joined .+'s party\\.$", 
    [[
        if goldeneyes.party_alerts then
            cecho("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: You joined a party. ")
            cechoLink("<green>[Add Party Members]", "goldeneyes.add_party()", "Auto-add current party to ledger", true)
            cecho(" <msSilver>| ")
            -- Appends to command line so you can easily type the name before hitting enter
            cechoLink("<yellow>[Set Accountant]", 'clearCmdLine() appendCmdLine("goldeneyes accountant ")', "Designate the collector", true)
            cecho("\n")
        end
    ]]))

    -- When YOU leave a party
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^You have left your party\\.$", 
    [[
        if goldeneyes.party_alerts then
            cecho("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: You left the party. ")
            cechoLink("<red>[Reset Tracker]", "goldeneyes.reset()", "Wipe all current ledger data", true)
            cecho("\n")
        end
    ]]))

    -- When SOMEONE ELSE joins your party
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^\\(Party\\): (\\w+) has joined your party\\.$", 
    [[
        if goldeneyes.party_alerts then
            local name = matches[2]
            cecho("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: <msGold>" .. name .. " <msSilver>joined the party. ")
            cechoLink("<green>[Add to Tracker]", 'goldeneyes.add("' .. name .. '")', "Add " .. name .. " to the gold split", true)
            cecho("\n")
        end
    ]]))

    -- When SOMEONE ELSE leaves your party
    -- (Assuming standard Achaea syntax based on the join message)
    table.insert(goldeneyes.trigger_ids, tempRegexTrigger("^\\(Party\\): (\\w+) has left your party\\.$", 
    [[
        local name = matches[2]
        -- We only prompt if they are actually in our ledger!
        if goldeneyes.party_alerts and goldeneyes.names[name:lower()] then
            cecho("\n<msSilver>[<msGold>Goldeneyes<msSilver>]: <msGold>" .. name .. " <msSilver>left the party. ")
            cechoLink("<orange>[Remove from Tracker]", 'goldeneyes.remove("' .. name .. '")', "Remove " .. name .. " from the gold split", true)
            cecho("\n")
        end
    ]]))
    
    -- 9. The Main Controller Alias
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
            if args[2] then goldeneyes.setcontainer(args[2]) else cecho("\n<msSilver>Usage: <msGold>goldeneyes container <name>") end
        elseif cmd == "stash" then goldeneyes.stash()
        elseif cmd == "add" then if args[2] then goldeneyes.add(args[2]) end
        elseif cmd == "party" then goldeneyes.add_party()
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
            if args[2] then goldeneyes.set_accountant(args[2]) else cecho("\n<msSilver>Current Accountant: <msGold>" .. goldeneyes.accountant) end
        elseif cmd == "loot" then 
            local amt = tonumber(args[2]); if amt then goldeneyes.handle_loot(amt) else cecho("\n<msSilver>Usage: <msGold>goldeneyes loot <amount>") end
        elseif cmd == "autohandover" then goldeneyes.toggle_handover(args[2] or "")
        elseif cmd == "strategy" then goldeneyes.set_strategy(args[2])
        elseif cmd == "alerts" then goldeneyes.togglealerts(args[2] or "")
        elseif cmd == "calc" then goldeneyes.calc(args[2], args[3])
        else cecho("\n<msSilver>Unknown command. Try <msGold>goldeneyes help<msSilver>.") end
    ]]))

    goldeneyes.echo("Dynamic triggers and aliases loaded.")
end

-- Initialize triggers on load
goldeneyes.create_triggers()

-- Load saved data
goldeneyes.load()

-- Inform user it successfully loaded
cecho("\n<green>Goldeneyes Core Loaded Successfully!<reset>\n")