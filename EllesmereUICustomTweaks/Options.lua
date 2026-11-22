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
        local auraTexturePaths, auraTextureValues, auraTextureOrder = EUI.BuildBarTextureTables()
        if EUI.AppendSharedMediaTextures then
            EUI.AppendSharedMediaTextures(auraTextureValues, auraTextureOrder, nil, auraTexturePaths)
        end
        if EUI.ClearContentHeader then EUI:ClearContentHeader() end
        parent._showRowDivider = true

        if EUI.IS_FOREVER then
            _, h = W:SectionHeader(parent, "MINIMAP", y); y = y - h
            _, h = W:DualRow(parent, y,
                Toggle("alwaysGatheringTracking", "Always Enable Gathering Tracking",
                    "Keeps your last-used Find Herbs or Find Minerals minimap tracker enabled after login, zoning, death, or another tracker replacing it."),
                nil)
            y = y - h

            _, h = W:SectionHeader(parent, "QUEST TRACKER", y); y = y - h
            _, h = W:DualRow(parent, y,
                Toggle("questTimerFullWidth", "Full-Width Quest Timer Bar",
                    "Extends the timed-quest bar to the full available quest-tracker row instead of matching the Time Remaining text width."),
                { type = "multiSwatch", text = "Empty Timer Color",
                  swatches = {
                      { tooltip = "Empty Timer Color", hasAlpha = true,
                        getValue = function()
                            local c = ns.Get("questTimerEmptyColor") or ns.DEFAULTS.questTimerEmptyColor
                            return c.r or 0.15, c.g or 0.15, c.b or 0.15,
                                c.a == nil and 0.8 or c.a
                        end,
                        setValue = function(r, g, b, a)
                            ns.Set("questTimerEmptyColor", { r = r, g = g, b = b, a = a })
                        end },
                  } })
            y = y - h

            _, h = W:SectionHeader(parent, "LOOT FEED SESSION", y); y = y - h
            local durableLoot = Toggle("durableLootSession", "Persist Gold and XP Session",
                "Caches this character's Loot Feed gold and XP counters across reloads and relogs. Offline time is excluded from the hourly-rate clock.")
            durableLoot.setValue = function(value)
                ns.Set("durableLootSession", value)
                EUI:RefreshPage()
            end
            _, h = W:DualRow(parent, y,
                durableLoot,
                Slider("lootSessionTimeoutHours", "Reset After Offline", 1, 48, 1,
                    "Starts a fresh session after this many consecutive hours offline. Short reloads and relogs keep the existing session.",
                    function() return not ns.Get("durableLootSession") end))
            y = y - h
            _, h = W:DualRow(parent, y,
                { type = "button", text = "Reset Cached Session",
                  tooltip = "Clears the durable Loot Feed gold, spending, XP, and elapsed-time counters for this character.",
                  disabled = function() return not ns.Get("durableLootSession") end,
                  onClick = function()
                      if ns.ResetLootSession then ns.ResetLootSession() end
                  end },
                nil)
            y = y - h
        end

        _, h = W:SectionHeader(parent, "FLIGHT TIMER", y); y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("hideFlightYou", "Hide Center 'You' Marker",
                "Removes the centre marker and its redundant You label."),
            Toggle("fixedFlightPoints", "Fixed Flight-Point Markers",
                "Places every point at its route position on the bar. Point names appear only while hovering their markers."))
        y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("smartFlightExit", "Smart Early Exit",
                "Shows Ellesmere's early-exit button only while the route still has an intermediate flight point ahead."),
            Toggle("hideBlizzardFlightExit", "Hide Blizzard Flight Exit",
                "Hides Blizzard's duplicate early-landing button during taxi flights without affecting vehicle exit buttons."))
        y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("learnFlightTimes", "Learn Actual Route Times",
                "Records clean completed flights by their complete route and uses the learned time for future timers and flight-point tooltips."),
            nil)
        y = y - h
        _, h = W:DualRow(parent, y,
            { type = "button", text = "Clear Learned Route Times",
              tooltip = "Forgets recorded flight durations. New clean flights will begin learning them again.",
              onClick = function()
                  ns.ResetFlightTimes()
                  EUI:RefreshPage()
              end },
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

        _, h = W:SectionHeader(parent, "PLAYER CAST BAR", y); y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("useCraftedItemIcon", "Show Crafted Item Icon",
                "Replaces the generic crafting cast icon with the recipe or output-item icon shown by the profession interface."),
            nil)
        y = y - h

        _, h = W:SectionHeader(parent, "AURA DURATION BARS", y); y = y - h
        local auraOff = function() return not ns.Get("auraDurationBars") end
        local auraEnable = Toggle("auraDurationBars", "Enable Aura Duration Bars",
            "Shows selected player buffs as horizontal duration bars above the player unit frame.")
        auraEnable.setValue = function(value)
            ns.Set("auraDurationBars", value)
            EUI:RefreshPage()
        end
        _, h = W:DualRow(parent, y,
            auraEnable,
            Slider("auraDurationBarMax", "Maximum Bars", 1, 20, 1,
                "Maximum number of selected buffs shown at once.", auraOff))
        y = y - h

        local assignedRow
        assignedRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Filters",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end, setValue = function() end },
            { type = "dropdown", text = "Extra Spells",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end, setValue = function() end })
        y = y - h

        local function PlayerAuraBarsNS()
            return EUI._ModuleNS and EUI._ModuleNS["EllesmereUIUnitFrames"]
        end
        local function CurrentFilters()
            local source = ns.Get("auraDurationFilters")
            local copy = {}
            if type(source) == "table" then
                for id, enabled in pairs(source) do
                    if enabled then copy[id] = true end
                end
            end
            return copy
        end
        local function HasFilter(id)
            local filters = ns.Get("auraDurationFilters")
            return type(filters) == "table" and filters[id] == true
        end
        local function NativeFilters()
            local pab = PlayerAuraBarsNS()
            local list = pab and pab.PAB_Filters and pab.PAB_Filters() or {}
            local result, seenNames = {}, {}
            for i = 1, #list do
                local filter = list[i]
                local name = filter.name or ("Filter " .. tostring(filter.id))
                if not seenNames[name] then
                    seenNames[name] = true
                    result[#result + 1] = filter
                end
            end
            return result
        end

        -- Native Player Aura Bars filter assignments.  The selection is saved
        -- by Custom Tweaks, while filter definitions and editing remain owned
        -- by EllesmereUI's shared registry.
        do
            local region = assignedRow._leftRegion
            if region and region._control then region._control:Hide() end

            local function Items()
                local pab = PlayerAuraBarsNS()
                local items = {}
                if pab and pab.PABMP_ShowFilterEditor then
                    items[#items + 1] = {
                        isTopAction = true,
                        label = "Edit Filters",
                        onClick = function() pab.PABMP_ShowFilterEditor() end,
                    }
                end
                local filters = NativeFilters()
                if #filters > 0 then
                    items[#items + 1] = { isHeader = true, label = "Assigned Filters" }
                    for i = 1, #filters do
                        items[#items + 1] = {
                            key = filters[i].id,
                            label = filters[i].name or ("Filter " .. tostring(filters[i].id)),
                        }
                    end
                else
                    items[#items + 1] = { isHeader = true, label = "No filters available" }
                end
                return items
            end

            local dropdown, refresh = EUI.BuildVisOptsCBDropdown(
                region, 190, region:GetFrameLevel() + 2,
                Items, HasFilter,
                function(id, enabled)
                    local filters = CurrentFilters()
                    filters[id] = enabled and true or nil
                    ns.Set("auraDurationFilters", filters)
                    EUI:RefreshPage()
                end,
                nil, 12, true)
            EUI.PanelPP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dropdown
            region._lastInline = nil
            EUI.RegisterWidgetRefresh(refresh)
        end

        -- Native Extra Spells behaviour: selected custom IDs first, followed
        -- by the searchable curated preset universe, with spells supplied by
        -- an assigned filter omitted as redundant choices.
        do
            local region = assignedRow._rightRegion
            if region and region._control then region._control:Hide() end

            local function CurrentSpells()
                local source = ns.Get("auraDurationSpellIDs")
                local copy = {}
                if type(source) == "table" then
                    for i = 1, #source do copy[#copy + 1] = source[i] end
                end
                return copy
            end
            local function HasSpell(id)
                local spells = ns.Get("auraDurationSpellIDs")
                if type(spells) ~= "table" then return false end
                for i = 1, #spells do
                    if tonumber(spells[i]) == tonumber(id) then return true end
                end
                return false
            end
            local function SetSpells(spells)
                table.sort(spells, function(a, b)
                    return (tonumber(a) or 0) < (tonumber(b) or 0)
                end)
                ns.Set("auraDurationSpellIDs", spells)
            end
            local function AddSpellPopup()
                EUI:ShowInputPopup({
                    title = "Add Extra Spell",
                    message = "Enter a buff spell ID or paste a spell link.",
                    confirmText = "Add", cancelText = "Cancel",
                    onConfirm = function(text)
                        text = tostring(text or "")
                        local id = tonumber(text:match("spell:(%d+)") or text:match("^%s*(%d+)%s*$"))
                        if not (id and id > 0) or HasSpell(id) then return end
                        local spells = CurrentSpells()
                        spells[#spells + 1] = id
                        SetSpells(spells)
                        EUI:RefreshPage(true)
                    end,
                })
            end
            local function SpellEntry(id)
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                return { key = id, label = name or ("Spell " .. tostring(id)), icon = icon }
            end
            local function PresetUniverse()
                local pab = PlayerAuraBarsNS()
                local source = pab and pab.PAB_AllPresetSpells and pab.PAB_AllPresetSpells() or {}
                local result, seenNames = {}, {}
                for i = 1, #source do
                    local id = source[i]
                    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                    local key = name or ("id:" .. tostring(id))
                    if not seenNames[key] then
                        seenNames[key] = true
                        result[#result + 1] = id
                    end
                end
                return result
            end
            local function Items()
                local pab = PlayerAuraBarsNS()
                local covered = {}
                local selectedFilters = ns.Get("auraDurationFilters")
                if pab and type(selectedFilters) == "table" and pab.PAB_GetFilter then
                    for filterID, enabled in pairs(selectedFilters) do
                        local filter = enabled and pab.PAB_GetFilter(filterID)
                        if filter and type(filter.spells) == "table" then
                            for id, on in pairs(filter.spells) do
                                if on and not (pab.PAB_OtherClientSpell
                                    and pab.PAB_OtherClientSpell(filter, id)) then
                                    covered[id] = true
                                end
                            end
                        end
                    end
                end

                local selected, presets, seen = {}, {}, {}
                local spells = CurrentSpells()
                for i = 1, #spells do
                    seen[spells[i]] = true
                    selected[#selected + 1] = SpellEntry(spells[i])
                end
                local universe = PresetUniverse()
                for i = 1, #universe do
                    local id = universe[i]
                    if not seen[id] and not covered[id] then
                        presets[#presets + 1] = SpellEntry(id)
                    end
                end
                local function ByLabel(a, b) return a.label < b.label end
                table.sort(selected, ByLabel)
                table.sort(presets, ByLabel)
                local items = {
                    { isTopAction = true, label = "Custom Spell ID", onClick = AddSpellPopup },
                }
                if #selected > 0 then
                    items[#items + 1] = { isHeader = true, label = "Selected" }
                    for i = 1, #selected do items[#items + 1] = selected[i] end
                end
                items[#items + 1] = { isHeader = true, label = "Presets" }
                for i = 1, #presets do items[#items + 1] = presets[i] end
                return items
            end
            local dropdown, refresh = EUI.BuildVisOptsCBDropdown(
                region, 190, region:GetFrameLevel() + 2,
                Items, HasSpell,
                function(id, enabled)
                    local spells = CurrentSpells()
                    if enabled then
                        if not HasSpell(id) then spells[#spells + 1] = id end
                    else
                        local pab = PlayerAuraBarsNS()
                        local family = pab and pab.PAB_SPELL_FAMILY and pab.PAB_SPELL_FAMILY[id]
                        for i = #spells, 1, -1 do
                            local spellID = tonumber(spells[i])
                            if spellID == tonumber(id)
                                or (family and spellID
                                    and pab.PAB_SPELL_FAMILY[spellID] == family) then
                                table.remove(spells, i)
                            end
                        end
                    end
                    SetSpells(spells)
                    EUI:RefreshPage()
                end,
                nil, 10, true)
            EUI.PanelPP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dropdown
            region._lastInline = nil
            EUI.RegisterWidgetRefresh(refresh)
        end

        _, h = W:DualRow(parent, y,
            Slider("auraDurationBarWidth", "Bar Width", 120, 500, 5,
                "Width of each aura timer bar, including its icon.", auraOff),
            Slider("auraDurationBarHeight", "Bar Height", 14, 40, 1,
                "Height of each aura timer bar and its icon.", auraOff))
        y = y - h
        _, h = W:DualRow(parent, y,
            Slider("auraDurationBarSpacing", "Bar Spacing", 0, 20, 1,
                "Vertical space between aura timer bars.", auraOff),
            Slider("auraDurationBarOffsetY", "Vertical Offset", -100, 200, 1,
                "Distance above the player unit frame.", auraOff))
        y = y - h
        _, h = W:DualRow(parent, y,
            Slider("auraDurationBarOffsetX", "Horizontal Offset", -300, 300, 1,
                "Horizontal position relative to the centre of the player unit frame.", auraOff),
            { type = "dropdown", text = "Bar Texture",
              values = auraTextureValues, order = auraTextureOrder,
              disabled = auraOff,
              getValue = function() return ns.Get("auraDurationBarTexture") end,
              setValue = function(value) ns.Set("auraDurationBarTexture", value) end })
        y = y - h

        local function SetAuraColorMode(mode)
            if auraOff() then return end
            ns.Set("auraDurationBarColorMode", mode)
            EUI:RefreshPage()
        end
        local function ClassColor()
            local classToken = EUI._playerClass
            if not classToken and UnitClass then
                local _, token = UnitClass("player")
                classToken = token
            end
            local color = classToken and EUI.GetClassColor and EUI.GetClassColor(classToken)
            if color then return color.r, color.g, color.b, 1 end
            return 1, 1, 1, 1
        end
        _, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Bar Color", disabled = auraOff,
              swatches = {
                  { tooltip = "Custom Color", hasAlpha = true,
                    getValue = function()
                        local c = ns.Get("auraDurationBarColor") or ns.DEFAULTS.auraDurationBarColor
                        return c.r, c.g, c.b, c.a == nil and 1 or c.a
                    end,
                    setValue = function(r, g, b, a)
                        ns.Set("auraDurationBarColor", { r = r, g = g, b = b, a = a })
                        ns.Set("auraDurationBarColorMode", "custom")
                    end,
                    onClick = function(self)
                        if ns.Get("auraDurationBarColorMode") ~= "custom" then
                            SetAuraColorMode("custom")
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        return ns.Get("auraDurationBarColorMode") == "custom" and 1 or 0.3
                    end },
                  { tooltip = "Accent Color", hasAlpha = false,
                    getValue = function()
                        if EUI.GetAccentColor then return EUI.GetAccentColor() end
                        return 1, 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = function() SetAuraColorMode("accent") end,
                    refreshAlpha = function()
                        return (ns.Get("auraDurationBarColorMode") or "accent") == "accent" and 1 or 0.3
                    end },
                  { tooltip = "Class Color", hasAlpha = false,
                    getValue = ClassColor,
                    setValue = function() end,
                    onClick = function() SetAuraColorMode("class") end,
                    refreshAlpha = function()
                        return ns.Get("auraDurationBarColorMode") == "class" and 1 or 0.3
                    end },
              } },
            Toggle("auraDurationBarShowIcon", "Show Buff Icon",
                "Shows the buff's icon at the left end of its duration bar."))
        y = y - h
        _, h = W:DualRow(parent, y,
            Toggle("auraDurationBarShowStacks", "Show Stack Count",
                "Shows stack counts over the buff icon when the aura has more than one application."),
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
        description = "Personal aura bars, cast-bar, quest-tracker, minimap, unit-frame, flight timer, and chat refinements for EllesmereUI.",
        pages = { "Tweaks" },
        buildPage = BuildPage,
        searchTerms = "custom tweaks aura duration bars buffs filter spell timer status cast bar crafted item recipe icon profession crafting queue quest tracker timed quest time remaining full width empty background color elvui minimap gathering tracking herbs minerals player unit frame health mana eating drinking channeling flight timer you route fixed marker flight point hover early exit blizzard learn actual time clear chat fade history tabs collapse input border channel",
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
