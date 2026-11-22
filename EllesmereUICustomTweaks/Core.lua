-------------------------------------------------------------------------------
-- EllesmereUI Custom Tweaks
-- Update-safe personal refinements layered over EllesmereUI without changing
-- any of the suite's files.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

EUI._ModuleNS[ADDON_NAME] = ns

local DEFAULTS = {
    hideFlightYou = true,
    fixedFlightPoints = true,
    smartFlightExit = true,
    hideBlizzardFlightExit = true,
    learnFlightTimes = true,
    fadeChatLines = true,
    chatLineSeconds = 45,
    chatFadeDuration = 3,
    autoHideTabs = true,
    tabSeconds = 45,
    hideCollapseButtons = true,
    channelInputBorder = true,
    inputBorderColorMode = "channel",
    inputBorderColor = { r = 1, g = 1, b = 1, a = 1 },
    inputBorderStep = 1,
    inputBorderSizePx = false,
    showPlayerOnMissingHealth = true,
    showPlayerOnMissingMana = true,
    showPlayerWhileEating = true,
    showPlayerWhileChanneling = true,
    useCraftedItemIcon = true,
    questTimerFullWidth = true,
    questTimerEmptyColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
    alwaysGatheringTracking = true,
    auraDurationBars = true,
    auraDurationFilters = {},
    auraDurationSpellIDs = {},
    auraDurationBarWidth = 240,
    auraDurationBarHeight = 20,
    auraDurationBarSpacing = 3,
    auraDurationBarMax = 8,
    auraDurationBarOffsetX = 0,
    auraDurationBarOffsetY = 8,
    auraDurationBarTexture = "gradient-lr",
    auraDurationBarColorMode = "accent",
    auraDurationBarColor = { r = 0.05, g = 0.75, b = 0.58, a = 1 },
    auraDurationBarShowIcon = true,
    auraDurationBarShowStacks = true,
    durableLootSession = true,
    lootSessionTimeoutHours = 8,
}
ns.DEFAULTS = DEFAULTS

local function DB()
    local db = _G.EllesmereUICustomTweaksDB
    if type(db) ~= "table" then
        db = {}
        _G.EllesmereUICustomTweaksDB = db
    end
    return db
end

function ns.Get(key)
    local value = DB()[key]
    if value == nil then return DEFAULTS[key] end
    return value
end

local function IsSecret(value)
    return _G.issecretvalue and _G.issecretvalue(value)
end

local driver
local lineGeneration = 0
local lineStates = setmetatable({}, { __mode = "k" })
local floatGhosts = setmetatable({}, { __mode = "k" })
local inputBorders = setmetatable({}, { __mode = "k" })
local tabsLastInteraction = 0
local tabsInteracting = false
local tabsShown = true
local chromeElapsed = 0

-------------------------------------------------------------------------------
-- Gathering minimap tracking. WoW Forever exposes Find Herbs and Find
-- Minerals as spell-backed minimap trackers. Keep the last gathering tracker
-- used by each character selected; if none has been chosen yet, prefer the
-- first one the character knows. Class tracking remains untouched unless it
-- replaces the enforced gathering tracker.
-------------------------------------------------------------------------------
local GATHERING_TRACKERS = { 2383, 2580 } -- Find Herbs, Find Minerals
local gatheringEvents
local gatheringTimer
local gatheringLastAttempt = 0

local function GatheringSpellKnown(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID) == true
    end
    if IsPlayerSpell then return IsPlayerSpell(spellID) == true end
    return IsSpellKnown and IsSpellKnown(spellID) == true or false
end

local function GatheringCharacterKey()
    local guid = UnitGUID("player")
    if type(guid) == "string" and not IsSecret(guid) then return guid end
end

local function GatheringChoices()
    local db = DB()
    if type(db.gatheringTrackingByCharacter) ~= "table" then
        db.gatheringTrackingByCharacter = {}
    end
    return db.gatheringTrackingByCharacter
end

