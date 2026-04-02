---------------------------------------------------------------------------
-- GOLDENEYES: Gold Tracking & Distribution Utility
---------------------------------------------------------------------------

goldtracking = goldtracking or {}
goldtracking.settings = {}

-- =========================================================== --
--                 Gold Tracking Settings                      --
-- =========================================================== --
goldtracking.settings.commandseparator = ";"
goldtracking.settings.getalias = false
goldtracking.settings.container = "box"
goldtracking.settings.promptfunction = false

if goldtracking.getsettings then goldtracking.getsettings() end

-- =========================================================== --
--              Gold Tracking Functions & Logic                --
-- =========================================================== --

-- 1. Initialize Colors
color_table.msGold = {255,215,0}
color_table.msSilver = {160,160,160}

-- 2. Initialize Defaults
if goldtracking.enabled == nil then goldtracking.enabled = true end
goldtracking.pickup = goldtracking.pickup or true
goldtracking.names = goldtracking.names or {}
goldtracking.paused = goldtracking.paused or {}
goldtracking.total = goldtracking.total or 0
goldtracking.org = goldtracking.org or {name = false, percent = 0, gold = 0}
goldtracking.starttime = goldtracking.starttime or os.time()
goldtracking.ledger = goldtracking.ledger or {}
goldtracking.unknown_ledger = goldtracking.unknown_ledger or {}
goldtracking.snapshot = goldtracking.snapshot or {hand = 0, bank = 0, phase = nil}
goldtracking.baseline = goldtracking.baseline or {hand = 0, bank = 0, set = false}
goldtracking.expenses = goldtracking.expenses or 0
goldtracking.autohandover = goldtracking.autohandover or false
goldtracking.reset_pending = false

local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
goldtracking.accountant = goldtracking.accountant or my_name

