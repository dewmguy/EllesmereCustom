-------------------------------------------------------------------------------
-- ElvUI-style player aura duration bars.
--
-- Blizzard makes player-aura duration data secret in combat.  This module
-- therefore rides EllesmereUI's AuraKit/Blizzard AuraContainer pipeline rather
-- than querying C_UnitAuras itself.  AuraKit supplies each protected AuraButton;
-- we register a horizontal StatusBar, spell-name text, duration text, icon, and
-- stack count during the button's legal initialization window.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = _G.EllesmereUI
local AK = EUI and EUI.AuraKit
if not (EUI and AK) then return end

local STYLE_KEY = "EllesmereUICustomTweaks_AuraDurationBars"
local GROUP_KEY = "customTweaksTrackedBuffs"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local textures = EUI.BuildBarTextureTables and EUI.BuildBarTextureTables() or {}

local host
local container
local applyQueued = false
local nativeFiltersHooked = false

local function Number(key, fallback)
    local value = tonumber(ns.Get(key))
    return value or fallback
end

local function DirectSpellIDs()
    local source = ns.Get("auraDurationSpellIDs")
    local result, seen = {}, {}
    if type(source) ~= "table" then return result end
    for i = 1, #source do
        local id = tonumber(source[i])
        if id and id > 0 and not seen[id] then
            seen[id] = true
            result[#result + 1] = id
        end
    end
    return result
end

local function UnitFramesNS()
    return EUI._ModuleNS and EUI._ModuleNS["EllesmereUIUnitFrames"]
end

-- Use the same resolver as native Player Aura Bars.  Besides unioning every
-- selected filter with Extra Spells, it expands rank/talent/state families and
-- ignores preset entries that belong only to the other game client.
local function SpellIDs()
    local unitFrames = UnitFramesNS()
    local resolver = unitFrames and unitFrames.PAB_ResolveSpells
    if type(resolver) == "function" then
        local ok, result = pcall(resolver, {
            showAllBuffs = false,
            filters = ns.Get("auraDurationFilters"),
            spells = ns.Get("auraDurationSpellIDs"),
        })
        if ok and type(result) == "table" then return result end
    end
    return DirectSpellIDs()
end

local function InstallNativeFilterHook()
    if nativeFiltersHooked or type(hooksecurefunc) ~= "function" then return end
    local unitFrames = UnitFramesNS()
    if not (unitFrames and type(unitFrames.PAB_ApplyLiveConfig) == "function") then return end
    hooksecurefunc(unitFrames, "PAB_ApplyLiveConfig", function()
        ns.ApplyAuraDurationBars()
    end)
    nativeFiltersHooked = true
end

local function BarColor()
    local mode = ns.Get("auraDurationBarColorMode") or "accent"
    if mode == "class" and EUI.GetClassColor then
        local classToken = EUI._playerClass
        if not classToken and UnitClass then
            local _, token = UnitClass("player")
            if not (_G.issecretvalue and _G.issecretvalue(token)) then classToken = token end
        end
        local color = classToken and EUI.GetClassColor(classToken)
        if color then return color.r, color.g, color.b, 1 end
    elseif mode == "custom" then
        local color = ns.Get("auraDurationBarColor") or ns.DEFAULTS.auraDurationBarColor
        return color.r or 1, color.g or 1, color.b or 1, color.a == nil and 1 or color.a
    end
    if EUI.GetAccentColor then
        local r, g, b = EUI.GetAccentColor()
        return r, g, b, 1
    end
    return 0.05, 0.75, 0.58, 1
end

local function TexturePath()
    local key = ns.Get("auraDurationBarTexture") or "gradient-lr"
    if EUI.ResolveTexturePath then
        return EUI.ResolveTexturePath(textures, key, WHITE) or WHITE
    end
    return textures[key] or WHITE
end

local function MakeBorder(frame, parent)
    frame.top = frame:CreateTexture(nil, "OVERLAY")
    frame.bottom = frame:CreateTexture(nil, "OVERLAY")
    frame.left = frame:CreateTexture(nil, "OVERLAY")
    frame.right = frame:CreateTexture(nil, "OVERLAY")
    local px = (EUI.PP and EUI.PP.mult) or 1
    frame.top:SetPoint("TOPLEFT", parent, "TOPLEFT")
    frame.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    frame.top:SetHeight(px)
    frame.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
    frame.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    frame.bottom:SetHeight(px)
    frame.left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -px)
    frame.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, px)
    frame.left:SetWidth(px)
    frame.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -px)
    frame.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, px)
    frame.right:SetWidth(px)
    for _, region in ipairs({ frame.top, frame.bottom, frame.left, frame.right }) do
        region:SetColorTexture(0, 0, 0, 0.95)
    end