local function RememberGatheringTracker(spellID)
    local key = GatheringCharacterKey()
    if key then GatheringChoices()[key] = spellID end
end

-- Returns the active gathering spell and its minimap index. The index is also
-- needed to restore a spell through Blizzard's tracking API.
local function ActiveGatheringTracker()
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return end
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(index)
        if info and info.type == "spell" then
            for i = 1, #GATHERING_TRACKERS do
                if info.spellID == GATHERING_TRACKERS[i] then
                    if info.active then return info.spellID, index end
                end
            end
        end
    end
end

local function DesiredGatheringTracker()
    local key = GatheringCharacterKey()
    local saved = key and GatheringChoices()[key]
    if saved and GatheringSpellKnown(saved) then return saved end
    for i = 1, #GATHERING_TRACKERS do
        local spellID = GATHERING_TRACKERS[i]
        if GatheringSpellKnown(spellID) then return spellID end
    end
end

local function RestoreGatheringTracker()
    gatheringTimer = nil
    if not ns.Get("alwaysGatheringTracking") or not EUI.IS_FOREVER then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end

    local active = ActiveGatheringTracker()
    if active then
        RememberGatheringTracker(active)
        return
    end

    local desired = DesiredGatheringTracker()
    if not desired then return end
    local setter = C_Minimap and C_Minimap.SetTracking
    if not setter then return end

    local now = GetTime()
    if now - gatheringLastAttempt < 0.75 then return end
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(index)
        if info and info.spellID == desired then
            gatheringLastAttempt = now
            pcall(setter, index, true)
            return
        end
    end
end

local function QueueGatheringRestore(delay)
    if gatheringTimer then gatheringTimer:Cancel() end
    gatheringTimer = C_Timer.NewTimer(delay or 0.20, RestoreGatheringTracker)
end

local function SyncGatheringTrackingEvents()
    if not gatheringEvents then
        gatheringEvents = CreateFrame("Frame")
        gatheringEvents:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_AURA" and unit ~= "player" then return end
            QueueGatheringRestore(event == "PLAYER_ENTERING_WORLD" and 1 or 0.20)
        end)
    end

    gatheringEvents:UnregisterAllEvents()
    if gatheringTimer then gatheringTimer:Cancel(); gatheringTimer = nil end
    if not ns.Get("alwaysGatheringTracking") or not EUI.IS_FOREVER then return end

    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
        "PLAYER_REGEN_ENABLED", "MINIMAP_UPDATE_TRACKING",
        "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED",
    }) do
        gatheringEvents:RegisterEvent(event)
    end
    gatheringEvents:RegisterUnitEvent("UNIT_AURA", "player")
    QueueGatheringRestore(0)
end

-------------------------------------------------------------------------------
-- Player unit-frame conditional reveals. Ellesmere keeps visibility on a
-- non-secure alpha wrapper, but group/driver modes may still secure-hide the
-- underlying frame. Extending HealthVisibilityEnabled keeps the player frame
-- available at secure level whenever any reveal rule is configured; the
-- ResolveVisResting wrapper then supplies full alpha only while a rule matches.
-------------------------------------------------------------------------------
local playerRevealHooked = false
local playerRevealPending = false
local playerRevealEvents
local playerRevealResource = "health"
local playerRevealVisState = {}

local PLAYER_REGEN_AURAS = {}
for _, spellID in ipairs({
    430, 431, 432, 433, 434, 435, 1127, 1129, 1131, 1133, 1135, 1137,
    2639, 5004, 5006, 5007, 6410, 7737, 10256, 22734, 24005, 24355,
    24707, 24869, 25660, 29007, 29008, 29073, 468767, 470362, 470369,
    1225769, 1225771, 1225772,
}) do
    PLAYER_REGEN_AURAS[spellID] = true
end

local function UnitFramesNS()
    return EUI._ModuleNS and EUI._ModuleNS["EllesmereUIUnitFrames"]
end

