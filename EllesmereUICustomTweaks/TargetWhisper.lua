-------------------------------------------------------------------------------
-- /tt: whisper the currently targeted player.
--
-- Typing the space after /tt resolves the target into Blizzard's native
-- addressed-whisper state.  A pasted command can still send immediately, and
-- an empty submitted command opens the chat edit box with the recipient filled
-- in.  The target name is read only at command time, and protected/secret unit
-- data is never passed into chat APIs.
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

-------------------------------------------------------------------------------
-- Native whisper resolution
--
-- Blizzard's edit box parses chat-type prefixes from OnTextChanged.  Do not
-- hook that script: it also runs from secure chat-state transitions, and addon
-- code there can taint the attributes used by later messages.  OnChar is the
-- physical typing path.  Once the player types the first space after /tt, put
-- the equivalent native /w line into the box; Blizzard immediately consumes
-- it, sets WHISPER/tellTarget, and displays its normal "To <name>:" header.
-------------------------------------------------------------------------------
local hookedEditBoxes = setmetatable({}, { __mode = "k" })

local function PermanentChatEditBox(editBox)
    if not editBox or type(editBox.GetName) ~= "function" then return false end
    local frameIndex = tonumber((editBox:GetName() or ""):match("^ChatFrame(%d+)EditBox$"))
    return frameIndex ~= nil and frameIndex <= 10
end

local function MessagingIsRestricted()
    if GetCVarBool and GetCVarBool("addonChatRestrictionsForced") then
        return true
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, restricted = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and restricted then return true end
    end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and active then return true end
    end
    return false
end

local function ResolveTypedTargetWhisper(editBox)
    if ns.Get("targetWhisperCommand") ~= true then return end
    if not PermanentChatEditBox(editBox) then return end

    local text = editBox:GetText()
    if type(text) ~= "string" or IsSecret(text) then return end
    if text:lower() ~= "/tt " then return end

    local name, reason = TargetPlayerName()
    if not name then
        ErrorMessage(reason)
        editBox:SetText("/tt")
        return
    end

    -- Programmatically supplied edit-box text is addon-owned.  It works for
    -- ordinary chat, but Blizzard deliberately rejects it during messaging
    -- lockdowns, so fail clearly instead of creating a whisper that cannot send.
    if MessagingIsRestricted() then
        ErrorMessage("/tt name resolution is unavailable during restricted chat.")
        editBox:SetText("/tt")
        return
    end

    editBox:SetText((SLASH_WHISPER1 or "/w") .. " " .. name .. " ")
end

local function HookTargetWhisperEditBoxes()
    local count = tonumber(NUM_CHAT_WINDOWS) or 10
    for index = 1, math.min(count, 10) do
        local editBox = _G["ChatFrame" .. index .. "EditBox"]
        if editBox and not hookedEditBoxes[editBox] then
            hookedEditBoxes[editBox] = true
            editBox:HookScript("OnChar", ResolveTypedTargetWhisper)
        end
    end
end

HookTargetWhisperEditBoxes()

local editBoxWatcher = CreateFrame("Frame")
editBoxWatcher:RegisterEvent("PLAYER_LOGIN")
editBoxWatcher:RegisterEvent("UPDATE_CHAT_WINDOWS")
editBoxWatcher:SetScript("OnEvent", HookTargetWhisperEditBoxes)

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
