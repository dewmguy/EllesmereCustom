-------------------------------------------------------------------------------
-- EllesmereUI Custom Tweaks: flight timer refinements.
--
-- Forever Essentials continues to own the flight bar, styling, mover, route
-- data, and native fallback estimate.  This file overlays fixed, hover-labelled
-- route points, trims the duplicate exit controls, and layers learned route
-- times on top.  No EllesmereUI file needs to be modified for the feature to
-- work.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = _G.EllesmereUI
if not (EUI and EUI.IS_FOREVER) then return end

local DEFAULT_SPEED = 30.4
local ROUTE_HISTORY = 5
local STOP_ICON = "Interface\\Minimap\\Tracking\\FlightMaster"
local POINT_SIZE = 14
local NATIVE_LOOKAHEAD = 60

local pending
local active
local taxiHooked
local landingHooked
local classicTooltipHooked
local flightMapTooltipHooked
local routeElapsed = 0

local function DB()
    local db = _G.EllesmereUICustomTweaksDB
    if type(db) ~= "table" then
        db = {}
        _G.EllesmereUICustomTweaksDB = db
    end
    return db
end

local function RouteDB(create)
    local db = DB()
    if type(db.flightRoutes) ~= "table" and create then db.flightRoutes = {} end
    return db.flightRoutes
end

local function NativeTimer()
    return EUI._FlightTimer
end

local function NativeGet(key, fallback)
    local timer = NativeTimer()
    if timer and type(timer.Get) == "function" then
        local ok, value = pcall(timer.Get, key)
        if ok and value ~= nil then return value end
    end
    return fallback
end

local function NativeEnabled()
    return NativeTimer() and NativeGet("enabled", true) ~= false
end

local function NativeSpeed()
    local timer = NativeTimer()
    if timer and type(timer.Cfg) == "function" then
        local ok, cfg = pcall(timer.Cfg)
        local speed = ok and type(cfg) == "table" and cfg.speed
        if type(speed) == "number" and speed > 0 then return speed end
    end
    return DEFAULT_SPEED
end

local function SpeedMultiplier()
    if not (C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetNodeInfo) then return 1 end
    local configID = C_Traits.GetConfigIDByTreeID(1188)
    local node = configID and C_Traits.GetNodeInfo(configID, 110300)
    return (node and node.activeRank or 0) > 0 and 1.2 or 1
end