local function AnyPlayerRevealEnabled()
    return ns.Get("showPlayerOnMissingHealth")
        or ns.Get("showPlayerOnMissingMana")
        or ns.Get("showPlayerWhileEating")
        or ns.Get("showPlayerWhileChanneling")
end

local function MissingResourceState(current, maximum)
    if IsSecret(current) or IsSecret(maximum) then return nil end
    if type(current) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
        return false
    end
    return current < maximum
end

local function PlayerHasRegenAura()
    -- Food and drink effects cannot be used in combat. Aura data can become a
    -- protected secret there, so do not query it from tainted addon code.
    if _G.InCombatLockdown and InCombatLockdown() then return false end

    if _G.C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for index = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
            if not aura then break end
            if PLAYER_REGEN_AURAS[aura.spellId or aura.spellID] then return true end
        end
    elseif _G.UnitAura then
        for index = 1, 40 do
            local name, _, _, _, _, _, _, _, _, spellID = UnitAura("player", index, "HELPFUL")
            if not name then break end
            if PLAYER_REGEN_AURAS[spellID] then return true end
        end
    end
    return false
end

local function ResourceRevealCurve(frame, resource, baseAlpha)
    local curveKey = resource == "health"
        and "_euiCustomHealthRevealCurve" or "_euiCustomManaRevealCurve"
    local alphaKey = resource == "health"
        and "_euiCustomHealthRevealBase" or "_euiCustomManaRevealBase"
    local curve = frame[curveKey]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Step)
        frame[curveKey] = curve
    end
    if frame[alphaKey] ~= baseAlpha then
        curve:ClearPoints()
        curve:AddPoint(0, 1)
        curve:AddPoint(1, baseAlpha)
        frame[alphaKey] = baseAlpha
    end
    return curve
end

-- Return the alpha for the custom reveal, preserving Ellesmere's normal alpha
-- when no rule matches. Health and power values become protected secrets in
-- combat on modern clients, so a secret value is never used as a Lua condition.
-- A single protected resource can use Blizzard's curve API exactly. When both
-- are protected, combat stays visible (the requested safe behavior); outside
-- combat, the resource whose event triggered the refresh supplies the curve.
local function PlayerRevealAlpha(frame, baseAlpha, inCombat)
    -- Taxi flight protects player health and power even out of combat. Feeding
    -- those secret values through the reveal curves can leave a full-resource
    -- frame visibly latched for the entire trip. A taxi cannot be interrupted
    -- to eat, cast, or spend resources, so let native visibility own it.
    if _G.UnitOnTaxi and UnitOnTaxi("player") then return baseAlpha end

    if ns.Get("showPlayerWhileEating") and PlayerHasRegenAura() then return 1 end
    if ns.Get("showPlayerWhileChanneling") and UnitChannelInfo("player") then
        return 1
    end

    local healthEnabled = ns.Get("showPlayerOnMissingHealth")
    local manaEnabled = ns.Get("showPlayerOnMissingMana")
    local mana = _G.Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    local healthMissing
    local manaMissing

    if healthEnabled then
        healthMissing = MissingResourceState(UnitHealth("player"), UnitHealthMax("player"))
        if healthMissing == true then return 1 end
    end
    if manaEnabled then
        local manaMaximum = UnitPowerMax("player", mana)
        -- Classes without a mana pool should not turn the two-resource combat
        -- fallback into an unconditional reveal.
        if not IsSecret(manaMaximum)
            and (type(manaMaximum) ~= "number" or manaMaximum <= 0) then
            manaEnabled = false
        else
            manaMissing = MissingResourceState(UnitPower("player", mana), manaMaximum)
            if manaMissing == true then return 1 end
        end
    end

    local healthProtected = healthEnabled and healthMissing == nil
    local manaProtected = manaEnabled and manaMissing == nil
    if healthProtected and manaProtected then
        if inCombat then return 1 end
        if playerRevealResource == "mana" then
            return UnitPowerPercent("player", mana, false,
                ResourceRevealCurve(frame, "mana", baseAlpha))
        end
        return UnitHealthPercent("player", false,
            ResourceRevealCurve(frame, "health", baseAlpha))
    end
    if healthProtected then
        return UnitHealthPercent("player", false,
            ResourceRevealCurve(frame, "health", baseAlpha))
    end
    if manaProtected then
        return UnitPowerPercent("player", mana, false,
            ResourceRevealCurve(frame, "mana", baseAlpha))
    end
    return baseAlpha
