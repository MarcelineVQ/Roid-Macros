--[[
	Author: Dennis Werner Garske (DWG)
	License: MIT License
]]
local _G = _G or getfenv(0)
local Roids = _G.Roids or {}

-- local caches to reduce search times for cooldown purposes
local item_cache = {}
local spell_cache = {}

function print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- Function to get buffs or debuffs based on `isbuff`
local function getAura(unit, index, buff)
    if buff then
        local _, stacks, aura_id = UnitBuff(unit, index)
        return stacks, aura_id
    else
        local _, stacks, _, aura_id = UnitDebuff(unit, index)
        return stacks, aura_id
    end
end

-- Validates that the given target is either friend (if [help]) or foe (if [harm])
-- target: The unit id to check
-- help: Optional. If set to 1 then the target must be friendly. If set to 0 it must be an enemy.
-- remarks: Will always return true if help is not given
-- returns: Whether or not the given target can either be attacked or supported, depending on help
function Roids.CheckHelp(target, help)
	if help then
		if help == 1 then
            return UnitCanAssist("player", target);
		else
			return UnitCanAttack("player", target);
		end
	end
	return true;
end

-- Ensures the validity of the given target
-- target: The unit id to check
-- help: Optional. If set to 1 then the target must be friendly. If set to 0 it must be an enemy
-- returns: Whether or not the target is a viable target
function Roids.IsValidTarget(target, help)
	if target ~= "mouseover" then
		if not Roids.CheckHelp(target, help) or not UnitExists(target) then
			return false;
		end
		return true;
	end
	
	if (not Roids.mouseoverUnit) and not UnitName("mouseover") then
		return false;
	end
    
	return Roids.CheckHelp(target, help);
end

-- Returns the current shapeshift / stance index
-- returns: The index of the current shapeshift form / stance. 0 if in no shapeshift form / stance
function Roids.GetCurrentShapeshiftIndex()
    for i=1, GetNumShapeshiftForms() do
        _, _, active = GetShapeshiftFormInfo(i);
        if active then
            return i; 
        end
    end
    
    return 0;
end

function Roids.CancelAura(auraName)
    local ix = 0
    while true do
        local aura_ix = GetPlayerBuff(ix,"HELPFUL")
        ix = ix + 1
        if aura_ix == -1 then break end
        auraName = string.gsub(auraName, "_"," ")
        local bid = GetPlayerBuffID(aura_ix)
        bid = (bid < -1) and (bid + 65536) or bid
        if string.lower(SpellInfo(bid)) == string.lower(auraName) then
            CancelPlayerBuff(aura_ix)
            break
        end
    end
end

function Roids.ValidateAura(aura_data, isbuff, unit)
    if not unit then
        -- Roids.Print("[no][de]buff condition does not have a target!")
        return false
    end
    if not Roids.has_superwow then
        Roids.Print("'buff/debuff' conditional requires SuperWoW")
        return false
    end
    local limit,amount
    local name = aura_data
    if type(aura_data) == "table" then
        limit = aura_data.bigger
        name = aura_data.name
        _,_,amount = string.find(aura_data.amount,"^#(%d+)")
        if not amount then
            Roids.Print("invalid stack amount argument!")
            return false
        end
        amount = tonumber(amount)
    end
    name = string.gsub(name, "_", " ")

    local stack_count = 0
    local i = 1
    while true do
        local stacks, aura_id = getAura(unit, i, isbuff)
        if not aura_id then break end  -- End of buffs/debuffs list
        if aura_id < -1 then aura_id = aura_id + 65536 end
        if name == SpellInfo(aura_id) then
            stack_count = stacks or 1
            break
        end
        i = i + 1
    end

    if limit == 1 then
        return stack_count > amount
    elseif limit == 0 then
        return stack_count < amount
    else
        return stack_count ~= 0
    end
end

