--[[
    Author: Dennis Werner Garske (DWG)
    License: MIT License
]]

-- Setup to wrap our stuff in a table so we don't pollute the global environment
local _G = _G or getfenv(0);
local Roids = _G.Roids or {};
_G.Roids = Roids;
Roids.Hooks = Roids.Hooks or {};
Roids.mouseoverUnit = Roids.mouseoverUnit or nil;

Roids.Extensions = Roids.Extensions or {};

-- Speedy references to utility functions
local ToLower = Roids.ToLower
local UnderscoreToSpace = Roids.UnderscoreToSpace
local splitStringIgnoringQuotes = Roids.splitStringIgnoringQuotes
local Trim = Roids.Trim
local splitString = Roids.splitString

-- Speedy references to string library
local strfind = string.find
local strsub = string.sub
local strlen = string.len
local strgsub = string.gsub
local strgfind = string.gfind

Roids.has_superwow = SetAutoloot and true or false

-- Parse result cache (keyed by raw message string)
local parse_cache = {}

local function shallow_copy_conditionals(conditionals)
    if not conditionals then return nil end
    local copy = {}
    for k, v in pairs(conditionals) do
        copy[k] = v
    end
    return copy
end

-- GUID tracking table for targeting by GUID
-- Maps full GUIDs to unit names (e.g., "0x0000000600001234" -> "Goober")
Roids.GuidToUnitName = Roids.GuidToUnitName or {};

-- Executes the given Macro's body
-- body: The Macro's body
function Roids.ExecuteMacroBody(body,inline)
    local lines = splitString(body, "\n");
    if inline then lines = splitString(body, "\\n"); end
    -- print(body)
    for k,v in pairs(lines) do
        -- print(v)
        ChatFrameEditBox:SetText(v);
        ChatEdit_SendText(ChatFrameEditBox);
    end
    return true
end

-- Gets the body of the Macro with the given name
-- name: The name of the Macro
-- returns: The body of the macro
function Roids.GetMacroBody(name)
    local macroId = GetMacroIndexByName(name);
    if not macroId then
        return false;
    end

    local _,_, body = GetMacroInfo(macroId);
    if not body and SuperMacroFrame ~= nil then
        body = GetSuperMacroInfo(name, "body");
    end

    return body;
end

-- Attempts to execute a macro by the given name
-- name: The name of the macro
-- returns: Whether the macro was executed or not
function Roids.ExecuteMacroByName(name)
    local body = Roids.GetMacroBody(name);
    if not body then
        return false;
    end

    Roids.ExecuteMacroBody(body);
    return true;
end

-- Searches for a ':', '>' or '<' in the given word and returns its position
-- word: The word to search in
-- returns: The position of the delimeter or nil and 1 for '>' or 2 for '<'
function Roids.FindDelimeter(word)
    local delimeter = strfind(word, ":");
    local which = nil;
    
    if not delimeter then
        delimeter = strfind(word, ">");
        which = 1;
        if not delimeter then
            delimeter = strfind(word, "<");
            which = 0;
        end
        -- if not delimeter then
        --     delimeter = strfind(word, "=");
        --     which = 2;
        -- end
    end
    
    if not delimeter then
        which = nil;
    end
    
    return delimeter, which;
end