end

local function IsCustomRevealFrame(settings, frame)
    if not AnyPlayerRevealEnabled() or not settings or not frame then return false end
    if frame._euiUnit ~= "player" and frame ~= _G.EllesmereUIUnitFrames_Player then
        return false
    end
    local override = EUI.VisOverrideValue and EUI.VisOverrideValue(settings)
    return (override or settings.barVisibility or "always") ~= "never"
end

local function CustomRevealVetoed(settings, hiddenByOptions, inCombat)
    -- The custom conditions deliberately override ordinary visibility options
    -- such as Hide Without Target / Hide Without Enemy: "show while injured"
    -- must remain literal even when those normal-context filters are active.
    -- Visibility-mode Hide lanes are different user-authored hard stops (for
    -- example Hide Out of Combat), and remain terminal. A temporary Visibility
    -- override replaces the underlying configuration and its stored vetoes.
    local override = EUI.VisOverrideValue and EUI.VisOverrideValue(settings)
    if override then return false end

    local selection = EUI.GetActiveVisibilityModes
        and EUI.GetActiveVisibilityModes(settings, "barVisibility")
    if not (selection and EUI.VisModeHideVeto) then return false end
    local inRaid = IsInRaid()
    playerRevealVisState.inCombat = inCombat and true or false
    playerRevealVisState.inRaid = inRaid
    playerRevealVisState.inParty = not inRaid and IsInGroup()
    return EUI.VisModeHideVeto(
        selection, playerRevealVisState, EUI.VIS_CAPS_DEFAULT) and true or false
end

local function InstallPlayerRevealHooks()
    if playerRevealHooked then return true end
    local unitFrames = UnitFramesNS()
    if not (unitFrames and unitFrames.ResolveVisResting
        and unitFrames.HealthVisibilityEnabled) then return false end

    local baseResolve = unitFrames.ResolveVisResting
    local baseHealthEnabled = unitFrames.HealthVisibilityEnabled
    unitFrames.ResolveVisResting = function(settings, frame, extended, hiddenByOptions, inCombat)
        local alpha, hoverGated = baseResolve(settings, frame, extended, hiddenByOptions, inCombat)
        if IsCustomRevealFrame(settings, frame)
            and not CustomRevealVetoed(settings, hiddenByOptions, inCombat) then
            -- Custom rules supplement native Show conditions. Explicit Hide
            -- lanes and Never remain terminal. Preserve the native hover gate
            -- so a full-resource frame still responds to mouseover normally.
            return PlayerRevealAlpha(frame, alpha, inCombat), hoverGated
        end
        return alpha, hoverGated
    end
    unitFrames.HealthVisibilityEnabled = function(settings, frame)
        if baseHealthEnabled(settings, frame) then return true end
        return IsCustomRevealFrame(settings, frame)
    end
    playerRevealHooked = true
    return true
end

local function RefreshPlayerReveal()
    if not InstallPlayerRevealHooks() then return end
    local unitFrames = UnitFramesNS()
    if unitFrames and unitFrames.UpdateFrameVisibility then
        unitFrames.UpdateFrameVisibility()
    end
end

local function QueuePlayerRevealRefresh()
    if playerRevealPending then return end
    playerRevealPending = true
    C_Timer.After(0, function()
        playerRevealPending = false
        RefreshPlayerReveal()
    end)
end