-- =========================================================== --
--                     HELPER FUNCTIONS                        --
-- =========================================================== --
function goldtracking.count(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end

goldtracking.echo = function (x)
  cecho ("\n<msSilver>[<msGold>GoldTracking<msSilver>]: " .. x .. "<reset>")
end

goldtracking.getsettings = function ()
  if goldtracking.settings then
      goldtracking.cs = goldtracking.settings.commandseparator or ";"
      goldtracking.getalias = goldtracking.settings.getalias
      goldtracking.container = goldtracking.settings.container or "pack"
      goldtracking.showprompt = goldtracking.settings.promptfunction or function() end
  end
end
goldtracking.getsettings()

-- =========================================================== --
--                     CORE FUNCTIONS                          --
-- =========================================================== --
goldtracking.display = function ()
  local status = goldtracking.enabled and "<msGold>enabled" or "<msSilver>disabled"
  local current_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
  local accountant = goldtracking.accountant or current_name
  local role = (accountant:lower() == current_name:lower()) and "<green>(Me)" or "<yellow>(" .. accountant .. ")"

  local elapsed = os.time() - goldtracking.starttime
  if elapsed < 1 then elapsed = 1 end
  local gph = math.floor((goldtracking.total / elapsed) * 3600)

  cecho ("\n     <msGold>Gold Tracking " .. status .. " <msSilver>Accountant: " .. role .. "\n\n")
  cecho ("      <msSilver>Total Pot:  <msGold>" .. goldtracking.total .. "\n")
  cecho ("      <msSilver>Gold/Hour:  <msGold>" .. gph .. "\n")

  if goldtracking.org.name then
    cecho ("\n  <msSilver>" .. string.format ("%14s", goldtracking.org.name:title ()) ..
           ": <msGold>" .. string.format ("%-8s", math.floor(goldtracking.org.gold)) ..
           " <msSilver>(" .. goldtracking.org.percent ..  "%)\n")
  end

  if goldtracking.count(goldtracking.names) > 0 then cecho ("\n") end
  for k, v in pairs (goldtracking.names) do
    cecho ("  <msSilver>" .. string.format ("%14s", k:title ()) .. ": <msGold>" .. math.floor(v) .. "\n")
  end

  local ledger_count = goldtracking.count(goldtracking.ledger)
  local unknown_count = goldtracking.count(goldtracking.unknown_ledger)

  if ledger_count > 0 or unknown_count > 0 then
      cecho ("\n<orange>     -- Gold Held by Others --\n")
      local all_holders = {}
      for k,v in pairs(goldtracking.ledger) do all_holders[k] = true end
      for k,v in pairs(goldtracking.unknown_ledger) do all_holders[k] = true end

      for k, _ in pairs(all_holders) do
          local debt = goldtracking.ledger[k] or 0
          local unknown = goldtracking.unknown_ledger[k] or 0
          local str = string.format("  <msSilver>%14s: ", k:title())

          if debt > 0 then str = str .. "<orange>" .. math.floor(debt) .. " gold " end
          if unknown > 0 then str = str .. "<red>(+" .. unknown .. " unknown piles!)" end
          cecho(str .. "\n")
      end
  end
  cecho ("<reset>\n")
  goldtracking.showprompt ()
end

goldtracking.set_accountant = function(name)
    goldtracking.accountant = name:title()
    goldtracking.echo("Accountant set to <msGold>" .. name)
    goldtracking.showprompt()
end

goldtracking.toggle_handover = function(val)
    if val == "on" then
        goldtracking.autohandover = true
        goldtracking.echo("Auto-Handover <green>ENABLED<msSilver>. I will give gold to " .. goldtracking.accountant)
    else
        goldtracking.autohandover = false
        goldtracking.echo("Auto-Handover <red>DISABLED<msSilver>.")
    end
end

goldtracking.toggle = function (enabled)
  local state = enabled:lower() == "on"
  goldtracking.enabled = state

  if state and goldtracking.count(goldtracking.names) == 0 and gmcp.Char and gmcp.Char.Name then
      goldtracking.add(gmcp.Char.Name.name:lower())
  end
  goldtracking.echo ("tracking " .. (state and "<msGold>enabled" or "<msSilver>disabled"))
  goldtracking.showprompt ()
end

goldtracking.plus = function (amt, noecho)
  local original_amt = amt
  local x = goldtracking

  if x.org.name then
    x.org.gold = x.org.gold + original_amt * (x.org.percent/100)
    amt = original_amt * ( 1 - x.org.percent/100)
  end

  local num = goldtracking.count(x.names)
  if num > 0 then
      local split_share = amt / num
      for k, v in pairs (x.names) do
        x.names[k] = v + split_share
      end
  end

  x.total = x.total + original_amt
  if not noecho then x.echo ("<msGold>" .. original_amt .. " <msSilver>gold added") end
  x.showprompt ()
end

goldtracking.minus = function (amt)
  local x = goldtracking
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
  x.echo ("<msGold>" .. amt .. " <msSilver>gold removed.")
  x.showprompt ()
end

goldtracking.handle_loot = function (amt)
  if not goldtracking.enabled then return end
  local my_name = (gmcp and gmcp.Char and gmcp.Char.Name and gmcp.Char.Name.name) or "Unknown"
  local acc = goldtracking.accountant or my_name

  if acc == my_name then
      goldtracking.plus(amt, true)
  else
      if goldtracking.autohandover then
          send("give " .. amt .. " gold to " .. acc)
          goldtracking.echo("Looted <msGold>"..amt.."<msSilver>. Handing over to <msGold>"..acc)
      else
          send("pt I picked up " .. amt .. " gold.")
          goldtracking.echo("Looted <msGold>"..amt.."<msSilver>. Reported to party.")
      end
  end
end

goldtracking.add = function (name)
  name = name:lower()
  if goldtracking.names[name] == nil then
    goldtracking.echo ("Added <msGold>" .. name:title () .. " <msSilver>to tracking.")
    goldtracking.names[name] = 0
  else
    goldtracking.echo ("<msGold>" .. name:title () .. " <msSilver>is already being tracked.")
  end
  goldtracking.showprompt ()
end

goldtracking.add_party = function()
    goldtracking.echo("Scanning party members...")
    send("party", false)

    if goldtracking.party_trigger then killTrigger(goldtracking.party_trigger) end
    goldtracking.party_trigger = tempRegexTrigger("^\\s+([A-Z][a-z]+)", function()
        local name = matches[2]
        if name ~= "Party" and name ~= "The" then goldtracking.add(name) end
    end)

    tempTimer(1.5, function()
        if goldtracking.party_trigger then
            killTrigger(goldtracking.party_trigger)
            goldtracking.party_trigger = nil
            goldtracking.echo("Party scan complete.")
            goldtracking.showprompt()
        end
    end)
end

goldtracking.remove = function (name)
  name = name:lower()
  if goldtracking.names[name] ~= nil then
    goldtracking.echo ("removed <msGold>" .. name:title () .. " <msSilver>from tracking")
    goldtracking.echo ("<msGold>" .. name:title () .. " <msSilver>was at <msGold>" .. math.floor (goldtracking.names[name]) .. " <msSilver>gold.")
    goldtracking.names[name] = nil
  else
    goldtracking.echo ("<msGold>" .. name .. " <msSilver>is not currently being tracked.")
  end
  goldtracking.showprompt ()
end

goldtracking.pause = function (name)
  name = name:lower()
  if goldtracking.names[name] ~= nil then
    goldtracking.echo ("Gold tracking for <msGold>" .. name:title () .. " <msSilver>paused.")
    goldtracking.paused[name] = goldtracking.names[name]
    goldtracking.names[name] = nil
  end
  goldtracking.showprompt ()
end

goldtracking.unpause = function (name)
  name = name:lower()
  if goldtracking.paused[name] then
    goldtracking.echo ("Gold tracking for <msGold>" .. name:title () .. " <msSilver>unpaused.")
    goldtracking.names[name] = goldtracking.paused[name]
    goldtracking.paused[name] = nil
  end
  goldtracking.showprompt ()
end

goldtracking.reset = function ()
  if goldtracking.reset_pending then
      goldtracking.confirm_reset()
      if goldtracking.reset_timer then killTimer(goldtracking.reset_timer) end
      goldtracking.reset_pending = false
  else
      goldtracking.reset_pending = true
      cecho("\n<msSilver>[<msGold>GoldTracking<msSilver>]: <red>WARNING!<msSilver> This will wipe ALL data (Total: " .. goldtracking.total .. ").\n")
      cecho("<msSilver>Type <msGold>gold reset<msSilver> again within 6 seconds to confirm.\n")
      goldtracking.reset_timer = tempTimer(6, function()
          goldtracking.reset_pending = false
          cecho("\n<msSilver>[<msGold>GoldTracking<msSilver>]: Reset cancelled.\n")
      end)
  end
end

goldtracking.confirm_reset = function()
  goldtracking.names = {}
  goldtracking.paused = {}
  goldtracking.ledger = {}
  goldtracking.unknown_ledger = {}
  goldtracking.org = {name = false, percent = 0, gold = 0}
  goldtracking.total = 0
  goldtracking.expenses = 0
  goldtracking.starttime = os.time()

  if gmcp.Char and gmcp.Char.Name then goldtracking.add(gmcp.Char.Name.name) end
  goldtracking.set_baseline()
  goldtracking.echo ("<red>Tracker has been reset.<reset>")
  goldtracking.showprompt ()
end

goldtracking.distribute = function ()
  local cont = goldtracking.container or "pack"
  send ("get gold from " .. cont)
  
  -- Prevent spam disconnects by adding a slight delay between gives
  local delay = 0
  for k, v in pairs (goldtracking.names) do
    if k ~= gmcp.Char.Name.name:lower () then
      v = math.floor (v)
      if v > 0 then 
          tempTimer(delay, function() send ("give " .. v .. " gold to " .. k) end)
          delay = delay + 0.5
      end
    end
  end

  goldtracking.echo("Distributed gold from <msGold>" .. cont)
  cecho("\n\n<msSilver>Distribution complete. Verify everyone received their share, then type <msGold>gold reset<msSilver>.\n")
end

goldtracking.help = function ()
    cecho ("\n<msGold>GOLD TRACKING HELP <msSilver>(Commands start with <msGold>gold<msSilver>)\n")
    cecho ("<msSilver>----------------------------------------------------------------------\n")
    cecho ("<msGold>  BASIC CONTROLS\n")
    cecho ("    <msGold>gold <on|off>          <msSilver>- Turn tracker on/off.\n")
    cecho ("    <msGold>gold reset             <msSilver>- Reset all totals (Double tap to confirm).\n")
    cecho ("    <msGold>gold report            <msSilver>- Announce current totals to Party.\n")
    cecho ("\n<msGold>  GROUP & ACCOUNTING\n")
    cecho ("    <msGold>gold accountant <name> <msSilver>- Designate the banker (Default: You).\n")
    cecho ("    <msGold>gold autohandover <on|off> <msSilver>- Automatically give loot to Accountant.\n")
    cecho ("    <msGold>gold add <name>        <msSilver>- Add a person to the split list.\n")
    cecho ("    <msGold>gold party             <msSilver>- Auto-add your current party members.\n")
    cecho ("    <msGold>gold remove <name>     <msSilver>- Remove a person from the list.\n")
    cecho ("\n<msGold>  LOOT & AUTOMATION\n")
    cecho ("    <msGold>gold autoloot <on|off> <msSilver>- Toggle auto-looting.\n")
    cecho ("    <msGold>gold container <name>  <msSilver>- Set loot bag (e.g., 'pack').\n")
    cecho ("    <msGold>gold stash             <msSilver>- Move all carried gold to container.\n")
    cecho ("    <msGold>gold distribute        <msSilver>- Empty container and share gold.\n")
    cecho ("\n<msGold>  ADVANCED\n")
    cecho ("    <msGold>gold snapshot / check  <msSilver>- Capture 'Show Gold' to find hidden rewards.\n")
    cecho ("    <msGold>gold loot <amount>     <msSilver>- Manually simulate picking up loot.\n")
    cecho ("    <msGold>gold plus <amount>     <msSilver>- Manually add to Total.\n\n")
    goldtracking.showprompt ()
end

-- =========================================================== --
--                  REWARD/SNAPSHOT LOGIC                      --
-- =========================================================== --
goldtracking.set_baseline = function()
    goldtracking.baseline.set = false
    goldtracking.capture_mode = "baseline"
    send("show gold")
end

goldtracking.check_reward = function()
    if not goldtracking.baseline.set then
        goldtracking.echo("<yellow>Warning:<msSilver> No baseline established yet. Establishing now. Type <msGold>gold check<msSilver> after your next reward.")
        goldtracking.set_baseline()
        return
    end
    goldtracking.capture_mode = "check"
    send("show gold")
end

goldtracking.process_gold_capture = function(hand, bank)
    if type(hand) == "string" then hand = tonumber(string.gsub(hand, ",", "")) end
    if type(bank) == "string" then bank = tonumber(string.gsub(bank, ",", "")) end
    hand = hand or 0
    bank = bank or 0
    
    if goldtracking.capture_mode == "baseline" then
        goldtracking.baseline.hand = hand
        goldtracking.baseline.bank = bank
        goldtracking.baseline.set = true
        goldtracking.echo("Baseline set. Hand: " .. hand .. ", Bank: " .. bank)
        
    elseif goldtracking.capture_mode == "check" then
        local wealth_change = (hand + bank) - (goldtracking.baseline.hand + goldtracking.baseline.bank)
        local hidden_profit = wealth_change + goldtracking.expenses - goldtracking.total
        
        if hidden_profit > 0 then
            goldtracking.echo("<orange>Hidden Reward Detected!<msSilver> You gained <msGold>" .. hidden_profit .. "<msSilver> gold.")
            goldtracking.plus(hidden_profit)
        elseif hidden_profit < 0 then
             goldtracking.echo("Math check negative (" .. hidden_profit .. "). Did you spend gold we missed?")
        else
             goldtracking.echo("No hidden rewards found (Math is balanced).")
        end
        goldtracking.baseline.hand = hand
        goldtracking.baseline.bank = bank
        goldtracking.expenses = 0 
    end
    goldtracking.capture_mode = nil
end

-- =========================================================== --
--                     EVENT HANDLERS                          --
-- =========================================================== --
function goldtracking_login_check()
  if not gmcp or not gmcp.Char or not gmcp.Char.Name then return end
  local my_name = gmcp.Char.Name.name:title()

  if goldtracking.enabled and goldtracking.count(goldtracking.names) == 0 then
     goldtracking.add(my_name)
  end
  
  if goldtracking.accountant == "Unknown" or goldtracking.accountant == "Solina" then
      goldtracking.accountant = my_name
  end

  if goldtracking.pickup then
      goldtracking.echo("Auto-pickup is <msGold>ENABLED<msSilver>.")
  end
end

if goldtracking.login_handler then killAnonymousEventHandler(goldtracking.login_handler) end
goldtracking.login_handler = registerAnonymousEventHandler("gmcp.Char.Name", "goldtracking_login_check")

-- Inform user it successfully loaded
cecho("\n<green>Goldeneyes Core Loaded Successfully!<reset>\n")

-- =========================================================== --
--               DYNAMIC TRIGGERS & ALIASES                    --
-- =========================================================== --
goldtracking.trigger_ids = goldtracking.trigger_ids or {}
goldtracking.alias_ids = goldtracking.alias_ids or {}

goldtracking.create_triggers = function()
    -- 1. Clean up existing triggers/aliases to prevent duplicates on reload
    for _, id in pairs(goldtracking.trigger_ids) do killTrigger(id) end
    for _, id in pairs(goldtracking.alias_ids) do killAlias(id) end
    goldtracking.trigger_ids = {}
    goldtracking.alias_ids = {}

    -- 2. Mystery Gold Pickups
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^Some gold falls from the corpse and automatically flies into the hands of (\\w+)\\.", 
    [[
        local name_key = matches[2]:lower()
        if goldtracking.names[name_key] then
            goldtracking.unknown_ledger[name_key] = (goldtracking.unknown_ledger[name_key] or 0) + 1
            cecho(string.format("\n<red>[ALERT]: %s picked up a MYSTERY pile of gold! (Auto-loot artifact detected)", matches[2]))
            cecho("\n<red>       Please ask them how much they got and use 'gold plus <amount>'.")
        end
    ]]))

    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^.*sovereigns spills from the corpse, flying into the hands of.*before they ", 
    [[
        -- Catches the alternate artifact message, but doesn't capture the name easily.
        cecho("\n<red>[ALERT]: Someone's artifact just auto-looted a MYSTERY pile of gold!<reset>")
    ]]))

    -- 3. Shop Purchases & Bribes (Expenses)
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^You pay ([\\d,]+) gold sovereigns\\.$", [[ goldtracking.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^You buy .* for ([\\d,]+) gold\\.$", [[ goldtracking.add_expense(tonumber((matches[2]:gsub(",", "")))) ]]))
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^You give ([\\d,]+) gold to .*$", [[ -- Expense ignored unless explicitly tracked ]]))

    -- 4. Gold Picked Up (You)
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^You (?:pick|scoop) up ([\\d,]+) gold", 
    [[
        local amount = tonumber((matches[2]:gsub(",", "")))
        if amount then goldtracking.handle_loot(amount) end
    ]]))

    -- 5. Gold Dropped (Grab It)
    local grab_script = [[ if goldtracking.enabled and goldtracking.pickup then send("queue add eqbal get gold", false) end ]]
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^A.*sovereigns? spills? from the corpse", grab_script))
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("A pile of golden sovereigns twinkles and gleams\\.", grab_script))
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("There is.*pile of golden sovereigns here\\.", grab_script))
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("pile of .*sovereigns?", grab_script))

    -- 6. Gold Received (Handover)
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^(\\w+) gives you ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if goldtracking.names[name_key] then
            goldtracking.plus(amount)
            if goldtracking.ledger[name_key] then
                goldtracking.ledger[name_key] = goldtracking.ledger[name_key] - amount
                cecho(string.format("\n<msSilver>[<msGold>GoldTracking<msSilver>]: %s paid off %d (Remaining: %d).", name, amount, goldtracking.ledger[name_key]))
                if goldtracking.ledger[name_key] <= 0 then
                    goldtracking.ledger[name_key] = nil
                    cecho(string.format("\n<msSilver>[<msGold>GoldTracking<msSilver>]: %s has settled their debt.", name))
                end
            else
                cecho(string.format("\n<msSilver>[<msGold>GoldTracking<msSilver>]: Accepted %d gold from %s (No prior debt).", amount, name))
            end
        end
    ]]))

    -- 7. Gold Tracking - Watchdog (Others)
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^(\\w+) (?:picks|scoops) up ([\\d,]+) gold", 
    [[
        local name = matches[2]
        local amount = tonumber((matches[3]:gsub(",", "")))
        local name_key = name:lower()

        if goldtracking.names[name_key] then
            goldtracking.ledger[name_key] = (goldtracking.ledger[name_key] or 0) + amount
            cecho(string.format("\n<msSilver>[<msGold>GoldTracking<msSilver>]: <orange>ALERT<msSilver>: <msGold>%s<msSilver> picked up <orange>%d<msSilver> gold!", name, amount))
        end
    ]]))

    -- 8. Capture Gold (All Sources)
    table.insert(goldtracking.trigger_ids, tempRegexTrigger("^You have .* gold sovereigns? in your .*", 
    [[
        if goldtracking.capture_mode then
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
            goldtracking.process_gold_capture(total_hand, total_bank)
        end
    ]]))

    -- 9. The Main Controller Alias
    table.insert(goldtracking.alias_ids, tempAlias("^(?:goldtracking|gold)(?:\\s+(.*))?$", 
    [[
        local args_str = matches[2] or ""
        local args = args_str:split(" ")
        local cmd = args[1] and args[1]:lower() or ""

        if cmd == "" then goldtracking.display()
        elseif cmd == "help" then goldtracking.help()
        elseif cmd == "on" or cmd == "off" then goldtracking.toggle(cmd)
        elseif cmd == "autoloot" then goldtracking.togglepickup(args[2] or "")
        elseif cmd == "container" then 
            if args[2] then goldtracking.setcontainer(args[2]) else cecho("\n<msSilver>Usage: <msGold>gold container <name>") end
        elseif cmd == "stash" then goldtracking.stash()
        elseif cmd == "add" then if args[2] then goldtracking.add(args[2]) end
        elseif cmd == "party" then goldtracking.add_party()
        elseif cmd == "remove" then if args[2] then goldtracking.remove(args[2]) end
        elseif cmd == "plus" then local amt = tonumber(args[2]); if amt then goldtracking.plus(amt) end
        elseif cmd == "minus" then local amt = tonumber(args[2]); if amt then goldtracking.minus(amt) end
        elseif cmd == "pause" then if args[2] then goldtracking.pause(args[2]) end
        elseif cmd == "unpause" then if args[2] then goldtracking.unpause(args[2]) end
        elseif cmd == "reset" then goldtracking.reset()
        elseif cmd == "distribute" then goldtracking.distribute()
        elseif cmd == "snapshot" then goldtracking.start_snapshot()
        elseif cmd == "check" then goldtracking.check_reward()
        elseif cmd == "report" then goldtracking.announce("party")
        elseif cmd == "accountant" then 
            if args[2] then goldtracking.set_accountant(args[2]) else cecho("\n<msSilver>Current Accountant: <msGold>" .. goldtracking.accountant) end
        elseif cmd == "loot" then 
            local amt = tonumber(args[2]); if amt then goldtracking.handle_loot(amt) else cecho("\n<msSilver>Usage: <msGold>gold loot <amount>") end
        elseif cmd == "autohandover" then goldtracking.toggle_handover(args[2] or "")
        else cecho("\n<msSilver>Unknown command. Try <msGold>gold help<msSilver>.") end
    ]]))

    goldtracking.echo("Dynamic triggers and aliases loaded.")
end

-- Initialize triggers on load
goldtracking.create_triggers()