-- Parses the given message and looks for any conditionals
-- msg: The message to parse
-- returns: A set of conditionals found inside the given string
local function parseMsgInner(msg)
    local modifier = "";
    local modifierEnd = strfind(msg, "]");
    local help = nil;

    -- If we find conditionals trim down the message to everything except the conditionals
    if strsub(msg, 1, 1) == "[" and modifierEnd then
        modifier = strsub(msg, 2, modifierEnd - 1);
        msg = strsub(msg, modifierEnd + 1);
    -- No conditionals found. Just return the message as is
    elseif strsub(msg, 1, 1) ~= "!" then
        return msg;
    end

    local target;
    local conditionals = {};

    msg = Trim(msg)

    if strsub(msg, 1, 1) == "!" then
        msg = strsub(msg, 2);
        conditionals.checkchanneled = msg;
    end

    local pattern = "(@?%w+:?>?<?%w*[><:'_?%-?%w*]*[#/?_?%w*.?]*)";
    -- print(modifier)
    for w in strgfind(modifier, pattern) do
        local delimeter, which = Roids.FindDelimeter(w);
        -- print(delimeter)
        -- print(which)
        -- x:y
        if delimeter then
            local conditional = strsub(w, 1, delimeter - 1);
            local rest = strsub(w, delimeter+1);
            conditionals[conditional] = conditionals[conditional] or {}
            -- print("cond "..conditional)
            -- print("rest "..rest)
            if which then
                -- print("condwhich1 "..which.." "..conditional)
                table.insert(conditionals[conditional], { bigger = which, amount = tonumber(strsub(w, delimeter + 1)) })
                -- conditionals[conditional] = { bigger = which, amount = strsub(w, delimeter + 1) };
            else
                -- conditionals[conditional] = rest;

                delimeter, which = Roids.FindDelimeter(rest);
                if delimeter then
                    local conditional2 = strsub(rest, 1, delimeter - 1);
                    local rest2 = strsub(rest, delimeter+1);
                    -- print("cond "..conditional2)
                    -- print("rest "..rest2)
                    -- print("rest "..delimeter)
                    if which then
                        -- print("condwhich2 "..which.." "..conditional2)
                        table.insert(conditionals[conditional], { name = conditional2, bigger = which, amount = rest2 })
                        -- conditionals[conditional] = { name = conditional2, bigger = which, amount = rest2 };
                    else
                        table.insert(conditionals[conditional], strsub(rest2, delimeter + 1) )
                        -- conditionals[conditional] = strsub(rest2, delimeter + 1);
                    end
                else
                    -- print(conditional)
                    -- print(rest)
                    table.insert(conditionals[conditional], rest)
                end
                -- print("condnotwhich "..conditional)
            end
        -- @target
        elseif strsub(w, 1, 1) == "@" then
            conditionals["target"] = strsub(w,  2);
        -- Any other keyword like harm or help
        elseif Roids.Keywords[w] ~= nil then
            if w == "casting" or w == "nocasting" then
                conditionals[w] = conditionals[w] or {}
                table.insert(conditionals[w], "")
            else
                conditionals[w] = 1;
            end
        end
    end

    return msg, conditionals;
end

-- Cached wrapper around parseMsgInner
function Roids.parseMsg(msg)
    local cached = parse_cache[msg]
    if cached then
        return cached.msg, shallow_copy_conditionals(cached.conditionals)
    end

    local result_msg, result_conditionals = parseMsgInner(msg)
    parse_cache[msg] = { msg = result_msg, conditionals = result_conditionals }
    return result_msg, shallow_copy_conditionals(result_conditionals)
end

function Roids.SetHelp(conditionals)
    if conditionals.help then
        conditionals.help = 1;
    elseif conditionals.harm then
        conditionals.help = 0;
    end
end

-- Fixes the conditionals' target by using the player's current target if it exists or falling back to the player itself if it doesn'target
-- conditionals: The conditionals containing the current target
-- returns: Whether or not we've changed the player's current target
function Roids.FixEmptyTarget(conditionals)
    if not conditionals.target then
        if UnitExists("target") then
            conditionals.target = "target";
        elseif GetCVar("autoSelfCast") == "1" then
            conditionals.target = "player";
        end
    end
    
    return false;
end

-- Fixes the conditionals' target by targeting the target with the given name
-- conditionals: The conditionals containing the current target
-- name: The name of the player to target
-- hook: The target hook
-- returns: Whether or not we've changed the player's current target
function Roids.FixEmptyTargetSetTarget(conditionals, name, hook)
    if not conditionals.target then
        hook(name);
        conditionals.target = "target";
        return true;
    end
    return false;
end

-- Returns the name of the focus target or nil
function Roids.GetFocusName()
    if ClassicFocus_CurrentFocus then
        return ClassicFocus_CurrentFocus;
    elseif CURR_FOCUS_TARGET then
        return CURR_FOCUS_TARGET;
    end
    
    return nil;
