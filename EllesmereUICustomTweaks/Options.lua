-------------------------------------------------------------------------------
-- EllesmereUI settings-panel integration for EllesmereUI Custom Tweaks.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

local registered = false

local function RegisterOptions()
    if registered or not (EUI.RegisterModule and EUI.Widgets) then return end
    registered = true

    local function Toggle(key, text, tooltip)
        return {
            type = "toggle",
            text = text,
            tooltip = tooltip,
            getValue = function() return ns.Get(key) == true end,
            setValue = function(value) ns.Set(key, value) end,
        }
    end

    local function Slider(key, text, minimum, maximum, step, tooltip, disabled)
        return {
            type = "slider",
            text = text,
            tooltip = tooltip,
            min = minimum,
            max = maximum,
            step = step,
            disabled = disabled,
            getValue = function() return ns.Get(key) end,
            setValue = function(value) ns.Set(key, value) end,
        }
    end

    local function BuildPage(_, parent, yOffset)
        local W = EUI.Widgets
        local y = yOffset
        local _, h
        if EUI.ClearContentHeader then EUI:ClearContentHeader() end
        parent._showRowDivider = true

        _, h = W:SectionHeader(parent, "FLIGHT TIMER", y); y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("hideFlightYou", "Hide Center 'You' Label",
                "Keeps the centre route marker but removes its redundant You label."),
            nil)
        y = y - h

        _, h = W:SectionHeader(parent, "CHAT HISTORY", y); y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("fadeChatLines", "Fade Old Chat Lines",
                "Fades each chat line after the selected delay. Hovering or focusing that chat window restores its history."),
            Slider("chatLineSeconds", "Seconds Before Fade", 5, 180, 5,
                "How long chat lines remain fully visible after you leave the window.",
                function() return not ns.Get("fadeChatLines") end))
        y = y - h
        _, h = W:DualRow(parent, y,
            Slider("chatFadeDuration", "Fade Duration", 0, 10, 0.5,
                "How many seconds a chat line takes to fade away.",
                function() return not ns.Get("fadeChatLines") end),
            nil)
        y = y - h

        _, h = W:SectionHeader(parent, "CHAT TABS", y); y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("autoHideTabs", "Auto-Hide Chat Tabs",
                "Hides docked and floating Ellesmere chat tabs after inactivity and restores them when you hover the chat window."),
            Slider("tabSeconds", "Seconds Before Hiding", 5, 180, 5,
                "How long chat tabs remain visible after you leave the chat area.",
                function() return not ns.Get("autoHideTabs") end))
        y = y - h

        _, h = W:SectionHeader(parent, "CHAT CONTROLS", y); y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("hideCollapseButtons", "Hide Collapse Buttons",
                "Hides Blizzard's collapse and expand button attached to chat windows."),
            Toggle("channelInputBorder", "Channel-Colored Input Border",
                "Shows Blizzard's focus outline around the chat input, colored for the active channel."))
        y = y - h

        return math.abs(y)
    end

    EUI:RegisterModule(ADDON_NAME, {
        title = "Custom Tweaks",
        description = "Personal flight timer and chat refinements for EllesmereUI.",
        pages = { "Tweaks" },
        buildPage = BuildPage,
        searchTerms = "custom tweaks flight timer you chat fade history tabs collapse input border channel",
        onReset = function()
            ns.Reset()
            if EUI.InvalidatePageCache then EUI:InvalidatePageCache() end
        end,
    })
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, addonName)
    if addonName == "EllesmereUIOptions" then RegisterOptions() end
end)

if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUIOptions") then
    RegisterOptions()
elseif IsAddOnLoaded and IsAddOnLoaded("EllesmereUIOptions") then
    RegisterOptions()
end