end

local function RegisterDurationBar(button, statusBar)
    if not button.SetDurationBar then return end
    local options = {}
    local interpolation = Enum and Enum.StatusBarInterpolation
    local direction = Enum and Enum.StatusBarTimerDirection
    if interpolation and interpolation.Immediate ~= nil then
        options.interpolation = interpolation.Immediate
    end
    if direction and direction.RemainingTime ~= nil then
        options.direction = direction.RemainingTime
    end
    button:SetDurationBar(statusBar, options)
end

local function BuildRegions(button, d)
    d.ctBar = CreateFrame("StatusBar", nil, button)
    d.ctBar:SetFrameLevel(button:GetFrameLevel() + 1)
    d.ctBarBg = d.ctBar:CreateTexture(nil, "BACKGROUND")
    d.ctBarBg:SetAllPoints(d.ctBar)

    d.ctIcon = button:CreateTexture(nil, "ARTWORK")
    d.ctIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    d.ctText = CreateFrame("Frame", nil, button)
    d.ctText:SetAllPoints(button)
    d.ctText:SetFrameLevel(d.ctBar:GetFrameLevel() + 1)
    d.ctName = d.ctText:CreateFontString(nil, "OVERLAY")
    d.ctName:SetJustifyH("LEFT")
    d.ctDuration = d.ctText:CreateFontString(nil, "OVERLAY")
    d.ctDuration:SetJustifyH("RIGHT")
    d.ctStacks = d.ctText:CreateFontString(nil, "OVERLAY")
    d.ctStacks:SetJustifyH("RIGHT")

    -- AuraButton registrations immediately write their current values. Give
    -- every target region a valid appearance first; an unfonted FontString can
    -- error when the engine performs that initial SetText.
    local font = (EUI.GetFontPath and EUI.GetFontPath(ADDON_NAME)) or "Fonts\\FRIZQT__.TTF"
    d.ctName:SetFont(font, 11, "OUTLINE")
    d.ctDuration:SetFont(font, 10, "OUTLINE")
    d.ctStacks:SetFont(font, 10, "OUTLINE")
    d.ctBar:SetStatusBarTexture(WHITE)

    d.ctBorder = CreateFrame("Frame", nil, button)
    d.ctBorder:SetAllPoints(button)
    d.ctBorder:SetFrameLevel(d.ctText:GetFrameLevel() + 1)
    d.ctBorder:EnableMouse(false)
    MakeBorder(d.ctBorder, button)

    button:SetIcon(d.ctIcon)
    d.akKickIcon = d.ctIcon
    if button.SetSpellName then button:SetSpellName(d.ctName) end
    RegisterDurationBar(button, d.ctBar)
    if button.SetApplicationCount then button:SetApplicationCount(d.ctStacks, {}) end
    if AK.SetDurationTextSafe then
        local formatter = AK.GetDurationFormatter and AK.GetDurationFormatter(true)
        local options = AK.BuildDurationTextOpts and AK.BuildDurationTextOpts(formatter) or {}
        AK.SetDurationTextSafe(button, d.ctDuration, options)
    elseif button.SetDurationText then
        button:SetDurationText(d.ctDuration, {})
    end
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
    d.ctBuilt = true
end