-- Checks whether or not the given textureName is present in the current player's buff bar
-- textureName: The full name (including path) of the texture
-- returns: True if the texture can be found, false otherwhise
function Roids.HasBuff(textureName)
    for i = 1, 16 do
        if UnitBuff("player", i) == textureName then
            return true;
        end
    end
    
    return false;
end

-- I need to make a 2h modifier
-- Maps easy to use weapon type names (e.g. Axes, Shields) to their inventory slot name and their localized tooltip name
Roids.WeaponTypeNames = {
    Daggers = { slot = "MainHandSlot", name = Roids.Localized.Dagger },
    Fists =  { slot = "MainHandSlot", name = Roids.Localized.FistWeapon },
    Axes =  { slot = "MainHandSlot", name = Roids.Localized.Axe },
    Swords =  { slot = "MainHandSlot", name = Roids.Localized.Sword },
    Staves =  { slot = "MainHandSlot", name = Roids.Localized.Staff },
    Maces =  { slot = "MainHandSlot", name = Roids.Localized.Mace },
    Polearms =  { slot = "MainHandSlot", name = Roids.Localized.Polearm },
    -- OH
    Daggers2 = { slot = "SecondaryHandSlot", name = Roids.Localized.Dagger },
    Fists2 = { slot = "SecondaryHandSlot", name = Roids.Localized.FistWeapon },
    Axes2 = { slot = "SecondaryHandSlot", name = Roids.Localized.Axe },
    Swords2 = { slot = "SecondaryHandSlot", name = Roids.Localized.Sword },
    Maces2 = { slot = "SecondaryHandSlot", name = Roids.Localized.Mace },
    Shields = { slot = "SecondaryHandSlot", name = Roids.Localized.Shield },
    -- ranged
    Guns = { slot = "RangedSlot", name = Roids.Localized.Gun },
    Crossbows = { slot = "RangedSlot", name = Roids.Localized.Crossbow },
    Bows = { slot = "RangedSlot", name = Roids.Localized.Bow },
    Thrown = { slot = "RangedSlot", name = Roids.Localized.Thrown },
    Wands = { slot = "RangedSlot", name = Roids.Localized.Wand },
};

-- Checks whether a given piece of gear is equipped is currently equipped
-- gearId: The name (or item id) of the gear (e.g. Badge_Of_The_Swam_Guard, etc.)
-- returns: True when equipped, otherwhise false
function Roids.HasGearEquipped(gearId)
    local slotLink
    for slotId=1,19 do
        slotLink = GetInventoryItemLink("player",slotId)
        if slotLink then
            local _,_,itemId = string.find(slotLink,"item:(%d+)")
            if gearId == itemId then
                return true
            end
            local gearName = string.gsub(gearId, "_", " ");
            local name,_link,_,_lvl,_type,subtype = GetItemInfo(itemId)
            if name == gearName then
                return true
            end
        end
    end
    return false
end

-- Checks whether or not the given weaponType is currently equipped
-- weaponType: The name of the weapon's type (e.g. Axe, Shield, etc.)
-- returns: True when equipped, otherwhise false
function Roids.HasWeaponEquipped(weaponType)
    if not Roids.WeaponTypeNames[weaponType] then
        return false;
    end
    
    local slotName = Roids.WeaponTypeNames[weaponType].slot;
    local localizedName = Roids.WeaponTypeNames[weaponType].name;
    local slotId = GetInventorySlotInfo(slotName);
    local slotLink = GetInventoryItemLink("player",slotId)
    if not slotLink then
        return false;
    end

    local _,_,itemId = string.find(slotLink,"item:(%d+)")
    local _name,_link,_,_lvl,_type,subtype = GetItemInfo(itemId)
    -- just had to be special huh?
    local fist = string.find(subtype,"^Fist")
    -- drops things like the One-Handed prefix
    local _,_,subtype = string.find(subtype,"%s?(%S+)$")

    if subtype == localizedName or (fist and (Roids.WeaponTypeNames[weaponType].name == Roids.Localized.FistWeapon)) then
        return true
    end

    return false;
end

