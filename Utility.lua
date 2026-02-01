--[[
	Author: Dennis Werner Garske (DWG)
	License: MIT License
]]
local _G = _G or getfenv(0)
local Roids = _G.Roids or {} -- redundant since we're loading first but peace of mind if another file is added top of chain

-- Speedy references to string library
local strfind = string.find
local strsub = string.sub
local strlen = string.len
local strgsub = string.gsub
local strlower = string.lower

-- Caches for string operations
local split_cache = {}
local split_sep_cache = {}
local underscore_cache = {}
local lower_cache = {}

-- Shallow copy an array (for cached split results)
local function shallow_copy_array(arr)
    local copy = {}
    for i, v in ipairs(arr) do
        copy[i] = v
    end
    return copy
end

-- Trims any leading or trailing white space characters from the given string
-- str: The string to trim
-- returns: The trimmed string
local function Trim(str)
    if not str then
        return nil;
    end
    return strgsub(str,"^%s*(.-)%s*$", "%1");
end

-- Splits the given string into a list of sub-strings (inner, uncached)
-- str: The string to split
-- seperatorPattern: The seperator between sub-string. May contain patterns
-- returns: A list of sub-strings
local function splitStringInner(str, seperatorPattern)
    local tbl = {};
    if not str then
        return tbl;
    end
    local pattern = "(.-)" .. seperatorPattern;
    local lastEnd = 1;
    local s, e, cap = strfind(str, pattern, 1);

    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(tbl,cap);
        end
        lastEnd = e + 1;
        s, e, cap = strfind(str, pattern, lastEnd);
    end

    if lastEnd <= strlen(str) then
        cap = strsub(str, lastEnd);
        table.insert(tbl, cap);
    end

    return tbl
end

-- Cached wrapper for splitString
local function splitString(str, seperatorPattern)
    local key = str .. "\0" .. seperatorPattern
    local cached = split_sep_cache[key]
    if cached then
        return shallow_copy_array(cached)
    end

    local result = splitStringInner(str, seperatorPattern)
    split_sep_cache[key] = result
    return shallow_copy_array(result)
end

-- Splits by semicolon ignoring quoted strings (inner, uncached)
local function splitStringIgnoringQuotesInner(str)
    local result = {}
    local temp = ""
    local insideQuotes = false

    for i = 1, strlen(str) do
        local char = strsub(str, i, i)

        if char == "\"" then
            insideQuotes = not insideQuotes
            temp = temp .. char
        elseif char == ";" and not insideQuotes then
            temp = Trim(temp)
            table.insert(result, temp)
            temp = ""
        else
            temp = temp .. char
        end
    end

    -- Add the last segment if it exists
    if temp ~= "" then
        temp = Trim(temp)
        table.insert(result, temp)
    end

    -- if nothing was found, return the empty string
    return (next(result) and result or {""})
end

-- Cached wrapper for splitStringIgnoringQuotes
local function splitStringIgnoringQuotes(str)
    local cached = split_cache[str]
    if cached then
        return shallow_copy_array(cached)
    end

    local result = splitStringIgnoringQuotesInner(str)
    split_cache[str] = result
    return shallow_copy_array(result)
end

-- Replaces underscores with spaces (cached)
local function UnderscoreToSpace(str)
    if not str then return str end

    local cached = underscore_cache[str]
    if cached then
        return cached
    end

    local result = strgsub(str, "_", " ")
    underscore_cache[str] = result
    return result
end

-- Converts string to lowercase (cached)
local function ToLower(str)
    if not str then return str end

    local cached = lower_cache[str]
    if cached then
        return cached
    end

    local result = strlower(str)
    lower_cache[str] = result
    return result
end

-- Prints all the given arguments into WoW's default chat frame
local function Print(...)
    if not DEFAULT_CHAT_FRAME:IsVisible() then
        FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
    end
    local out = "|cffc8c864Roids:|r";

    for i=1, arg.n, 1 do
        out = out..tostring(arg[i]).."  ";
    end

    DEFAULT_CHAT_FRAME:AddMessage(out)
end

-- Export all functions to Roids table for external use
Roids.Trim = Trim
Roids.splitString = splitString
Roids.splitStringIgnoringQuotes = splitStringIgnoringQuotes
Roids.UnderscoreToSpace = UnderscoreToSpace
Roids.ToLower = ToLower
Roids.Print = Print

_G["Roids"] = Roids