end

-- Attempts to target the focus target.
-- returns: Whether or not it succeeded
function Roids.TryTargetFocus()
    local name = Roids.GetFocusName();
    
    if not name then
        return false;
    end
    
    Roids.Hooks.TARGET_SlashCmd(name);
    return true;
end

-- Does the given action with a set of conditionals provided by the given msg
-- msg: The conditions followed by the action's parameters
-- hook: The hook of the function we've intercepted
-- fixEmptyTargetFunc: A function setting the player's target if the player has none. Required to return true if we need to re-target later or false if not
-- targetBeforeAction: A boolean value that determines whether or not we need to target the target given in the conditionals before performing the given action
-- action: A function that is being called when everything checks out
function Roids.DoWithConditionals(msg, hook, fixEmptyTargetFunc, targetBeforeAction, action)
    local msg, conditionals = Roids.parseMsg(msg);
    
    msg = Trim(msg);
    
    -- No conditionals. Just exit.
    if not conditionals then
        if not msg then -- if not even an empty string
            return false;
        else
            if strsub(msg, 1, 1) == "{" and strsub(msg, -1) == "}" then
                if strsub(msg, 2, 2) == "\"" and strsub(msg, -2, -2) == "\"" then
                    return Roids.ExecuteMacroBody(strsub(msg, 3, -3), true);
                else
                    return Roids.ExecuteMacroByName(strsub(msg, 2, -2));
                end
            end
            
            if hook then
                hook(msg);
            end
            return true;
        end
    end

    if conditionals.target == "mouseover" then
        if not UnitExists("mouseover") then
            conditionals.target = Roids.mouseoverUnit;
        end
        if not conditionals.target or (conditionals.target ~= "focus" and not UnitExists(conditionals.target)) then
            return false;
        end
    end

    local needRetarget = false;
    if fixEmptyTargetFunc then
        needRetarget = fixEmptyTargetFunc(conditionals, msg, hook)
    end

    Roids.SetHelp(conditionals);

    if conditionals.target == "focus" then
        if UnitExists("target") and UnitName("target") == Roids.GetFocusName() then
            conditionals.target = "target";
            needRetarget = false;
        else
            if not Roids.TryTargetFocus() then
                return false;
            end
            conditionals.target = "target";
            needRetarget = true;
        end
    end

    for k, v in pairs(conditionals) do
        if not Roids.Keywords[k] or not Roids.Keywords[k](conditionals) then
            if needRetarget then
                TargetLastTarget();
                needRetarget = false;
            end
            return false;
        end
    end

    if conditionals.target ~= nil and targetBeforeAction and not (Roids.has_superwow and action == CastSpellByName) then
        if not UnitIsUnit("target", conditionals.target) then
            needRetarget = true;
        end
        
        if SpellIsTargeting() then
            SpellStopCasting()
        end

        TargetUnit(conditionals.target);
    else
        if needRetarget then
            TargetLastTarget();
            needRetarget = false;
        end
    end

    local result = true;
    if strsub(msg, 1, 1) == "{" and strsub(msg, -1) == "}" then
        if strsub(msg, 2, 2) == "\"" and strsub(msg, -2,-2) == "\"" then
            result = Roids.ExecuteMacroBody(strsub(msg, 3, -3), true);
        else
            result = Roids.ExecuteMacroByName(strsub(msg, 2, -2));
        end
    else
        if Roids.has_superwow and action == CastSpellByName and conditionals.target then
            action(msg,conditionals.target);
        else
            action(msg);
        end
    end

    if needRetarget then
        TargetLastTarget();
    end

    return result;
end

-- Attempts to cast a single spell from the given set of conditional spells
-- msg: The player's macro text
function Roids.DoCast(msg)
    local handled = false;
    msg = Trim(msg);

    for k, v in pairs(splitStringIgnoringQuotes(msg)) do
    -- for k, v in pairs(splitString(msg,";%s*")) do
        if Roids.DoWithConditionals(v, Roids.Hooks.CAST_SlashCmd, Roids.FixEmptyTarget, not Roids.has_superwow, CastSpellByName) then
            handled = true; -- we parsed at least one command
            break;
        end
    end
    return handled;