local function StyleRegions(button, d)
    if not d.ctBuilt then BuildRegions(button, d) end
    if AK.AurasRestricted and AK.AurasRestricted()
        and not (AK.InCreationWindow and AK.InCreationWindow(button)) then
        if AK.DeferRestyle then AK.DeferRestyle(STYLE_KEY) end
        return
    end

    local height = Number("auraDurationBarHeight", 20)
    local showIcon = ns.Get("auraDurationBarShowIcon") == true
    local iconGap = showIcon and 2 or 0
    local textInset = 4
    local fontSize = math.max(9, math.min(14, math.floor(height * 0.55 + 0.5)))
    local smallSize = math.max(8, fontSize - 1)
    local font = (EUI.GetFontPath and EUI.GetFontPath(ADDON_NAME)) or "Fonts\\FRIZQT__.TTF"

    d.ctIcon:ClearAllPoints()
    if showIcon then
        d.ctIcon:SetPoint("TOPLEFT", button, "TOPLEFT")
        d.ctIcon:SetSize(height, height)
        d.ctIcon:Show()
    else
        d.ctIcon:Hide()
    end

    d.ctBar:ClearAllPoints()
    d.ctBar:SetPoint("TOPLEFT", button, "TOPLEFT", showIcon and (height + iconGap) or 0, 0)
    d.ctBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
    d.ctBar:SetStatusBarTexture(TexturePath())
    local r, g, b, a = BarColor()
    d.ctBar:SetStatusBarColor(r, g, b, a)
    d.ctBarBg:SetColorTexture(0.025, 0.025, 0.025, 0.88)

    local barLeft = showIcon and (height + iconGap) or 0
    d.ctDuration:ClearAllPoints()
    d.ctDuration:SetPoint("RIGHT", button, "RIGHT", -textInset, 0)
    d.ctDuration:SetFont(font, smallSize, "OUTLINE")
    d.ctDuration:SetTextColor(1, 1, 1, 1)

    d.ctName:ClearAllPoints()
    d.ctName:SetPoint("LEFT", button, "LEFT", barLeft + textInset, 0)
    d.ctName:SetPoint("RIGHT", d.ctDuration, "LEFT", -4, 0)
    d.ctName:SetFont(font, fontSize, "OUTLINE")
    d.ctName:SetTextColor(1, 1, 1, 1)

    d.ctStacks:ClearAllPoints()
    d.ctStacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", height - 2, 1)
    d.ctStacks:SetFont(font, smallSize, "OUTLINE")
    d.ctStacks:SetTextColor(1, 1, 1, 1)
    d.ctStacks:SetShown(showIcon and ns.Get("auraDurationBarShowStacks") == true)
end

AK.styles[STYLE_KEY] = {
    noRegions = true,
    noTooltips = false,
    applyExtra = StyleRegions,
}

local function EnsureHost()
    if host then return host end
    host = CreateFrame("Frame", nil, UIParent)
    host:SetClampedToScreen(true)
    host:EnableMouse(false)
    return host
end

local function PositionHost()
    local frame = EnsureHost()
    local width = Number("auraDurationBarWidth", 240)
    local height = Number("auraDurationBarHeight", 20)
    local spacing = Number("auraDurationBarSpacing", 3)
    local maximum = math.max(1, math.floor(Number("auraDurationBarMax", 8)))
    frame:SetSize(width, height * maximum + spacing * (maximum - 1))
    frame:ClearAllPoints()

    local playerFrame = EUI.FindPlayerUnitFrame and EUI.FindPlayerUnitFrame()
    playerFrame = playerFrame or _G.EllesmereUIUnitFrames_Player
    if playerFrame then
        frame:SetPoint("BOTTOM", playerFrame, "TOP",
            Number("auraDurationBarOffsetX", 0), Number("auraDurationBarOffsetY", 8))
    else
        frame:SetPoint("CENTER", UIParent, "CENTER",
            Number("auraDurationBarOffsetX", 0), Number("auraDurationBarOffsetY", 8) + 80)
    end
end

local function GroupLayout()
    return {
        elementWidth = Number("auraDurationBarWidth", 240),
        elementHeight = Number("auraDurationBarHeight", 20),
        elementSpacing = 0,
        lineSpacing = Number("auraDurationBarSpacing", 3),
        groupSpacing = 0,
        groupLineSpacing = Number("auraDurationBarSpacing", 3),
    }