-- Checks whether or not the given UnitId is in your party or your raid
-- target: The UnitId of the target to check
-- groupType: The name of the group type your target has to be in ("party" or "raid")
-- returns: True when the given target is in the given groupType, otherwhise false
function Roids.IsTargetInGroupType(target, groupType)
    local upperBound = 5;
    if groupType == "raid" then
        upperBound = 40;
    end
    
    -- use UnitIsUnit here? is it faster than name?
    for i = 1, upperBound do
        if UnitName(groupType..i) == UnitName(target) then
            return true;
        end
    end
    
    return false;
end

-- Checks whether or not we're currently casting a channeled spell
function Roids.CheckChanneled(conditionals)
    -- Remove the "(Rank X)" part from the spells name in order to allow downranking
    local spellName = string.gsub(Roids.CurrentSpell.spellName, "%(.-%)%s*", "");
    local channeled = string.gsub(conditionals.checkchanneled, "%(.-%)%s*", "");
    
    if Roids.CurrentSpell.type == "channeled" and spellName == channeled then
        return false;
    end
    
    if channeled == Roids.Localized.Attack then
        return not Roids.CurrentSpell.autoAttack;
    end
    
    if channeled == Roids.Localized.AutoShot then
        return not Roids.CurrentSpell.autoShot;
    end
    
    if channeled == Roids.Localized.Shoot then
        return not Roids.CurrentSpell.wand;
    end
    
    Roids.CurrentSpell.spellName = channeled;
    return true;
end

-- Checks whether or not the target has the specified number of combo points on it
-- bigger: 1 if the number needs to be bigger, 0 if it needs to be lower
-- amount: The required amount
-- returns: True or false
function Roids.ValidateCombo(bigger, amount)
	local cp = GetComboPoints()
    if bigger == 0 then
        return cp < tonumber(amount);
    end
    
    return cp > tonumber(amount);
end

-- Checks whether or not the given unit has more or less power in percent than the given amount
-- unit: The unit we're checking
-- bigger: 1 if the percentage needs to be bigger, 0 if it needs to be lower
-- amount: The required amount
-- returns: True or false
function Roids.ValidatePower(unit, bigger, amount)
    if not unit then return false end
    local powerPercent = 100 / UnitManaMax(unit) * UnitMana(unit);
    if bigger == 0 then
        return powerPercent < tonumber(amount);
    end
    
    return powerPercent > tonumber(amount);
end

-- Checks whether or not the given unit has more or less total power than the given amount
-- unit: The unit we're checking
-- bigger: 1 if the raw power needs to be bigger, 0 if it needs to be less
-- amount: The required amount
-- returns: True or false
function Roids.ValidateRawPower(unit, bigger, amount)
    if not unit then return false end
    local power = UnitMana(unit);
    if bigger == 0 then
        return power < tonumber(amount);
    end
    
    return power > tonumber(amount);
end

-- Checks whether or not the given unit has more or less hp in percent than the given amount
-- unit: The unit we're checking
-- bigger: 1 if the percentage needs to be bigger, 0 if it needs to be lower
-- amount: The required amount
-- returns: True or false
function Roids.ValidateHp(unit, bigger, amount)
    if not unit then return false end
    local powerPercent = 100 / UnitHealthMax(unit) * UnitHealth(unit);
    if bigger == 0 then
        return powerPercent < tonumber(amount);
    end
    
    return powerPercent > tonumber(amount);
end

-- Checks whether the given creatureType is the same as the target's creature type
-- creatureType: The type to check
-- target: The target's unitID
-- returns: True or false
-- remarks: Allows for both localized and unlocalized type names
function Roids.ValidateCreatureType(creatureType, target)
    if not target then return false end
    local targetType = UnitCreatureType(target)
    if not targetType then return false end -- ooze or silithid etc
    local ct = string.lower(creatureType)
    local cl = UnitClassification(target)
    if (ct == "boss" and "worldboss" or ct) == cl then
        return true
    end
    if string.lower(creatureType) == "boss" then creatureType = "worldboss" end
    local englishType = Roids.Localized.CreatureTypes[targetType];
    return string.lower(creatureType) == string.lower(targetType) or creatureType == englishType;