end

-- Attempts to target a unit by its name or GUID using a set of conditionals
-- msg: The raw message intercepted from a /target command
-- Supports GUID targeting: full 18-char GUID uses TargetUnit directly,
-- shorter GUIDs starting with 0x scan the tracked GUID table
function Roids.DoTarget(msg)
    local handled = false;
    msg = ToLower(msg)

    local action = function(msg)
        if strsub(msg, 1, 1) == "@" then
            msg = UnitName(strsub(msg, 2));
        end

        -- Check if msg looks like a GUID (starts with 0x)
        if strsub(msg, 1, 2) == "0x" then
            local len = strlen(msg)
            if len == 18 then
                -- Full GUID - use TargetUnit directly
                TargetUnit(msg)
                return
            else
                -- Partial GUID - look up unit from tracked table
                local unit = nil
                local srch = "^"..msg
                for fullGuid, _ in pairs(Roids.GuidToUnitName) do
                    if strfind(ToLower(fullGuid), srch) then
                        if not unit then
                            unit = fullGuid
                        end
                        if not UnitIsDead(fullGuid) then
                            unit = fullGuid
                            break
                        end
                    end
                end
                if unit then
                    TargetUnit(unit)
                else
                    Roids.Hooks.TARGET_SlashCmd(msg)
                end
                return
            end
        end

        Roids.Hooks.TARGET_SlashCmd(msg);
    end

    for k, v in pairs(splitStringIgnoringQuotes(msg)) do
        if Roids.DoWithConditionals(v, action, Roids.FixEmptyTargetSetTarget, false, action) then
            handled = true;
            break;
        end
    end
    return handled;
end

-- Attempts to attack a unit by a set of conditionals
-- msg: The raw message intercepted from a /petattack command
function Roids.DoPetAttack(msg)
    local handled = false;
    for k, v in pairs(splitStringIgnoringQuotes(msg)) do
        if Roids.DoWithConditionals(v, PetAttack, Roids.FixEmptyTarget, true, PetAttack) then
            handled = true;
            break;
        end
    end
    return handled;
end

-- Searches for the given itemName in the player's iventory
-- itemName: The name/id of the item to look for
-- returns: The bag number and the slot number if the item has been found. nil otherwhise
local items_table = {}
function Roids.FindItem(itemName)
    -- just in case, prob not neccesary given where FindItem is used
    local itemName = UnderscoreToSpace(itemName);

    -- check stored table, micro-optimization
    if items_table[itemName] then
        local link = GetContainerItemLink(items_table[itemName].bag,items_table[itemName].slot)
        if link then
            local _,_,full_itemId,itemId = strfind(link,"(item:(%d+):%d+:%d+:%d+)")
            local name,_link,_,_lvl,_type,subtype = GetItemInfo(full_itemId)
            if itemId and itemId == itemName or itemName == name then
                return items_table[itemName].bag, items_table[itemName].slot;
            end
        end
    end

    -- check inv first, unlikely that bags are a smaller search space
    local slotLink = nil
    for i = 0, 19 do
        slotLink = GetInventoryItemLink("player",i)
        if slotLink then
            local _,_,full_itemId,itemId = strfind(slotLink,"(item:(%d+):%d+:%d+:%d+)")
            if itemName == itemId then
                return -i
            end
            -- local gearName = strgsub(itemId, "_", " ");
            local name,_link,_,_lvl,_type,subtype = GetItemInfo(full_itemId)
            if name == itemName then
                return -i
            end
        end
    end

    -- no item stored? search
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag,slot)
            if link then
                local _,_,full_itemId,itemId = strfind(link,"(item:(%d+):%d+:%d+:%d+)")
                local name,_link,_,_lvl,_type,subtype = GetItemInfo(full_itemId)
                if itemId and itemId == itemName or itemName == name then
                    items_table[itemName] = items_table[itemName] or {}
                    items_table[itemName].bag,items_table[itemName].slot = bag,slot
                    return bag, slot;
                end
            end
        end
    end