local function SyncPlayerRevealEvents()
    if not playerRevealEvents then
        playerRevealEvents = CreateFrame("Frame")
        playerRevealEvents:SetScript("OnEvent", function(_, event, unit, powerToken)
            if unit and unit ~= "player" then return end
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                playerRevealResource = "health"
            elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE"
                or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
                if powerToken and powerToken ~= "MANA" then return end
                playerRevealResource = "mana"
            end
            QueuePlayerRevealRefresh()
        end)
    end

    playerRevealEvents:UnregisterAllEvents()
    if AnyPlayerRevealEnabled() then
        -- Repaint immediately when taxi protection begins or ends; resource
        -- events alone are not guaranteed at either edge of a flight path.
        playerRevealEvents:RegisterEvent("PLAYER_CONTROL_LOST")
        playerRevealEvents:RegisterEvent("PLAYER_CONTROL_GAINED")
        playerRevealEvents:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    end
    if ns.Get("showPlayerOnMissingHealth") then
        playerRevealEvents:RegisterUnitEvent("UNIT_HEALTH", "player")
        playerRevealEvents:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    end
    if ns.Get("showPlayerOnMissingMana") then
        -- UNIT_POWER_UPDATE is throttled; the frequent event is what makes an
        -- instant mana-cost spell reveal the frame on the same power change.
        playerRevealEvents:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        playerRevealEvents:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        playerRevealEvents:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        playerRevealEvents:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    end
    if ns.Get("showPlayerWhileEating") then
        playerRevealEvents:RegisterUnitEvent("UNIT_AURA", "player")
    end
    if ns.Get("showPlayerWhileChanneling") then
        for _, event in ipairs({
            "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
            "UNIT_SPELLCAST_CHANNEL_UPDATE",
        }) do
            playerRevealEvents:RegisterUnitEvent(event, "player")
        end
    end
    QueuePlayerRevealRefresh()
end

local function ChatNS()
    return EUI._ModuleNS and EUI._ModuleNS["EllesmereUIChat"]
end

local function ChatWins()
    local chat = ChatNS()
    return chat and chat._chatWins
end

local function ChatFrameData(frame)
    return frame and EUI._chatCFD and EUI._chatCFD(frame)
end

local function FrameIsMouseOver(frame)
    return frame and frame:IsShown() and frame:IsMouseOver()
end

local function ForEachChatFrame(callback)
    local seen = {}
    local frames = _G.CHAT_FRAMES
    if type(frames) == "table" then
        for i = 1, #frames do
            local frame = _G[frames[i]]
            if frame and not seen[frame] then
                seen[frame] = true
                callback(frame)
            end
        end
    end
    for i = 1, 20 do
        local frame = _G["ChatFrame" .. i]
        if frame and not seen[frame] then
            seen[frame] = true
            callback(frame)
        end
    end
end

-------------------------------------------------------------------------------
-- Native ScrollingMessageFrame line fading.
-------------------------------------------------------------------------------
local function CancelLineTimer(state)
    if state and state.timer then
        state.timer:Cancel()
        state.timer = nil
    end
end

local function ConfigureLineWindow(win)
    local smf = win and win.smf
    if not smf then return nil end
    local state = lineStates[win]
    if not state then
        state = {}
        lineStates[win] = state
    end
    if state.generation == lineGeneration then return state end
    state.generation = lineGeneration
    CancelLineTimer(state)

    if ns.Get("fadeChatLines") then
        smf:SetTimeVisible(ns.Get("chatLineSeconds"))
        smf:SetFadeDuration(ns.Get("chatFadeDuration"))
        if smf.ResetAllFadeTimes then smf:ResetAllFadeTimes() end
        smf:SetFading(state.interacting ~= true)
    else
        state.interacting = false
        if smf.ResetAllFadeTimes then smf:ResetAllFadeTimes() end
        smf:SetFading(false)
    end
    return state
end

