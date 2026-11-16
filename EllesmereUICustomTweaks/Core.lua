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

local driver
local lineGeneration = 0
local lineStates = setmetatable({}, { __mode = "k" })
local floatGhosts = setmetatable({}, { __mode = "k" })
local inputBorders = setmetatable({}, { __mode = "k" })
local tabsLastInteraction = 0
local tabsInteracting = false
local tabsShown = true
local chromeElapsed = 0

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
-- Flight timer: suppress only the centre label. The route post remains owned
-- and drawn by Forever Essentials.
-------------------------------------------------------------------------------
local function FlightBar()
    local entries = EUI._unlockRegisteredElements
    local entry = entries and entries.EUI_FlightTimer
    if not (entry and entry.getFrame) then return nil end
    local ok, frame = pcall(entry.getFrame)
    return ok and frame or nil
end

local function HideFlightLabel()
    local bar = FlightBar()
    local label = bar and bar.you and bar.you.label
    if label then label:SetAlpha(0) end
end

local function ApplyFlightSetting()
    if ns.Get("hideFlightYou") then
        HideFlightLabel()
    else
        local timer = EUI._FlightTimer
        if timer and timer.ApplyStyle then timer.ApplyStyle() end
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

local function InputBorderColor(editBox)
    local mode = ns.Get("inputBorderColorMode") or "channel"
    if mode == "accent" and EUI.GetAccentColor then
        local r, g, b = EUI.GetAccentColor()
        return r, g, b, 1
    elseif mode == "custom" then
        local c = ns.Get("inputBorderColor") or DEFAULTS.inputBorderColor
        return c.r or 1, c.g or 1, c.b or 1, c.a == nil and 1 or c.a
    end

    local focus = editBox.focusLeft
    if focus and focus.GetVertexColor then
        local r, g, b, a = focus:GetVertexColor()
        return r or 1, g or 1, b or 1, a or 1
    end
    local header = editBox.header
    if header and header.GetTextColor then
        local r, g, b, a = header:GetTextColor()
        return r or 1, g or 1, b or 1, a or 1
    end
    return 1, 1, 1, 1
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
            -- Keep Ellesmere's native focus art hidden; it remains our live
            -- source for Channel Color while the custom border supplies size.
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
    ApplyFlightSetting()

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
    if ns.Get("hideFlightYou") then HideFlightLabel() end

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