end

function Roids.DoCancelAura(msg)
    local handled = false;

    local handled = false;
    msg = Trim(msg);

    for k, v in pairs(splitStringIgnoringQuotes(msg)) do
        if Roids.DoWithConditionals(v, Roids.CancelAura, Roids.FixEmptyTarget, not Roids.has_superwow, Roids.CancelAura) then
            handled = true; -- we parsed at least one command
            break
        end
    end
    return handled
end

-- Attempts to use or equip an item from the player's inventory by a  set of conditionals
-- Also checks if a condition is a spell so that you can mix item and spell use
-- msg: The raw message intercepted from a /use or /equip command
function Roids.DoUse(msg)
    local handled = false;

    local checkFor = function(msg,bookType)
        local i = 1
        local msg_g = UnderscoreToSpace(msg);
        while true do
            local name, spellRank = GetSpellName(i, bookType);

            if not name then
                break;
            end
            
            if name == msg_g then
                return true
            end
            
            i = i + 1
        end
        return false
    end

    local action = function(msg)
        -- check if it's an item slot, e.g. trinkets: /use 13
        local n = tonumber(msg)
        if n and n < 21 then
            return UseInventoryItem(n);
        end

        local bag, slot = Roids.FindItem(msg);
        
        if bag and bag < 0 then
            return UseInventoryItem(-bag);
        end
        
        if not bag or not slot then
            return;
        end
        if (MerchantFrame:IsVisible() and MerchantFrame.selectedTab == 1) then return end
        UseContainerItem(bag, slot)
    end

    for k, v in pairs(splitStringIgnoringQuotes(msg)) do
        local subject = v
        local _,e = strfind(v,"%]")
        if e then subject = Trim(strsub(v,e+1)) end
        if checkFor(subject,BOOKTYPE_PET) or checkFor(subject,BOOKTYPE_SPELL) then
            handled = Roids.DoWithConditionals(v, Roids.Hooks.CAST_SlashCmd, Roids.FixEmptyTarget, not Roids.has_superwow, CastSpellByName)
        else
            -- TODO false needs checking here, for things like juju power we have an issue
            -- we need to target the spell but targeting before cast counts as a target change
            -- and this is potentially bad for things like the OH swing timer reset bug
            handled = Roids.DoWithConditionals(v, action, Roids.FixEmptyTarget, false, action)
        end
        if handled then break end
    end
    return handled
end

function Roids.DoEquipOffhand(msg)
    local handled = false;
    
    local action = function(msg)
        local bag, slot = Roids.FindItem(msg);
        if not bag or not slot then
            return;
        end
        PickupContainerItem(bag, slot);
        PickupInventoryItem(17);
    end
    
    for k, v in pairs(splitStringIgnoringQuotes(msg)) do
        if Roids.DoWithConditionals(v, action, Roids.FixEmptyTarget, false, action) then
            handled = true;
            break;
        end
    end
    return handled;
end

function Roids.DoUnshift(msg)
    local handled;
    
    local action = function(msg)
        local currentShapeshiftIndex = Roids.GetCurrentShapeshiftIndex();
        if currentShapeshiftIndex ~= 0 then
            CastShapeshiftForm(currentShapeshiftIndex);
        end
    end
    
    for k, v in pairs(splitStringIgnoringQuotes(msg)) do
        handled = false;
        if Roids.DoWithConditionals(v, action, Roids.FixEmptyTarget, false, action) then
            handled = true;
            break;
        end
    end
    
    if handled == nil then
        action();
    end
    
    return handled;
end

-- Holds information about the currently cast spell
Roids.CurrentSpell = {
    -- "channeled" or "cast"
    type = "",
    -- the name of the spell
    spellName = "",
    -- is the Attack ability enabled
    autoAttack = false,
    -- is the Auto Shot ability enabled
    autoShot = false,
    -- is the Shoot ability (wands) enabled
    wand = false,
};