local function SetLineInteraction(win, interacting)
    if not ns.Get("fadeChatLines") then return end
    local smf = win and win.smf
    local state = ConfigureLineWindow(win)
    if not (smf and state) or state.interacting == interacting then return end
    state.interacting = interacting
    CancelLineTimer(state)

    if interacting then
        if smf.ResetAllFadeTimes then smf:ResetAllFadeTimes() end
        smf:SetFading(false)
    elseif smf.ResetAllFadeTimes then
        smf:ResetAllFadeTimes()
        smf:SetFading(true)
    else
        smf:SetFading(false)
        state.timer = C_Timer.NewTimer(ns.Get("chatLineSeconds"), function()
            state.timer = nil
            if not state.interacting and ns.Get("fadeChatLines") then
                smf:SetFading(true)
            end
        end)
    end
end

-------------------------------------------------------------------------------
-- Tab discovery and independent auto-hide. Docked ghosts are on the exported
-- strip. Floating ghosts are recognizable addon-owned children of each chat
-- panel; no Blizzard tab fields are written.
-------------------------------------------------------------------------------
local function FindFloatGhost(cf)
    local cached = floatGhosts[cf]
    local data = ChatFrameData(cf)
    local bg = data and data.bg
    if cached and bg and cached:GetParent() == bg and cached.state
            and cached.state.cf == cf then
        return cached
    end
    floatGhosts[cf] = nil
    if not bg then return nil end
    local children = { bg:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child._fs and child.state and child.state.cf == cf then
            floatGhosts[cf] = child
            return child
        end
    end
end

local function MainChatAlpha()
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    selected = selected or _G.ChatFrame1
    return selected and selected:GetAlpha() or 1
end

local function PaintTabs(shown)
    tabsShown = shown and true or false
    local chat = ChatNS()
    local alpha = tabsShown and MainChatAlpha() or 0
    local strip = chat and chat._chatTabStrip
    if strip then strip:SetAlpha(alpha) end

    local blizzardTabs = chat and chat.ChatBlizzTabs and chat.ChatBlizzTabs()
    local dock = _G.GeneralDockManager
    if dock and blizzardTabs then dock:SetAlpha(alpha) end

    local wins = ChatWins()
    if not blizzardTabs and wins then
        for cf in pairs(wins) do
            if cf and not cf.isDocked then
                local ghost = FindFloatGhost(cf)
                if ghost then ghost:SetAlpha(tabsShown and 1 or 0) end
            end
        end
    end
end

local function RestoreTabs()
    PaintTabs(true)
end

-------------------------------------------------------------------------------
-- Chat chrome. Blizzard still updates its hidden focus textures to the active
-- channel color, so channel mode reads that authoritative color and paints an
-- addon-owned solid border whose physical-pixel size is user controlled.
-------------------------------------------------------------------------------
local function SetButtonMouse(button, enabled)
    if not button then return end
    if button.SetMouseClickEnabled then
        pcall(button.SetMouseClickEnabled, button, enabled)
        if button.SetMouseMotionEnabled then
            pcall(button.SetMouseMotionEnabled, button, enabled)
        end
    else
        pcall(button.EnableMouse, button, enabled)
    end
end

local function CreateInputBorder(editBox)
    if InCombatLockdown and InCombatLockdown() then return nil end
    local border = CreateFrame("Frame", nil, editBox)
    border:SetAllPoints(editBox)
    border:SetFrameLevel(editBox:GetFrameLevel() + 5)
    border:EnableMouse(false)
    border.top = border:CreateTexture(nil, "OVERLAY")
    border.bottom = border:CreateTexture(nil, "OVERLAY")
    border.left = border:CreateTexture(nil, "OVERLAY")
    border.right = border:CreateTexture(nil, "OVERLAY")
    inputBorders[editBox] = border
    return border
end

local function InputBorderPixels()
    local step = ns.Get("inputBorderStep") or 1
    local px = EUI.BorderPx and EUI.BorderPx(ns.Get("inputBorderSizePx"), step, "solid")
    if not px and EUI.BorderLegacyPx then px = EUI.BorderLegacyPx(step, "solid") end
    px = px or step
    return px, px * ((EUI.PP and EUI.PP.mult) or 1)
end

function ns.GetInputChannelColor(editBox)
    -- Blizzard's hidden focus textures stay white on this client.  The header
    -- is the live, already-resolved color for Say, Party, Guild, Whisper, and
    -- numbered channels, so prefer it before consulting the chat attributes.
    local header = editBox and editBox.header
    if header and header.GetTextColor then
        local r, g, b, a = header:GetTextColor()
        if r ~= nil then return r, g, b, a or 1 end
    end

    -- Attribute fallback for edit boxes whose header has not painted yet.
    -- This is read from our polling path, never from a Blizzard edit-box hook,
    -- so it does not taint the secure chat-type update chain.
    local chatType = editBox and editBox.GetAttribute
        and editBox:GetAttribute("chatType")
    if type(chatType) == "string" and not IsSecret(chatType) then
        local info
        if chatType == "CHANNEL" then
            local target = editBox:GetAttribute("channelTarget")
            if (type(target) == "number" or type(target) == "string")
                and not IsSecret(target) then
                info = _G.ChatTypeInfo and _G.ChatTypeInfo["CHANNEL" .. target]
            end
        end
        info = info or (_G.ChatTypeInfo and _G.ChatTypeInfo[chatType])
        if info then return info.r or 1, info.g or 1, info.b or 1, 1 end
    end

    local focus = editBox and editBox.focusLeft
    if focus and focus.GetVertexColor then
        local r, g, b, a = focus:GetVertexColor()
        return r or 1, g or 1, b or 1, a or 1
    end
    local say = _G.ChatTypeInfo and _G.ChatTypeInfo.SAY
    return say and say.r or 1, say and say.g or 1, say and say.b or 1, 1
end

local function InputBorderColor(editBox)
    local mode = ns.Get("inputBorderColorMode") or "channel"
    if mode == "accent" and EUI.GetAccentColor then
        local r, g, b = EUI.GetAccentColor()
        return r, g, b, 1
    elseif mode == "custom" then
        local c = ns.Get("inputBorderColor") or DEFAULTS.inputBorderColor
        return c.r or 1, c.g or 1, c.b or 1, c.a == nil and 1 or c.a
    end

    return ns.GetInputChannelColor(editBox)
end

local function UpdateInputBorder(editBox, enabled)
    local border = inputBorders[editBox]
    if enabled and not border then border = CreateInputBorder(editBox) end
    if not border then return end

    local pixels, thickness = InputBorderPixels()
    local active = enabled and pixels > 0 and editBox:IsShown()
        and editBox.HasFocus and editBox:HasFocus()
    border:SetShown(active and true or false)
    if not active then return end

    local top, bottom, left, right = border.top, border.bottom, border.left, border.right
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
    top:SetHeight(thickness)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(thickness)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", border, "TOPLEFT", 0, -thickness)
    left:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, thickness)
    left:SetWidth(thickness)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, -thickness)
    right:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, thickness)
    right:SetWidth(thickness)

    local r, g, b, a = InputBorderColor(editBox)
    top:SetColorTexture(r, g, b, a)
    bottom:SetColorTexture(r, g, b, a)
    left:SetColorTexture(r, g, b, a)
    right:SetColorTexture(r, g, b, a)