end

-- TODO this should technically keep a table of cooldowns it's seen and when, in case of something like GetContainerItemCooldownByName and you run out of the item
function Roids.ValidateCooldown(cooldown_data)
    local limit,amount
    local name = cooldown_data
    if type(cooldown_data) == "table" then
        limit = cooldown_data.bigger
        amount = tonumber(cooldown_data.amount)
        name = cooldown_data.name
    end
    name = string.gsub(name, "_", " ")

    local cd,start = Roids.GetSpellCooldownByName(name)
    if not cd then cd,start = Roids.GetInventoryCooldownByName(name) end
    if not cd then cd,start = Roids.GetContainerItemCooldownByName(name) end
    -- if not cd then cd = 0 end
    if not cd then return false end -- TODO: no item, not quite sure what to do here

    -- ignore the gcd if possible?
    -- if cd == 1.5 then return false end
    -- if limit == 2 and cd == amount then
    --     return true
    -- elseif limit == 1 and start ~= 0 then
    if limit == 1 and start ~= 0 then
        return (start + cd - GetTime()) >= amount
    elseif limit == 0 then
        return (start + cd - GetTime()) <= amount
    elseif limit == nil then
        return cd > 0
    end
end

function Roids.ValidatePlayerAura(aura_data,isbuff)
    if not Roids.has_superwow then
        Roids.Print("'mybuff/mydebuff' conditional requires SuperWoW")
        return
    end
    local limit,amount
    local name = aura_data
    local isTimeCheck = nil
    if type(aura_data) == "table" then
        limit = aura_data.bigger
        -- time check
        timeAmount = tonumber(aura_data.amount)
        -- stack check
        _,_,stackAmount = string.find(aura_data.amount,"^#(%d+)")
        if not timeAmount and not stackAmount then
            Roids.Print("invalid stack/time amount argument!")
        end
        if timeAmount then
            isTimeCheck = 1
            amount = timeAmount
        else
            isTimeCheck = nil
            amount = tonumber(stackAmount)
        end
        name = aura_data.name
    end
    name = string.gsub(name, "_", " ")

    local rem,stack_count,i = 0,0,1
    while true do
        local stacks, aura_id = getAura("player", i, isbuff)
        if not aura_id then break end  -- End of buffs/debuffs list
        if aura_id < -1 then aura_id = aura_id + 65536 end
        if name == SpellInfo(aura_id) then
            stack_count = stacks or 1
            if isTimeCheck then
                local aura_ix = -1
                local i2 = 0
                while true do
                    aura_ix = GetPlayerBuff(i2,isbuff and "HELPFUL|PASSIVE" or "HARMFUL")
                    if aura_ix == -1 then break end
                    local bid = GetPlayerBuffID(aura_ix)
                    if bid < -1 then bid = bid + 65536 end
                    if aura_id == bid then
                        rem = GetPlayerBuffTimeLeft(aura_ix)
                        break
                    end
                    i2 = i2 + 1
                end
            end
            break
        end
        i = i + 1
    end

    local data = 0
    if isTimeCheck then
        data = rem
    else
        data = stack_count
    end

    if limit == 1 then
        return data > amount
    elseif limit == 0 then
        return data < amount
    else
        return data ~= 0
    end
end

-- Returns the cooldown of the given spellName or nil if no such spell was found
function Roids.GetSpellCooldownByName(spellName)
    -- 1) Try the cached location first
    local cache = spell_cache[spellName]
    if cache then
        -- check to see if cache is accurate
        local name = GetSpellName(cache.index, cache.bookType)
        if name == spellName then
            local start, duration = GetSpellCooldown(cache.index, cache.bookType)
            return duration, start
        end
    end

    -- 2) Fallback scan function
    local function scanBook(bookType)
        local i = 1
        while true do
            local name, rank = GetSpellName(i, bookType)
            if not name then break end
            if name == spellName then
                local start, duration = GetSpellCooldown(i, bookType)
                -- cache for next time
                spell_cache[spellName] = { bookType = bookType, index = i }
                return duration, start
            end
            i = i + 1
        end
        return nil
    end

    -- 3) Scan pet book then player book
    local duration, start = scanBook(BOOKTYPE_PET)
    if not duration then
        duration, start = scanBook(BOOKTYPE_SPELL)
    end

    return duration, start