end

local function CandidateFilters(ids)
    local include = {}
    for i = 1, #ids do include[ids[i]] = true end
    return { includeSpellIDs = include }
end

local function SortMethod()
    local methods = _G.AuraContainerSortMethod
    return methods and (methods.ExpirationOnly or methods.Expiration or methods.Default)
end

local function SortDirection()
    local directions = _G.AuraContainerSortDirection
    return directions and directions.Normal
end

local function EnsureContainer(ids)
    if container then return container end
    local frame = EnsureHost()
    local Flow = AnchorUtil and AnchorUtil.FlowDirection
    local spec = {
        point = { "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0 },
        layout = {
            anchorPoint = "BOTTOMLEFT",
            padding = { 0, 0, 0, 0 },
            rowWidth = Number("auraDurationBarWidth", 240),
            growthH = Flow and Flow.Right,
            growthV = Flow and Flow.Up,
        },
        groups = {{
            key = GROUP_KEY,
            filter = { "HELPFUL" },
            style = STYLE_KEY,
            maxFrameCount = math.max(1, math.floor(Number("auraDurationBarMax", 8))),
            candidateFilters = CandidateFilters(ids),
            sortMethod = SortMethod(),
            sortDirection = SortDirection(),
            layout = GroupLayout(),
        }},
    }
    AK.RequestContainer(frame, "player", spec, function(value) container = value end)
    return container
end

local function ApplyNow()
    applyQueued = false
    PositionHost()
    local ids = SpellIDs()
    local active = ns.Get("auraDurationBars") == true and #ids > 0
    local auraContainer = EnsureContainer(ids)
    if not auraContainer then
        host:SetShown(false)
        return
    end

    local width = Number("auraDurationBarWidth", 240)
    local maximum = math.max(1, math.floor(Number("auraDurationBarMax", 8)))
    auraContainer:ClearAllPoints()
    auraContainer:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    if AK.SetContainerAnchor then AK.SetContainerAnchor(auraContainer, "BOTTOMLEFT") end
    if AK.SetContainerAxis then AK.SetContainerAxis(auraContainer, false) end
    if AK.SetContainerGrowth and AnchorUtil and AnchorUtil.FlowDirection then
        AK.SetContainerGrowth(auraContainer, AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
    end
    if AK.SetContainerPadding then AK.SetContainerPadding(auraContainer, 0, 0, 0, 0) end
    if AK.SetContainerRowWidth then AK.SetContainerRowWidth(auraContainer, width) end
    if auraContainer.SetAuraGroupLayout then
        auraContainer:SetAuraGroupLayout(GROUP_KEY, GroupLayout())
    end
    if auraContainer.SetAuraGroupCandidateFilters then
        auraContainer:SetAuraGroupCandidateFilters(GROUP_KEY, CandidateFilters(ids))
    end
    if auraContainer.SetAuraGroupSortMethod then
        local method, direction = SortMethod(), SortDirection()
        if method ~= nil and direction ~= nil then
            auraContainer:SetAuraGroupSortMethod(GROUP_KEY, method, direction)
        end
    end
    if AK.SetGroupCap then AK.SetGroupCap(auraContainer, GROUP_KEY, active and maximum or 0) end
    if active and auraContainer.UpdateAllAuras then auraContainer:UpdateAllAuras() end
    host:SetShown(active)
    if AK.RestyleSoon then AK.RestyleSoon(STYLE_KEY) end
end

function ns.ApplyAuraDurationBars()
    InstallNativeFilterHook()
    if applyQueued then return end
    applyQueued = true
    C_Timer.After(0, function()
        local ok, err = pcall(ApplyNow)
        if not ok then geterrorhandler()(err) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, addonName)
    if event ~= "ADDON_LOADED" or addonName == "EllesmereUIUnitFrames" then
        InstallNativeFilterHook()
        ns.ApplyAuraDurationBars()
    end
end)