end

local function ApplyChatChrome()
    local hideCollapse = ns.Get("hideCollapseButtons")
    local channelBorder = ns.Get("channelInputBorder")
    ForEachChatFrame(function(cf)
        local name = cf:GetName()
        if not name then return end

        local buttonFrame = _G[name .. "ButtonFrame"]
        local minimize = buttonFrame and (buttonFrame.minimizeButton
            or _G[name .. "ButtonFrameMinimizeButton"])
        if minimize then
            pcall(minimize.SetAlpha, minimize, hideCollapse and 0 or 1)
            SetButtonMouse(minimize, not hideCollapse)
        end

        local editBox = _G[name .. "EditBox"]
        if editBox then
            -- Keep Ellesmere's native focus art hidden; the resolved header
            -- color supplies Channel Color while our border supplies size.
            if editBox.focusLeft then editBox.focusLeft:SetAlpha(0) end
            if editBox.focusMid then editBox.focusMid:SetAlpha(0) end
            if editBox.focusRight then editBox.focusRight:SetAlpha(0) end
            UpdateInputBorder(editBox, channelBorder)
        end
    end)
end

local function SharedChatInteraction()
    local chat = ChatNS()
    local strip = chat and chat._chatTabStrip
    if FrameIsMouseOver(strip) or FrameIsMouseOver(_G.GeneralDockManager) then
        return true
    end
    local main = _G.ChatFrame1
    local data = ChatFrameData(main)
    return FrameIsMouseOver(data and data.sidebar)