end

-- Returns the cooldown of the given equipped itemName or nil if no such item was found
function Roids.GetInventoryCooldownByName(itemName)
    local function CheckItem(slot)
        local slotLink = GetInventoryItemLink("player",slot)
        if not slotLink then return nil end
        local _,_,itemId = string.find(slotLink,"item:(%d+)")
        local name,_link,_,_lvl,_type,subtype = GetItemInfo(itemId)
        if itemName == itemId or name == itemName then
            local start, duration = GetInventoryItemCooldown("player", slot);
            return duration,start
        end
    end

    if item_cache[itemName] and item_cache[itemName].bag == -1 then
        local duration,start = CheckItem(item_cache[itemName].slot)
        if duration then
            return duration,start
        end
    end

    for i = 0, 19 do
        local duration,start = CheckItem(i)
        if duration then
            item_cache[itemName] = { bag = -1, slot = i }
            return duration,start
        end
    end
    return nil
end

-- TODO, this should not check for new cache hits unless a bag_update event has fired since last scan
-- Returns the cooldown of the given itemName in the player's bags or nil if no such item was found
function Roids.GetContainerItemCooldownByName(itemName)
    local function CheckItem(bag,slot)
        local slotLink = GetContainerItemLink(bag,slot)
        if not slotLink then return nil end
        local _,_,itemId = string.find(slotLink,"item:(%d+)")
        local name,_link,_,_lvl,_type,subtype = GetItemInfo(itemId)
        if itemName == itemId or name == itemName then
            local start, duration = GetContainerItemCooldown(bag, slot);
            return duration, start
        end
    end

    if item_cache[itemName] then
        local duration,start = CheckItem(item_cache[itemName].bag, item_cache[itemName].slot)
        if duration then
            return duration,start
        end
    end

    for i = 0, 4 do
        for j = 1, GetContainerNumSlots(i) do
            local duration,start = CheckItem(i,j)
            if duration then
                item_cache[itemName] = { bag = i, slot = j }
                return duration,start
            end
        end
    end
    return nil
end

local function And(t,func)
    for k,v in pairs(t) do
        if not func(v) then
            return false
        end
    end
    return true
end

local function Or(t,func)
    for k,v in pairs(t) do
        if func(v) then
            return true
        end
    end
    return false
end

-- TODO check raptor strike and mongoose for 1.17.2
Roids.reactives = {
    ROGUE = {
        ["interface\\icons\\ability_warrior_challange"] = "riposte", -- rogue
        ["interface\\icons\\ability_rogue_surpriseattack"] = "surprise_attack", -- rogue
    },
    WARRIOR = {
        ["interface\\icons\\ability_warrior_revenge"] = "revenge",
        ["interface\\icons\\ability_meleedamage"] = "overpower", -- war
        ["interface\\icons\\ability_warrior_riposte"] = "counterattack", -- twow 1.17.2 war
    },
    HUNTER = {
        ["interface\\icons\\ability_warrior_challange"] = "counterattack", -- hunter
        ["interface\\icons\\ability_hunter_swiftstrike"] = "mongoose_bite", -- hunter
    },
    MAGE = {
        ["interface\\icons\\inv_enchant_essencemysticallarge"] = "arcane_surge",
    },
}

