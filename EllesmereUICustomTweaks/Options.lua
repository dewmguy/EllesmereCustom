-------------------------------------------------------------------------------
-- EllesmereUI settings-panel integration for EllesmereUI Custom Tweaks.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

local registered = false

local function RegisterOptions()
    if registered then return true end
    -- Register the page as soon as the companion addon loads.  Ellesmere's
    -- widget factory belongs to the LoadOnDemand options addon, so waiting for
    -- EUI.Widgets here can miss the registration window entirely.  The page
    -- builder is not invoked until the options surface (and its widgets) is
    -- ready.
    if type(EUI.RegisterModule) ~= "function" then return false end

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

        _, h = W:SectionHeader(parent, "PLAYER UNIT FRAME", y); y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("showPlayerOnMissingHealth", "Show When Health Is Missing",
                "Reveals the Ellesmere player frame whenever your health is below maximum."),
            Toggle("showPlayerOnMissingMana", "Show When Mana Is Missing",
                "Reveals the Ellesmere player frame whenever your mana is below maximum."))
        y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("showPlayerWhileEating", "Show While Eating or Drinking",
                "Reveals the Ellesmere player frame while a food or drink regeneration aura is active."),
            Toggle("showPlayerWhileChanneling", "Show While Channeling",
                "Reveals the Ellesmere player frame only while you are channeling a spell."))
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
        local showBorder = Toggle("channelInputBorder", "Show Input Border",
            "Shows a configurable border around the active chat input.")
        showBorder.setValue = function(value)
            ns.Set("channelInputBorder", value)
            EUI:RefreshPage()
        end
        _, h = W:DualRow(parent, y,
            Toggle("hideCollapseButtons", "Hide Collapse Buttons",
                "Hides Blizzard's collapse and expand button attached to chat windows."),
            showBorder)
        y = y - h

        local borderDisabled = function() return not ns.Get("channelInputBorder") end
        local function SetBorderColorMode(mode)
            if borderDisabled() then return end
            ns.Set("inputBorderColorMode", mode)
            ns.ApplyAll()
            EUI:RefreshPage()
        end
        local function ChannelColor()
            return ns.GetInputChannelColor(_G.ChatFrame1EditBox)
        end
        _, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Input Border Color",
              disabled = borderDisabled,
              swatches = {
                  { tooltip = "Custom Color", hasAlpha = true,
                    getValue = function()
                        local c = ns.Get("inputBorderColor") or ns.DEFAULTS.inputBorderColor
                        return c.r, c.g, c.b, c.a == nil and 1 or c.a
                    end,
                    setValue = function(r, g, b, a)
                        ns.Set("inputBorderColor", { r = r, g = g, b = b, a = a })
                        ns.Set("inputBorderColorMode", "custom")
                        ns.ApplyAll()
                    end,
                    onClick = function(self)
                        if ns.Get("inputBorderColorMode") ~= "custom" then
                            SetBorderColorMode("custom")
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        return ns.Get("inputBorderColorMode") == "custom" and 1 or 0.3
                    end },
                  { tooltip = "Accent Color", hasAlpha = false,
                    getValue = function()
                        if EUI.GetAccentColor then return EUI.GetAccentColor() end
                        return 1, 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = function() SetBorderColorMode("accent") end,
                    refreshAlpha = function()
                        return ns.Get("inputBorderColorMode") == "accent" and 1 or 0.3
                    end },
                  { tooltip = "Channel Color", hasAlpha = false,
                    getValue = ChannelColor,
                    setValue = function() end,
                    onClick = function() SetBorderColorMode("channel") end,
                    refreshAlpha = function()
                        return (ns.Get("inputBorderColorMode") or "channel") == "channel" and 1 or 0.3
                    end },
              } },
            EUI.BorderPxSliderCfg{
              text = "Input Border Size", max = 8,
              disabled = borderDisabled,
              getStep = function() return ns.Get("inputBorderStep") or 1 end,
              setStep = function(value) ns.Set("inputBorderStep", value) end,
              getTex = function() return "solid" end,
              getPx = function() return ns.Get("inputBorderSizePx") end,
              setPx = function(value) ns.Set("inputBorderSizePx", value) end,
              apply = ns.ApplyAll })
        y = y - h

        return math.abs(y)
    end

    EUI:RegisterModule(ADDON_NAME, {
        title = "Custom Tweaks",
        description = "Personal unit-frame, flight timer, and chat refinements for EllesmereUI.",
        pages = { "Tweaks" },
        buildPage = BuildPage,
        searchTerms = "custom tweaks player unit frame health mana eating drinking channeling flight timer you chat fade history tabs collapse input border channel",
        onReset = function()
            ns.Reset()
            if EUI.InvalidatePageCache then EUI:InvalidatePageCache() end
        end,
    })
    registered = EUI._modules and EUI._modules[ADDON_NAME] ~= nil or false
    return registered
end

if not RegisterOptions() then
    -- Defensive fallback for an unusual load order.  Dependencies normally
    -- guarantee RegisterModule already exists before this file runs.
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, _, addonName)
        if addonName == "EllesmereUI" and RegisterOptions() then
            self:UnregisterAllEvents()
        end
    end)
    if EUI.RegisterOnShow then EUI:RegisterOnShow(RegisterOptions) end
end