local function FormatTime(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function FlightBar()
    local entries = EUI._unlockRegisteredElements
    local entry = entries and entries.EUI_FlightTimer
    if not (entry and entry.getFrame) then return nil end
    local ok, frame = pcall(entry.getFrame)
    return ok and frame or nil
end

local function HideFlightCenter(bar)
    bar = bar or FlightBar()
    if not bar then return end
    if bar.you then
        if bar.you.icon then bar.you.icon:Hide() end
        if bar.you.label then bar.you.label:Hide() end
    end
end

-- Build a stable directed key from every node on the selected path.  Names are
-- presentation only; node IDs keep translated clients and duplicate names from
-- splitting or merging learned routes incorrectly.
local function RouteInfo(slot)
    if type(slot) ~= "number" or type(GetNumRoutes) ~= "function" then return nil end
    local hops = GetNumRoutes(slot)
    if type(hops) ~= "number" or hops < 1 then return nil end

    local mapID = GetTaxiMapID and GetTaxiMapID()
    local nodes = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_TaxiMap.GetAllTaxiNodes(mapID)
    local idBySlot = {}
    for _, node in ipairs(nodes or idBySlot) do
        idBySlot[node.slotIndex] = node.nodeID
    end

    local ids = {}
    local points = {}
    local startSlot = TaxiGetNodeSlot(slot, 1, true)
    ids[1] = idBySlot[startSlot]
    points[1] = { name = TaxiNodeName(startSlot), yards = 0 }

    local routeData = EUI._FlightTimerRoutes
    local yards = 0
    for hop = 1, hops do
        local fromSlot = TaxiGetNodeSlot(slot, hop, true)
        local toSlot = TaxiGetNodeSlot(slot, hop, false)
        local from = idBySlot[fromSlot]
        local to = idBySlot[toSlot]
        ids[hop + 1] = to
        local hopYards = routeData and from and to and routeData[from * 10000 + to]
        yards = yards and hopYards and yards + hopYards
        points[#points + 1] = { name = TaxiNodeName(toSlot), yards = yards }
    end

    local validIDs = true
    for i = 1, #points do
        if type(ids[i]) ~= "number" then validIDs = false break end
    end

    local key = validIDs and table.concat(ids, ">") or nil
    local totalYards = yards and yards > 0 and yards or nil
    return {
        key = key,
        points = points,
        yards = totalYards,
        staticBase = totalYards and totalYards / NativeSpeed() or nil,
    }
end

local function HideNativeMarks(marks)
    for _, mark in ipairs(marks or {}) do
        if mark.icon then mark.icon:Hide() end
        if mark.label then mark.label:Hide() end
    end
end

local function HideFixedRoute(bar)
    local route = bar and bar.customTweaksRoute
    if route then route:Hide() end
end

local function SuppressNativeRoute(bar)
    if not bar then return end
    if ns.Get("fixedFlightPoints") then
        if bar.clip then
            if bar.clip.glide then bar.clip.glide:Stop() end
            bar.clip:Hide()
        end
        HideNativeMarks(bar.ends)
        HideNativeMarks(bar.stops)
    else
        HideFixedRoute(bar)
    end
    if ns.Get("hideFlightYou") then HideFlightCenter(bar) end
end

local function NewRouteMarker(route)
    local marker = CreateFrame("Button", nil, route)
    marker:SetSize(POINT_SIZE + 6, POINT_SIZE + 6)
    marker:EnableMouse(true)
    marker.icon = marker:CreateTexture(nil, "OVERLAY")
    marker.icon:SetTexture(STOP_ICON)
    marker.icon:SetSize(POINT_SIZE, POINT_SIZE)
    marker.icon:SetPoint("CENTER")
    marker:SetScript("OnEnter", function(self)
        if self.flightPointName then EUI.ShowWidgetTooltip(self, self.flightPointName) end
    end)
    marker:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
    route.marks[#route.marks + 1] = marker
    return marker
end

local function FixedRoute(bar)
    local route = bar.customTweaksRoute
    if route then return route end
    route = CreateFrame("Frame", nil, bar.over or bar)
    route:SetAllPoints(bar)
    route:EnableMouse(false)
    route.marks = {}
    bar.customTweaksRoute = route
    return route
end

local function LayoutFixedRoute(bar, flight)
    if not (bar and ns.Get("fixedFlightPoints") and flight and flight.info) then
        HideFixedRoute(bar)
        return
    end
    local points = flight.info.points
    local count = points and #points or 0
    if count == 0 then
        HideFixedRoute(bar)
        return
    end

    local route = FixedRoute(bar)
    local levelOwner = bar.over or bar
    route:SetFrameLevel(levelOwner:GetFrameLevel() + 1)
    local width = bar:GetWidth()
    if not width or width <= 0 then width = NativeGet("width", 300) end
    local total = flight.info.yards
    for index = 1, count do
        local point = points[index]
        local marker = route.marks[index] or NewRouteMarker(route)
        local fraction
        if total and total > 0 and point.yards then
            fraction = math.max(0, math.min(1, point.yards / total))
        else
            fraction = count == 1 and 0 or (index - 1) / (count - 1)
        end
        marker.flightPointName = point.name or "Flight point"
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", bar, "CENTER", (fraction - 0.5) * width, 0)
        marker:SetAlpha(1)
        marker:Show()
    end
    for index = count + 1, #route.marks do route.marks[index]:Hide() end
    route:SetShown(bar:IsShown())
end

local function HasFutureIntermediate(flight, elapsed)
    local info = flight and flight.info
    local points = info and info.points
    if not points or #points <= 2 or flight.early then return false end
    local eta = flight.eta or flight.nativeETA
    if not (eta and eta > 0 and info.yards and info.yards > 0) then return true end
    local flown = math.max(0, math.min(1, elapsed / eta)) * info.yards
    for index = 2, #points - 1 do
        if not points[index].yards or points[index].yards > flown then return true end
    end
    return false
end

local function UpdateEarlyExit(bar, flight, elapsed)
    local button = bar and bar.exit
    if not (button and ns.Get("smartFlightExit")) then return end
    local show = NativeGet("earlyExit", true) and HasFutureIntermediate(flight, elapsed)
    button:SetEnabled(show)
    button:SetAlpha(show and 1 or 0)
    button:SetShown(show)
end

local function HideBlizzardFlightExit()
    if not (ns.Get("hideBlizzardFlightExit") and UnitOnTaxi("player")) then return end
    local button = _G.MainMenuBarVehicleLeaveButton
    if button then button:Hide() end
end

local function ApplyRoutePresentation(flight, elapsed)
    local bar = FlightBar()
    if not bar then return end
    SuppressNativeRoute(bar)
    LayoutFixedRoute(bar, flight)
    UpdateEarlyExit(bar, flight, elapsed or 0)
end

local function Median(values)
    local sorted = {}
    for i = 1, #values do
        local value = values[i]
        if type(value) == "number" and value > 0 then sorted[#sorted + 1] = value end
    end
    if #sorted == 0 then return nil end
    table.sort(sorted)
    local middle = math.floor(#sorted / 2) + 1
    if #sorted % 2 == 1 then return sorted[middle] end
    return (sorted[middle - 1] + sorted[middle]) / 2
end

local function LearnedBase(routeKey)
    local routes = RouteDB(false)
    local entry = routes and routeKey and routes[routeKey]
    return type(entry) == "table" and type(entry.times) == "table" and Median(entry.times) or nil
end

-- Times are stored without Frequent Flier's 20% bonus.  One account-wide
-- route history can therefore serve characters both with and without it.
local function RecordFlight(flight, elapsed)
    if not (ns.Get("learnFlightTimes") and flight and flight.sawTaxi and not flight.early) then return end
    if not (flight.info and flight.info.key and type(elapsed) == "number" and elapsed >= 5 and elapsed <= 7200) then return end

    local normalized = elapsed * (flight.mult or 1)
    local learned = LearnedBase(flight.info.key)
    local reference = learned or flight.info.staticBase
    -- A wide gate catches stale clicks and broken measurements.  The rolling
    -- median handles ordinary variation without rejecting a genuinely wrong
    -- static route estimate such as the one this feature is meant to repair.
    if reference and (normalized < reference * (learned and 0.5 or 0.35)
            or normalized > reference * (learned and 2 or 3)) then
        return
    end

    local routes = RouteDB(true)
    local entry = routes[flight.info.key]
    if type(entry) ~= "table" then
        entry = { times = {}, samples = 0 }
        routes[flight.info.key] = entry
    elseif type(entry.times) ~= "table" then
        entry.times = {}
    end

    entry.times[#entry.times + 1] = normalized
    while #entry.times > ROUTE_HISTORY do table.remove(entry.times, 1) end
    entry.samples = (tonumber(entry.samples) or 0) + 1
    entry.lastSeen = time and time() or nil
    entry.from = flight.info.points[1] and flight.info.points[1].name or nil
    entry.to = flight.info.points[#flight.info.points] and flight.info.points[#flight.info.points].name or nil
end

local function Estimate(info, allowLearned)
    if not info then return nil, false end
    local learned = allowLearned and info.key and LearnedBase(info.key)
    local base = learned or info.staticBase
    if not base then return nil, false end
    return base / SpeedMultiplier(), learned ~= nil
end

local function AddEstimatedTimeToTooltip(slot)
    if not NativeEnabled() then return end
    local eta, learned = Estimate(RouteInfo(slot), ns.Get("learnFlightTimes"))
    if not eta then return end
    GameTooltip:AddLine("Estimated flight time: " .. FormatTime(eta) .. (learned and " (learned)" or ""), 0.45, 0.8, 1)
    GameTooltip:Show()
end

local function HookTooltips()
    if not classicTooltipHooked and type(TaxiNodeOnButtonEnter) == "function" then
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
            if button then AddEstimatedTimeToTooltip(button:GetID()) end
        end)
        classicTooltipHooked = true
    end

    local mixin = FlightMap_FlightPointPinMixin
    if not flightMapTooltipHooked and type(mixin) == "table" and type(mixin.OnMouseEnter) == "function" then
        hooksecurefunc(mixin, "OnMouseEnter", function(pin)
            local node = pin and pin.taxiNodeData
            if node then AddEstimatedTimeToTooltip(node.slotIndex) end
        end)
        flightMapTooltipHooked = true
    end
end

local function OnTakeTaxiNode(slot)
    if not NativeEnabled() then pending = nil return end
    local info = RouteInfo(slot)
    pending = info and { info = info, clicked = GetTime() } or nil
end

local function RestoreNativeDisplay(flight, restyle)
    local bar = flight and (flight.bar or FlightBar())
    if not bar then return end
    if bar.time then bar.time:SetAlpha(flight.nativeTimeAlpha or 1) end
    if bar.customTweaksTime then bar.customTweaksTime:Hide() end
    flight.applied = false
    if restyle then
        local timer = NativeTimer()
        if timer and timer.ApplyStyle then timer.ApplyStyle() end
        ApplyRoutePresentation(flight, GetTime() - flight.start)
    end
end

local function ArmTrack(bar, startTime, eta)
    if not (bar and bar.track and C_DurationUtil and C_DurationUtil.CreateDuration) then return end
    local duration = C_DurationUtil.CreateDuration()
    duration:SetTimeFromStart(startTime, eta)
    bar.track:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
end

local function StyleCustomTime(bar)
    local text = bar.customTweaksTime
    if not text then
        text = bar:CreateFontString(nil, "OVERLAY")
        text:SetWordWrap(false)
        bar.customTweaksTime = text
    end
    if EUI.ApplyModuleFont then EUI.ApplyModuleFont(text, nil, NativeGet("timeSize", 12), "essentials") end
    text:ClearAllPoints()
    local point, relativeTo, relativePoint, x, y = bar.time:GetPoint(1)
    if point then
        text:SetPoint(point, relativeTo, relativePoint, x, y)
    else
        text:SetPoint("RIGHT", bar, "LEFT", -13 + NativeGet("timeX", 0), NativeGet("timeY", 0))
    end
    if bar.time and bar.time.GetTextColor then text:SetTextColor(bar.time:GetTextColor()) end
    text:SetShown(NativeGet("timeText", "show") ~= "none")
    return text
end

local function ApplyLearnedDisplay(flight)
    if not (flight and flight.eta and not flight.early and ns.Get("learnFlightTimes")) then return false end
    local bar = FlightBar()
    if not (bar and bar:IsShown() and bar.time and bar.track) then return false end

    flight.bar = bar
    if flight.nativeTimeAlpha == nil then flight.nativeTimeAlpha = bar.time:GetAlpha() end
    bar.time:SetAlpha(0)
    StyleCustomTime(bar)
    ArmTrack(bar, flight.start, flight.eta)
    flight.applied = true
    return true
end

local function UpdateLearnedDisplay(flight, elapsed)
    if not flight.applied and not ApplyLearnedDisplay(flight) then return end
    local bar = flight.bar
    if not (bar and bar:IsShown()) then return end

    local text = bar.customTweaksTime or StyleCustomTime(bar)
    local left = FormatTime(flight.eta - elapsed)
    local value = NativeGet("showTotal", false) and (left .. " / " .. FormatTime(flight.eta)) or left
    if value ~= flight.lastText then
        flight.lastText = value
        text:SetText(value)
    end

    -- Preserve the original moving-strip correction when the fixed-marker
    -- overlay is explicitly disabled.
    if ns.Get("fixedFlightPoints") then return end
    local info = flight.info
    local clip = bar.clip
    if not (clip and clip:IsShown() and info and info.yards and info.points and #info.points > 2) then return end
    if clip.glide then clip.glide:Stop() end
    local width = bar:GetWidth()
    if not (width and width > 0) then return end
    local pps = width / 2 / NATIVE_LOOKAHEAD
    clip.pps = pps
    local travel = math.max(0, math.min(elapsed, flight.eta))
    clip.strip:ClearAllPoints()
    clip.strip:SetPoint("CENTER", bar, "CENTER", -travel * pps, 0)

    local now = GetTime()
    if flight.nextRouteLayout and now < flight.nextRouteLayout then return end
    flight.nextRouteLayout = now + 0.20
    for index = 1, #info.points - 2 do
        local point = info.points[index + 1]
        local mark = bar.stops and bar.stops[index]
        if mark and point and point.yards then
            local arrival = point.yards / info.yards * flight.eta
            mark.icon:ClearAllPoints()
            mark.icon:SetPoint("CENTER", clip.strip, "CENTER", arrival * pps, 0)
            local alpha = elapsed >= arrival and 0.4 or 1
            mark.icon:SetAlpha(alpha)
            mark.label:SetAlpha(alpha)
        end
    end
end

local function FinishFlight(learn)
    local flight = active
    if not flight then return end
    active = nil
    local elapsed = GetTime() - flight.start
    if learn then RecordFlight(flight, elapsed) end
    RestoreNativeDisplay(flight, false)
    HideFixedRoute(flight.bar or FlightBar())
end

local function StartFlight()
    if not (pending and GetTime() - pending.clicked < 5) then pending = nil return end
    local info = pending.info
    pending = nil
    local mult = SpeedMultiplier()
    local learned = ns.Get("learnFlightTimes") and info.key and LearnedBase(info.key)
    active = {
        info = info,
        start = GetTime(),
        mult = mult,
        nativeETA = info.staticBase and info.staticBase / mult or nil,
        eta = learned and learned / mult or nil,
    }
    C_Timer.After(0, function()
        if not active then return end
        if active.eta then ApplyLearnedDisplay(active) end
        ApplyRoutePresentation(active, GetTime() - active.start)
        HideBlizzardFlightExit()
    end)
end

local function RequestEarlyLanding()
    if not active then return end
    active.early = true
    RestoreNativeDisplay(active, true)
end

local function HookFlightAPI()
    HookTooltips()
    if not taxiHooked and type(TakeTaxiNode) == "function" then
        hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
        taxiHooked = true
    end
    if not landingHooked and type(TaxiRequestEarlyLanding) == "function" then
        hooksecurefunc("TaxiRequestEarlyLanding", RequestEarlyLanding)
        landingHooked = true
    end
end

function ns.ResetFlightTimes()
    DB().flightRoutes = {}
    if active and active.applied then RestoreNativeDisplay(active, true) end
    if active then active.eta = nil end
end

function ns.ApplyFlightTweaks()
    HookFlightAPI()
    local timer = NativeTimer()
    if timer and timer.ApplyStyle then timer.ApplyStyle() end

    if active then
        local learned = ns.Get("learnFlightTimes") and active.info.key and LearnedBase(active.info.key)
        active.eta = learned and learned / active.mult or nil
        if active.eta then
            ApplyLearnedDisplay(active)
        elseif active.applied then
            RestoreNativeDisplay(active, true)
        end
    end
    ApplyRoutePresentation(active, active and (GetTime() - active.start) or 0)
    HideBlizzardFlightExit()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_CONTROL_LOST")
events:RegisterEvent("PLAYER_CONTROL_GAINED")
events:RegisterEvent("TAXIMAP_OPENED")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        ns.ApplyFlightTweaks()
    elseif event == "PLAYER_CONTROL_LOST" then
        StartFlight()
    elseif event == "PLAYER_CONTROL_GAINED" then
        if active and not UnitOnTaxi("player") then FinishFlight(active.sawTaxi and not active.early) end
    elseif event == "TAXIMAP_OPENED" then
        HookFlightAPI()
    elseif event == "ADDON_LOADED" and ... == "Blizzard_FlightMap" then
        HookFlightAPI()
    end
end)

events:SetScript("OnUpdate", function(_, delta)
    local flight = active
    local elapsed = flight and (GetTime() - flight.start) or 0
    routeElapsed = routeElapsed + delta
    if routeElapsed >= 0.20 then
        routeElapsed = 0
        ApplyRoutePresentation(flight, elapsed)
        HideBlizzardFlightExit()
    end

    if not flight then return end
    if UnitOnTaxi("player") then flight.sawTaxi = true end
    if elapsed > 2 and not UnitOnTaxi("player") then
        FinishFlight(flight.sawTaxi and not flight.early)
        return
    end
    if flight.eta and not flight.early and ns.Get("learnFlightTimes") then
        UpdateLearnedDisplay(flight, elapsed)
    elseif flight.applied then
        RestoreNativeDisplay(flight, true)
    end
end)

HookFlightAPI()