-- store found reactive id's, why scan every slot every press
Roids.live_reactives = {}
function Roids.CheckReactiveAbility(spellName)
    local _,class = UnitClass("player")
    spellName = string.lower(spellName)
    local function CheckAction(tex,spellName,actionSlot)
        if tex and spellName and actionSlot then
            tex = string.lower(tex)
            for rspell_texture,rspellName in pairs(Roids.reactives[class]) do
                if rspell_texture == tex and rspellName == spellName then
                    local isUsable = IsUsableAction(actionSlot)
                    local start, duration = GetActionCooldown(actionSlot)
                    if isUsable and (start == 0 or duration == 1.5) then -- 1.5 just means gcd is active
                        return true,true
                    else
                        return false,true
                    end
                end
            end
        end
        return false,false
    end

    -- check if we've search already
    if Roids.live_reactives[spellName] ~= -1 then
        -- check if we cached it
        if Roids.live_reactives[spellName] then
            local tex = GetActionTexture(Roids.live_reactives[spellName])
            local r,was_hit = CheckAction(tex,spellName,Roids.live_reactives[spellName])
            if was_hit then
                -- print(tostring(r).."1 "..spellName)
                return r
            end
        end
        -- search for it
        for actionSlot = 1, 120 do
            local tex = GetActionTexture(actionSlot)
            if tex and not GetActionText(actionSlot) then
                local r,was_hit = CheckAction(tex,spellName,actionSlot)
                if was_hit then
                    Roids.live_reactives[spellName] = actionSlot
                    -- print(tostring(r).."2 "..spellName)
                    return r
                end
            end
            -- wasn't on bars, ignore the reactive until action bars change
        end
        Roids.live_reactives[spellName] = -1
        Roids.Print(spellName .. " not found on action bars, or isn't an implemented reactive.")
    -- else
        -- print(spellName.." is -1")
    end
    return false
end

function Roids.CheckSpellCast(spell,unit)
    if not Roids.has_superwow then
        Roids.Print("'casting' conditional requires SuperWoW")
        return
    end
    local spell = string.gsub(spell or "", "_", " ");
    local _,guid = UnitExists(unit)
    if not guid or (guid and not Roids.spell_tracking[guid]) then
        return false
    else
        -- are we casting a specific spell, or any spell
        if spell == SpellInfo(Roids.spell_tracking[guid].spell_id) or (spell == "") then
            return true
        end
        return false
    end
end

-- Checks whether or not the distance between player and the current target is less than spell max range
-- actionSlot: the action slot number of the spell
-- returns: True or false
-- check https://wowwiki-archive.fandom.com/wiki/API_IsActionInRange
function Roids.CheckActionInrange(actionSlot)
    local ret = IsActionInRange(actionSlot)
    if ret == 0 then
        return false
    elseif ret == 1 then
        return true
    else
        return false
    end
end