-- Dummy Frame to hook ADDON_LOADED event in order to preserve compatiblity with other AddOns like SuperMacro
Roids.Frame = CreateFrame("FRAME");
Roids.Frame:RegisterEvent("ADDON_LOADED");
Roids.Frame:RegisterEvent("SPELLCAST_CHANNEL_START");
Roids.Frame:RegisterEvent("SPELLCAST_CHANNEL_STOP");
Roids.Frame:RegisterEvent("SPELLCAST_INTERRUPTED");
Roids.Frame:RegisterEvent("SPELLCAST_FAILED");
Roids.Frame:RegisterEvent("UNIT_CASTEVENT");
Roids.Frame:RegisterEvent("PLAYER_ENTER_COMBAT");
Roids.Frame:RegisterEvent("PLAYER_LEAVE_COMBAT");
-- Roids.Frame:RegisterEvent("PLAYER_REGEN_ENABLED");
Roids.Frame:RegisterEvent("PLAYER_TARGET_CHANGED");
Roids.Frame:RegisterEvent("START_AUTOREPEAT_SPELL");
Roids.Frame:RegisterEvent("STOP_AUTOREPEAT_SPELL");
Roids.Frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED");
Roids.Frame:RegisterEvent("UNIT_FLAGS");
Roids.Frame:RegisterEvent("UNIT_MODEL_CHANGED");
Roids.Frame:RegisterEvent("PLAYER_ENTERING_WORLD");
-- Roids.Frame:RegisterEvent("UI_ERROR_MESSAGE");

Roids.Frame:SetScript("OnEvent", function()
    Roids.Frame[event](this,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg10)
end)

function Roids.Frame:ADDON_LOADED(addon)
    if addon ~= "Roid-Macros" then
        return
    end

    Roids.InitializeExtensions();

    if SuperMacroFrame then
        local hooks = {
            cast = { action = Roids.DoCast },
            target = { action = Roids.DoTarget },
            use = { action = Roids.DoUse },
        }

        -- Hook SuperMacro's RunLine to stay compatible
        Roids.Hooks.RunLine = RunLine;
        Roids.RunLine = function(...)
            for i = 1, arg.n do
                local intercepted = false;
                local text = arg[i];

                for k,v in pairs(hooks) do
                    local begin, _end = strfind(text, "^/"..k.."%s+[!%[]");
                    if begin then
                        local msg = strsub(text, _end);
                        v.action(msg);
                        intercepted = true;
                        break
                    end
                end

                if not intercepted then
                    Roids.Hooks.RunLine(text);
                end
            end
        end
        RunLine = Roids.RunLine;
    end
end

Roids.spell_tracking = {}
function Roids.Frame:UNIT_CASTEVENT(caster,target,action,spell_id,cast_time)
    if action == "MAINHAND" or action == "OFFHAND" then return end

    local cast = Roids.spell_tracking[caster]
    if cast_time > 0 and action == "START" or action == "CHANNEL" then
        -- print(SpellInfo(spell_id).." "..spell_id.." start "..action)
        Roids.spell_tracking[caster] = { spell_id = spell_id, cast_time = cast_time/1000, started = GetTime(), type = action }
    elseif cast and ((cast.spell_id == spell_id and (action == "FAIL" or action == "CAST")) or
            (GetTime() > cast.started + cast.cast_time)) then
        -- print(SpellInfo(spell_id).." "..spell_id.." finished "..action)

        Roids.spell_tracking[caster] = nil
    end
end

function Roids.Frame:SPELLCAST_CHANNEL_START()
    Roids.CurrentSpell.type = "channeled";
end

function Roids.Frame:SPELLCAST_CHANNEL_STOP()
    Roids.CurrentSpell.type = "";
    Roids.CurrentSpell.spellName = "";
end

Roids.Frame.SPELLCAST_INTERRUPTED = Roids.Frame.SPELLCAST_CHANNEL_STOP;
Roids.Frame.SPELLCAST_FAILED = Roids.Frame.SPELLCAST_CHANNEL_STOP;

