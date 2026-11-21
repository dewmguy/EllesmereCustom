-------------------------------------------------------------------------------
-- EllesmereUI custom quest-timer presentation.
--
-- The native custom tracker owns the timer rows and updates their fill every
-- second.  This module discovers those rows through the public tracker frame,
-- then overrides only the timer bar width and empty-track texture.  The timer
-- text, remaining-time fill, colors, borders, and countdown remain native.
-------------------------------------------------------------------------------
local _, ns = ...

local hookedBars = setmetatable({}, { __mode = "k" })
local barLines = setmetatable({}, { __mode = "k" })
local backgrounds = setmetatable({}, { __mode = "k" })
local widthGuard = setmetatable({}, { __mode = "k" })
local trackerHooked
local applyQueued

local function Number(value, fallback)
    value = tonumber(value)
    return value or fallback
end

local function EmptyColor()
    local color = ns.Get("questTimerEmptyColor") or ns.DEFAULTS.questTimerEmptyColor
    return Number(color.r, 0.15), Number(color.g, 0.15),
        Number(color.b, 0.15), Number(color.a, 0.8)
end

local function TimerBackground(bar)
    local known = backgrounds[bar]
    if known then return known end
    for index = 1, select("#", bar:GetRegions()) do
        local region = select(index, bar:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            local layer = region:GetDrawLayer()
            if layer == "BACKGROUND" then
                backgrounds[bar] = region
                return region
            end
        end
    end
end

local function AvailableWidth(line)
    if not (line and line.GetWidth) then return end
    return math.max(Number(line:GetWidth(), 1) - Number(line.dashW, 0), 1)
end

local function NativeWidth(line)
    if not (line and line.text and line.text.GetStringWidth) then return end
    return math.max(Number(line.text:GetStringWidth(), 1) - Number(line.dashW, 0), 1)
end

local function SetTimerWidth(bar, line)
    local width = ns.Get("questTimerFullWidth") and AvailableWidth(line) or NativeWidth(line)
    if not width or math.abs(Number(bar:GetWidth(), 0) - width) < 0.01 then return end
    widthGuard[bar] = true
    bar:SetWidth(width)
    widthGuard[bar] = nil
end

local function ApplyBar(bar, line)
    if not (bar and line) then return end
    barLines[bar] = line
    SetTimerWidth(bar, line)
    local bg = TimerBackground(bar)
    if bg then bg:SetColorTexture(EmptyColor()) end
end

local function HookBar(bar, line)
    if not (bar and bar.SetWidth) then return end
    barLines[bar] = line
    if hookedBars[bar] then return end
    hooksecurefunc(bar, "SetWidth", function(self)
        if widthGuard[self] or not ns.Get("questTimerFullWidth") then return end
        SetTimerWidth(self, barLines[self])
    end)
    hookedBars[bar] = true
end

local function Scan(frame)
    if not (frame and frame.GetChildren) then return end
    local children = { frame:GetChildren() }
    for index = 1, #children do
        local child = children[index]
        if child and child.bar and child.text then
            HookBar(child.bar, child)
            ApplyBar(child.bar, child)
        end
        Scan(child)
    end
end

local function QueueApply()
    if applyQueued then return end
    applyQueued = true
    C_Timer.After(0, function()
        applyQueued = false
        ns.ApplyQuestTimerTweaks()
    end)
end

function ns.ApplyQuestTimerTweaks()
    local tracker = _G.EUI_CustomQuestTracker
    if not tracker then return end
    if trackerHooked ~= tracker then
        tracker:HookScript("OnShow", QueueApply)
        trackerHooked = tracker
    end
    Scan(tracker)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, addonName)
    if event ~= "ADDON_LOADED" or addonName == "EllesmereUIQuestTracker" then
        QueueApply()
    end
end)