end

local function WindowInteraction(cf, shared)
    if not (cf and cf:IsShown()) then return false end
    local data = ChatFrameData(cf)
    if FrameIsMouseOver(data and data.bg) then return true end

    local name = cf:GetName()
    local editBox = name and _G[name .. "EditBox"]
    if editBox and editBox.HasFocus and editBox:HasFocus() then return true end

    local tab = name and _G[name .. "Tab"]
    if FrameIsMouseOver(tab) then return true end
    local ghost = FindFloatGhost(cf)
    if FrameIsMouseOver(ghost) then return true end

    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    return shared and cf == selected
end

local function PollChat()
    local wins = ChatWins()
    if not wins then return end
    local shared = SharedChatInteraction()
    local anyInteraction = shared

    for cf, win in pairs(wins) do
        ConfigureLineWindow(win)
        local interacting = WindowInteraction(cf, shared)
        if interacting then anyInteraction = true end
        SetLineInteraction(win, interacting)
    end

    if ns.Get("autoHideTabs") then
        local now = GetTime()
        if anyInteraction then
            tabsLastInteraction = now
            tabsInteracting = true
            PaintTabs(true)
        else
            if tabsInteracting then
                tabsInteracting = false
                tabsLastInteraction = now
            end
            PaintTabs(now - tabsLastInteraction < ns.Get("tabSeconds"))
        end
    elseif not tabsShown then
        RestoreTabs()
    end
end

function ns.ApplyAll()
    lineGeneration = lineGeneration + 1
    tabsLastInteraction = GetTime()
    tabsInteracting = false
    RestoreTabs()
    ApplyChatChrome()
    if ns.ApplyFlightTweaks then ns.ApplyFlightTweaks() end
    if ns.ApplyCraftingCastIcon then ns.ApplyCraftingCastIcon() end
    if ns.ApplyQuestTimerTweaks then ns.ApplyQuestTimerTweaks() end
    if ns.ApplyAuraDurationBars then ns.ApplyAuraDurationBars() end
    if ns.ApplyLootSessionTracker then ns.ApplyLootSessionTracker() end
    SyncPlayerRevealEvents()
    SyncGatheringTrackingEvents()

    local wins = ChatWins()
    if wins then
        for _, win in pairs(wins) do ConfigureLineWindow(win) end
    end
end

function ns.Set(key, value)
    if DEFAULTS[key] == nil then return end
    DB()[key] = value
    ns.ApplyAll()
end

function ns.Reset()
    local db = DB()
    for key in pairs(db) do db[key] = nil end
    ns.ApplyAll()
end

driver = CreateFrame("Frame")
driver:Hide()
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("UPDATE_CHAT_WINDOWS")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then self:Show() end
    C_Timer.After(0, ns.ApplyAll)
end)

local elapsed = 0
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.10 then return end
    elapsed = 0
    PollChat()
    chromeElapsed = chromeElapsed + 0.10
    if chromeElapsed >= 0.50 then
        chromeElapsed = 0
        ApplyChatChrome()
    end
end)

if IsLoggedIn and IsLoggedIn() then
    driver:Show()
    C_Timer.After(0, ns.ApplyAll)
end