-- A list of Conditionals and their functions to validate them
Roids.Keywords = {
    help = function(conditionals)
        return true;
    end,

    harm = function(conditionals)
        return true;
    end,
    
    stance = function(conditionals)
        return And(conditionals.stance,function (stances)
            return Or(Roids.splitString(stances, "/"), function (v)
                return (Roids.GetCurrentShapeshiftIndex() == tonumber(v))
            end)
        end)
    end,

    mod = function(conditionals)
        for _,mods in pairs(conditionals.mod) do
            for k,v in pairs(Roids.splitString(mods, "/")) do
                if v == "alt" and IsAltKeyDown() then
                    return true
                elseif v == "ctrl" and IsControlKeyDown() then
                    return true
                elseif v == "shift" and IsShiftKeyDown() then
                    return true
                end
            end
        end
        return false
    end,

    target = function(conditionals)
        return Roids.IsValidTarget(conditionals.target, conditionals.help);
    end,

    combat = function(conditionals)
        return UnitAffectingCombat("player");
    end,

    nocombat = function(conditionals)
        return not UnitAffectingCombat("player");
    end,

    stealth = function(conditionals)
        return And(conditionals.stealth,function (v)
            return Roids.ValidatePlayerAura("stealth",true) or Roids.ValidatePlayerAura("prowl",true)
        end)
    end,

    nostealth = function(conditionals)
        return And(conditionals.stealth,function (v)
            return not (Roids.ValidatePlayerAura("stealth",true) or Roids.ValidatePlayerAura("prowl",true))
        end)
    end,

    casting = function(conditionals)
        return And(conditionals.casting,function (spells)
            if spells == "" then return Roids.CheckSpellCast("",conditionals.target) end
            return Or(Roids.splitString(spells, "/"), function (spell)
                return Roids.CheckSpellCast(spell,conditionals.target)
            end)
        end)
        -- return And(conditionals.casting,function (v) return Roids.CheckSpellCast(v,conditionals.target) end)
    end,

    nocasting = function(conditionals)
        -- nocasting with options needs all of them to not be true, e.g. AND not OR
        return And(conditionals.nocasting,function (spells)
            if spells == "" then return not Roids.CheckSpellCast("",conditionals.target) end
            return And(Roids.splitString(spells, "/"), function (spell)
                return not Roids.CheckSpellCast(spell,conditionals.target)
            end)
        end)
        -- return Or(conditionals.nocasting,function (v) return not Roids.CheckSpellCast(v,conditionals.target) end)
    end,

    zone = function(conditionals)
        local zone = string.lower(GetRealZoneText())
        local sub_zone = string.lower(GetSubZoneText())
        return And(conditionals.zone,function (zones)
            return Or(Roids.splitString(zones, "/"), function (v)
                v = string.gsub(v, "_", " ")
                return (sub_zone ~= "" and (string.lower(v) == sub_zone) or (string.lower(v) == zone))
            end)
        end)
    end,

    nozone = function(conditionals)
        local zone = string.lower(GetRealZoneText())
        local sub_zone = string.lower(GetSubZoneText())
        -- nozone with options needs all of them to not be true, e.g. AND not OR
        return And(conditionals.nozone,function (zones)
            return And(Roids.splitString(zones, "/"), function (v)
                v = string.gsub(v, "_", " ")
                return not ((sub_zone ~= "" and (string.lower(v) == sub_zone)) or (string.lower(v) == zone))
            end)
        end)

    end,

    equipped = function(conditionals)
        return And(conditionals.equipped,function (equips)
            return Or(Roids.splitString(equips, "/"), function (v)
                v = string.gsub(v, "_", " ")
                return (Roids.HasWeaponEquipped(v) or Roids.HasGearEquipped(v))
            end)
        end)
    end,

    -- double And, all must not be true
    noequipped = function(conditionals)
        return And(conditionals.noequipped,function (equips)
            return And(Roids.splitString(equips, "/"), function (v)
                v = string.gsub(v, "_", " ")
                return not (Roids.HasWeaponEquipped(v) or Roids.HasGearEquipped(v))
            end)
        end)
    end,

    reactive = function(conditionals)
        return And(conditionals.reactive,function (v)
            return Roids.CheckReactiveAbility(v)
        end)
    end,

    noreactive = function(conditionals)
        return And(conditionals.noreactive,function (v)
            return not Roids.CheckReactiveAbility(v)
        end)
    end,

    dead = function(conditionals)
        return UnitIsDeadOrGhost(conditionals.target);
    end,

    nodead = function(conditionals)
        return not UnitIsDeadOrGhost(conditionals.target);
    end,

    party = function(conditionals)
        return Roids.IsTargetInGroupType(conditionals.target, "party");
    end,

    raid = function(conditionals)
        return Roids.IsTargetInGroupType(conditionals.target, "raid");
    end,

    group = function(conditionals)
        return And(conditionals.group,function (v)
            if v == "party" then
                return GetNumPartyMembers() > 0 and GetNumRaidMembers() == 0
            elseif v == "raid" then
                return GetNumRaidMembers() > 0
            end
            return false;
        end)
    end,

    checkchanneled = function(conditionals)
        return Roids.CheckChanneled(conditionals);
    end,

    buff = function(conditionals)
        return And(conditionals.buff,function (v) return Roids.ValidateAura(v, true, conditionals.target) end)
    end,

    nobuff = function(conditionals)
        return And(conditionals.nobuff,function (v) return not Roids.ValidateAura(v, true, conditionals.target) end)
    end,

    debuff = function(conditionals)
        return And(conditionals.debuff,function (v) return Roids.ValidateAura(v, false, conditionals.target) end)
    end,

    nodebuff = function(conditionals)
        return And(conditionals.nodebuff,function (v) return not Roids.ValidateAura(v, false, conditionals.target) end)
    end,

    mybuff = function(conditionals)
        return And(conditionals.mybuff,function (v) return Roids.ValidatePlayerAura(v,true) end)
    end,

    nomybuff = function(conditionals)
        return And(conditionals.nomybuff,function (v) return not Roids.ValidatePlayerAura(v,true) end)
    end,

    mydebuff = function(conditionals)
        return And(conditionals.mydebuff,function (v) return Roids.ValidatePlayerAura(v,false) end)
    end,

    nomydebuff = function(conditionals)
        return And(conditionals.nomydebuff,function (v) return not Roids.ValidatePlayerAura(v,false) end)
    end,
        
    combo = function(conditionals)
        return And(conditionals.combo,function (v) return Roids.ValidateCombo(v.bigger, v.amount) end)
    end,

    power = function(conditionals)
        return And(conditionals.power,function (v) return Roids.ValidatePower(conditionals.target, v.bigger, v.amount) end)
    end,
    
    mypower = function(conditionals)
        return And(conditionals.mypower,function (v) return Roids.ValidatePower("player", v.bigger, v.amount) end)
    end,
    
    rawpower = function(conditionals)
        return And(conditionals.rawpower,function (v) return Roids.ValidateRawPower(conditionals.target, v.bigger, v.amount) end)
    end,
    
    myrawpower = function(conditionals)
        return And(conditionals.myrawpower,function (v) return Roids.ValidateRawPower("player", v.bigger, v.amount) end)
    end,
    
    hp = function(conditionals)
        return And(conditionals.hp,function (v) return Roids.ValidateHp(conditionals.target, v.bigger, v.amount) end)
    end,
    
    myhp = function(conditionals)
        return And(conditionals.myhp,function (v) return Roids.ValidateHp("player", v.bigger, v.amount) end)
    end,
    
    type = function(conditionals)
        return And(conditionals.type, function (types)
            return Or(Roids.splitString(types, "/"), function (v)
                return Roids.ValidateCreatureType(v, conditionals.target)
            end)
        end)
    end,

    cooldown = function(conditionals)
        return And(conditionals.cooldown,function (v) return Roids.ValidateCooldown(v) end)
    end,
    
    nocooldown = function(conditionals)
        return And(conditionals.nocooldown,function (v) return not Roids.ValidateCooldown(v) end)
    end,
    
    channeled = function(conditionals)
        return Roids.CurrentSpell.type == "channeled";
    end,
    
    nochanneled = function(conditionals)
        return Roids.CurrentSpell.type ~= "channeled"
        -- return Roids.CurrentSpell.spellName == "";
    end,
    
    attacks = function(conditionals)
        return And(conditionals.attacks,function (v) return UnitIsUnit("targettarget", v) end)
    end,
    
    noattacks = function(conditionals)
        return And(conditionals.noattacks,function (v) return not UnitIsUnit("targettarget", v) end)
    end,
    
    isplayer = function(conditionals)
        return And(conditionals.isplayer,function (v) return UnitIsPlayer(v) end)
    end,
    
    isnpc = function(conditionals)
        return And(conditionals.isnpc,function (v) return not UnitIsPlayer(v) end)
    end,

    hasPet = function(conditionals)
        return HasPetUI();
    end,

    -- TODO update to spellName version, need to implement spell name -> action slot number(same in [reactive])
    inRange = function(conditionals)
        return And(conditionals.inRange,function (v) return Roids.CheckActionInrange(v) end)
    end,
    outRange = function(conditionals)
        return And(conditionals.outRange,function (v) return not Roids.CheckActionInrange(v) end)
    end,
};