function Roids.Frame:UI_ERROR_MESSAGE()
--     if arg1 == ERR_NO_ATTACK_TARGET or strfind(string.lower(arg1), "^Can't attack") or arg1 == ERR_INVALID_ATTACK_TARGET then
--         Roids.CurrentSpell.autoAttack = false
--     end
end

function Roids.Frame:PLAYER_ENTER_COMBAT()
    Roids.CurrentSpell.autoAttack = true;
    Roids.CurrentSpell.autoAttackLock = false
end

function Roids.Frame:PLAYER_LEAVE_COMBAT()
    Roids.CurrentSpell.autoAttack = false;
    Roids.CurrentSpell.autoAttackLock = false
    Roids.CleanupGuidTable()
end

-- just a secondary check, shouldn't matter much
function Roids.Frame:PLAYER_TARGET_CHANGED()
    -- clean useless spell tracks, there won't be that many
    for guid,cast in Roids.spell_tracking do
        if not UnitExists(guid) then
            Roids.spell_tracking[guid] = nil
        end
    end
    Roids.CurrentSpell.autoAttack = false;
    Roids.CurrentSpell.autoAttackLock = false
    -- print("tarchange")
end

-- just a secondary check
-- function Roids.Frame:PLAYER_REGEN_ENABLED()
--     Roids.CurrentSpell.autoAttack = false;
-- end

-- Did a reactive slot change? clear it
function Roids.Frame:ACTIONBAR_SLOT_CHANGED(slot)
    local tex = ToLower(GetActionTexture(slot) or "")
    local _,class = UnitClass("player")
    local reactive_name = Roids.reactives[class] and Roids.reactives[class][tex]

    -- slot uses the icon of a reactive, so clear that reactive so it can be rechecked
    -- this clears -1's for instance, to trigger a re-search
    -- ignore macros
    if not GetActionText(slot) and reactive_name then
        Roids.live_reactives[reactive_name] = nil
        return
    end

    -- search to see if this slot was a reactive, clear if it was
    for spell,s in Roids.live_reactives do
        if s == slot then
            Roids.live_reactives[spell] = nil
            return
        end
    end
end

-- Tracks a unit's GUID when detected via UNIT_FLAGS or UNIT_MODEL_CHANGED
-- guid: The unit guid
function Roids.TrackUnitGuid(unit)
    local _,guid = UnitExists(unit)
    if not guid then return end

    local name = UnitName(guid)
    if name then
        Roids.GuidToUnitName[guid] = name
    end
end

function Roids.Frame:UNIT_FLAGS(unit)
    Roids.TrackUnitGuid(unit)
end

function Roids.Frame:UNIT_MODEL_CHANGED(unit)
    Roids.TrackUnitGuid(unit)
end

-- Cleans up GUIDs that no longer exist in the world
function Roids.CleanupGuidTable()
    for guid, name in pairs(Roids.GuidToUnitName) do
        if not UnitExists(guid) then
            Roids.GuidToUnitName[guid] = nil
        end
    end
end

function Roids.Frame:PLAYER_ENTERING_WORLD()
    Roids.CleanupGuidTable()
end

function Roids.Frame:START_AUTOREPEAT_SPELL(...)
    local _, className = UnitClass("player");
    if className == "HUNTER" then
        Roids.CurrentSpell.autoShot = true;
    else
        Roids.CurrentSpell.wand = true;
    end
end

function Roids.Frame:STOP_AUTOREPEAT_SPELL(...)
    local _, className = UnitClass("player");
    if className == "HUNTER" then
        Roids.CurrentSpell.autoShot = false;
    else
        Roids.CurrentSpell.wand = false;
    end
end


Roids.Hooks.SendChatMessage = SendChatMessage;

function SendChatMessage(msg, ...)
    if msg and strfind(msg, "^#showtooltip ") then
        return;
    end
    Roids.Hooks.SendChatMessage(msg, unpack(arg));
end
