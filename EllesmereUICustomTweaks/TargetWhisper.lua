-------------------------------------------------------------------------------
-- /tt: whisper the currently targeted player.
--
-- A message sends immediately; an empty command opens the chat edit box with
-- the recipient filled in.  The target name is read only at command time, and
-- protected/secret unit data is never passed into chat APIs.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = _G.EllesmereUI

local COMMAND_KEY = "ELLESMERECUSTOMTARGETWHISPER"

local function IsSecret(value)
    return _G.issecretvalue and issecretvalue(value)
end

local function ErrorMessage(message)
    if EUI and EUI.PrintError then
        EUI.PrintError(message)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Custom Tweaks:|r " .. message)
    end
end

local function TargetPlayerName()
    local exists = UnitExists and UnitExists("target")
    if IsSecret(exists) then
        return nil, "The target's identity is protected right now."
    end
    if not exists then return nil, "You do not have a target." end

    local player = UnitIsPlayer and UnitIsPlayer("target")
    if IsSecret(player) then
        return nil, "The target's identity is protected right now."
    end
    if not player then return nil, "Your target is not a player." end

    local name, realm
    if UnitFullName then name, realm = UnitFullName("target") end
    if not name and UnitName then name, realm = UnitName("target") end
    if IsSecret(name) or IsSecret(realm) then
        return nil, "The target's name is protected right now."
    end
    if type(name) ~= "string" or name == "" then
        return nil, "The targeted player's name is unavailable."
    end
    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function Trim(message)
    message = type(message) == "string" and message or ""
    if strtrim then return strtrim(message) end
    return message:match("^%s*(.-)%s*$") or ""
end

local function OpenWhisper(name)
    if not ChatFrame_OpenChat then
        ErrorMessage("The chat input is unavailable.")
        return
    end
    ChatFrame_OpenChat((SLASH_WHISPER1 or "/w") .. " " .. name .. " ")
end

_G["SLASH_" .. COMMAND_KEY .. "1"] = "/tt"
SlashCmdList[COMMAND_KEY] = function(message)
    if ns.Get("targetWhisperCommand") ~= true then
        ErrorMessage("/tt is disabled in Custom Tweaks.")
        return
    end

    local name, reason = TargetPlayerName()
    if not name then
        ErrorMessage(reason)
        return
    end

    message = Trim(message)
    if message == "" then
        OpenWhisper(name)
        return
    end

    if type(SendChatMessage) ~= "function" then
        ErrorMessage("Whisper sending is unavailable.")
        return
    end
    local ok = pcall(SendChatMessage, message, "WHISPER", nil, name)
    if not ok then ErrorMessage("The whisper could not be sent right now.") end
end
