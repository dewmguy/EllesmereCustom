-------------------------------------------------------------------------------
-- Durable replacement for Forever Essentials' Loot Feed session summary.
--
-- The native tracker keeps its counters in file-local memory, so /reload and
-- relog start it over.  This module owns a per-character cache in the Custom
-- Tweaks SavedVariables, hides the native pinned summary, and draws a custom
-- summary in the same reserved slot.  Ellesmere still owns the feed, settings,
-- placement, fonts, textures, and surrounding layout.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = _G.EllesmereUI
if not (EUI and EUI.IS_FOREVER) then return end

local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local RATE_FLOOR = 60
local COMMIT_INTERVAL = 60
local COPPER_PER_GOLD = 10000
local MOUNT_BASE_COST = 100 * COPPER_PER_GOLD

-- The racial capital faction controls the WoW Forever riding discount.
local HOME_FACTION_BY_RACE = {
    Human = 72,       -- Stormwind
    Dwarf = 47,       -- Ironforge
    NightElf = 69,    -- Darnassus
    Gnome = 54,       -- Gnomeregan Exiles
    Orc = 76,         -- Orgrimmar
    Scourge = 68,     -- Undercity
    Tauren = 81,      -- Thunder Bluff
    Troll = 530,      -- Darkspear Trolls
}

local nativeLoot
local anchor
local nativeSummary
local summary
local tracking = false
local runningSince
local state
local stateKey
local lastMoney
local lastXP, lastMaxXP, lastLevel
local lastCommit = 0
local hooksInstalled = false
local updateTicker
local backgroundTextures

local function Plain(value, kind)
    if not (_G.issecretvalue and issecretvalue(value)) and type(value) == kind then
        return value
    end
end

local function RawDB()
    local db = _G.EllesmereUICustomTweaksDB
    if type(db) ~= "table" then
        db = {}
        _G.EllesmereUICustomTweaksDB = db
    end
    return db
end

local function CharacterKey()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    if not name then name = UnitName and UnitName("player") end
    if not name or (_G.issecretvalue and issecretvalue(name)) then return stateKey end
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() or "?" end
    return tostring(name or "?") .. "-" .. tostring(realm)
end

local function LegacyCharacterKey()
    local guid = UnitGUID and UnitGUID("player")
    if guid and not (_G.issecretvalue and issecretvalue(guid)) then return guid end
end

local function EmptyState()
    return {
        coin = 0,
        items = 0,
        spent = 0,
        xp = 0,
        elapsed = 0,
        started = false,
        lastSeen = time and time() or 0,
    }
end

local function NormalizeState(saved)
    if type(saved) ~= "table" then return EmptyState() end
    saved.coin = math.max(0, tonumber(saved.coin) or 0)
    saved.items = math.max(0, tonumber(saved.items) or 0)
    saved.spent = math.max(0, tonumber(saved.spent) or 0)
    saved.xp = math.max(0, tonumber(saved.xp) or 0)
    saved.elapsed = math.max(0, tonumber(saved.elapsed) or 0)
    saved.started = saved.started == true
    saved.lastSeen = tonumber(saved.lastSeen) or 0
    return saved
end

local function SessionState()
    local key = CharacterKey()
    if not key then
        state = state or EmptyState()
        return state
    end
    if state and stateKey == key then return state end

    local db = RawDB()
    db.lootSessions = type(db.lootSessions) == "table" and db.lootSessions or {}
    local saved = db.lootSessions[key]
    local legacyKey = LegacyCharacterKey()
    if type(saved) ~= "table" and legacyKey and legacyKey ~= key then
        saved = db.lootSessions[legacyKey]
    end
    saved = NormalizeState(saved)
    db.lootSessions[key] = saved
    -- Retain the GUID alias as a redundant copy and as a downgrade path for
    -- versions that predate the stable name-realm key.
    if legacyKey and legacyKey ~= key then db.lootSessions[legacyKey] = saved end
    state, stateKey = saved, key
    return saved
end

local function CommitElapsed(stop)
    local s = SessionState()
    if runningSince and s.started then
        local now = GetTime()
        s.elapsed = s.elapsed + math.max(0, now - runningSince)
        runningSince = stop and nil or now
    elseif stop then
        runningSince = nil
    end
    if s.started then s.lastSeen = time and time() or s.lastSeen end
    lastCommit = GetTime()
end

local function Elapsed()
    local s = SessionState()
    local live = runningSince and math.max(0, GetTime() - runningSince) or 0
    return s.elapsed + live
end

local function BeginSession()
    local s = SessionState()
    if not s.started then
        s.started = true
        s.elapsed = 0
        s.lastSeen = time and time() or 0
    end
    runningSince = runningSince or GetTime()
    return s
end

local function Add(kind, amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end
    local s = BeginSession()
    s[kind] = (tonumber(s[kind]) or 0) + amount
    s.lastSeen = time and time() or s.lastSeen
end

local function NativeLoot()
    local loot = EUI._LootFeed
    if type(loot) == "table" and type(loot.Get) == "function" then
        nativeLoot = loot
    end
    return nativeLoot
end

local function NativeTrackerEnabled()
    local loot = NativeLoot()
    return loot and loot.Get("enabled") == true and loot.Get("tracker") == true
end

local function TrackerEnabled()
    return ns.Get("durableLootSession") == true and NativeTrackerEnabled()
end

local function SetBaselines()
    lastMoney = Plain(GetMoney and GetMoney(), "number")
    lastXP = Plain(UnitXP and UnitXP("player"), "number")
    lastMaxXP = Plain(UnitXPMax and UnitXPMax("player"), "number")
    lastLevel = Plain(UnitLevel and UnitLevel("player"), "number")
end

local function SyncTracking()
    local wanted = TrackerEnabled()
    if wanted == tracking then return end
    tracking = wanted
    if tracking then
        local s = SessionState()
        if s.started then runningSince = GetTime() end
        SetBaselines()
    else
        CommitElapsed(true)
        lastMoney, lastXP, lastMaxXP, lastLevel = nil, nil, nil, nil
    end
end

local compiled = {}
local function Compile(formatString, anchored)
    local parts, index, first = {}, 1, nil
    while true do
        local startAt, endAt, position, kind = formatString:find("%%(%d?)%$?([sd])", index)
        parts[#parts + 1] = (formatString:sub(index, startAt and startAt - 1)
            :gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
        if not startAt then break end
        first = first or tonumber(position)
        parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
        index = endAt + 1
    end
    return { pattern = (anchored and "^" or "") .. table.concat(parts)
        .. (anchored and "$" or ""), swap = first == 2 }
end

local function Match(globalKey, text, loose)
    local entry = compiled[globalKey]
    if entry == nil then
        local formatString = _G[globalKey]
        entry = type(formatString) == "string" and formatString ~= ""
            and Compile(formatString, not loose) or false
        compiled[globalKey] = entry
    end
    if not entry then return end
    local first, second = text:match(entry.pattern)
    if entry.swap then return second, first end
    return first, second
end

local function TrackMoneyGain(text)
    local copper = 0
    for globalKey, multiplier in pairs({ GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }) do
        local amount = Match(globalKey, text, true)
        if amount then copper = copper + (tonumber(amount) or 0) * multiplier end
    end
    if copper > 0 then Add("coin", copper) end
end

local function AuctionPrice(link)
    local module = EUI._ModuleNS and EUI._ModuleNS["EllesmereUIForeverEssentials"]
    if module and type(module.AuctionPrice) == "function" then
        return module.AuctionPrice(link)
    end
    local api = _G.Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemLink then
        local ok, price = pcall(api.GetAuctionPriceByItemLink, "EllesmereUI", link)
        if ok and type(price) == "number" and price > 0 then return price end
    end
end

local function ItemValue(link, sellPrice, bindType)
    if Enum and Enum.ItemBind and bindType == Enum.ItemBind.Quest then return 0 end
    if Enum and Enum.ItemBind and bindType == Enum.ItemBind.OnAcquire then return sellPrice or 0 end
    local loot = NativeLoot()
    return loot and loot.Get("auctionPrices") and AuctionPrice(link) or sellPrice or 0
end

local function CountItem(link, count, retried)
    local name, _, _, _, _, _, _, _, _, _, sellPrice, _, _, bindType = C_Item.GetItemInfo(link)
    if not name then
        if not retried and Item and Item.CreateFromItemLink then
            Item:CreateFromItemLink(link):ContinueOnItemLoad(function()
                if tracking then CountItem(link, count, true) end
            end)
        end
        return
    end
    Add("items", ItemValue(link, sellPrice, bindType) * count)
end

local ITEM_KEYS = {
    { "LOOT_ITEM_SELF_MULTIPLE", true }, { "LOOT_ITEM_SELF", true },
    { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", false }, { "LOOT_ITEM_PUSHED_SELF", false },
    { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", true }, { "LOOT_ITEM_BONUS_ROLL_SELF", true },
    { "LOOT_ITEM_CREATED_SELF_MULTIPLE", false }, { "LOOT_ITEM_CREATED_SELF", false },
}

local function TrackLoot(text)
    for i = 1, #ITEM_KEYS do
        local itemText, count = Match(ITEM_KEYS[i][1], text)
        if itemText then
            if ITEM_KEYS[i][2] then
                local link = itemText:find("|Hitem:", 1, true) and itemText or nil
                if not link then
                    local name = itemText:match("^%[(.-)%]$")
                    local itemID = name and C_Item.GetItemInfoInstant(name)
                    if itemID then link = "item:" .. itemID end
                end
                if link then CountItem(link, tonumber(count) or 1) end
            end
            return
        end
    end
end

local function TrackWallet()
    local current = Plain(GetMoney and GetMoney(), "number")
    if not current then return end
    if lastMoney and current < lastMoney then Add("spent", lastMoney - current) end
    lastMoney = current
end

local function TrackExperience()
    local current = Plain(UnitXP and UnitXP("player"), "number")
    local maximum = Plain(UnitXPMax and UnitXPMax("player"), "number")
    local level = Plain(UnitLevel and UnitLevel("player"), "number")
    if current == nil or maximum == nil or level == nil then return end

    local gained = 0
    if lastXP ~= nil and lastLevel ~= nil then
        if level == lastLevel then
            if current < lastXP then return end
            gained = current - lastXP
        elseif level > lastLevel then
            gained = math.max(0, (lastMaxXP or lastXP) - lastXP) + current
        end
    end
    lastXP, lastMaxXP, lastLevel = current, maximum, level
    if gained > 0 then Add("xp", gained) end
end

local function Money(copper)
    return C_CurrencyInfo.GetCoinTextureString(math.max(0, math.floor(copper)), 12)
end

local function SessionMoney(copper)
    if copper < 0 then return "|cffff4040-" .. Money(-copper) .. "|r" end
    return Money(copper)
end

local function XP(amount)
    return BreakUpLargeNumbers(math.floor(math.max(0, amount))) .. " XP"
end

local function Duration(seconds)
    local minutes = math.ceil(math.max(0, seconds) / 60)
    if minutes < 60 then return string.format(EUI.L("%dm"), minutes) end
    return string.format(EUI.L("%dh %dm"), math.floor(minutes / 60), minutes % 60)
end

local function EstimatedDuration(remaining, perSecond)
    remaining = tonumber(remaining)
    perSecond = tonumber(perSecond)
    if not remaining or not perSecond or remaining <= 0 or perSecond <= 0 then
        return "--"
    end
    local seconds = remaining / perSecond
    if seconds ~= seconds or seconds == math.huge then return "--" end
    return Duration(seconds)
end

local function MountCost()
    local _, race = UnitRace and UnitRace("player")
    if _G.issecretvalue and issecretvalue(race) then race = nil end
    local factionID = race and HOME_FACTION_BY_RACE[race]
    if not factionID then
        factionID = UnitFactionGroup and UnitFactionGroup("player") == "Horde" and 76 or 72
    end

    local faction = C_Reputation and C_Reputation.GetFactionDataByID
        and C_Reputation.GetFactionDataByID(factionID)
    local reaction = faction and Plain(faction.reaction, "number")
    -- Forever applies its racial-faction vendor discount at Honored and does
    -- not deepen it at Revered or Exalted: 100g becomes 90g.
    return reaction and reaction >= 5
        and MOUNT_BASE_COST - 10 * COPPER_PER_GOLD or MOUNT_BASE_COST
end

local function FindAnchor()
    local elements = EUI._unlockRegisteredElements
    local element = elements and elements.EUI_LootFeed
    if element and type(element.getFrame) == "function" then
        local ok, frame = pcall(element.getFrame)
        if ok and frame then anchor = frame end
    end
    return anchor
end

local function FindNativeSummary(parent)
    if nativeSummary and nativeSummary:GetParent() == parent then return nativeSummary end
    local children = { parent:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child.pinned and child.xpSub and child.summaryDivider then
            nativeSummary = child
            if not child._customTweaksDurableHook then
                child._customTweaksDurableHook = true
                hooksecurefunc(child, "Show", function(self)
                    if ns.Get("durableLootSession") == true then self:Hide() end
                end)
            end
            return child
        end
    end
end

local function Text(parent, justify)
    local fontString = parent:CreateFontString(nil, "OVERLAY")
    fontString:SetJustifyH(justify or "LEFT")
    fontString:SetWordWrap(false)
    return fontString
end

local function EnsureSummary(parent)
    if summary and summary:GetParent() == parent then return summary end
    summary = CreateFrame("Frame", nil, parent)
    summary:SetFrameLevel(parent:GetFrameLevel() + 5)
    summary:EnableMouse(false)
    summary.bg = summary:CreateTexture(nil, "BACKGROUND")
    summary.bg:SetAllPoints()
    summary.bar = summary:CreateTexture(nil, "ARTWORK")
    summary.bar:SetPoint("TOPLEFT")
    summary.bar:SetPoint("BOTTOMLEFT")
    summary.iconBg = summary:CreateTexture(nil, "ARTWORK")
    summary.icon = summary:CreateTexture(nil, "ARTWORK", nil, 1)
    summary.icon:SetTexture(MONEY_ICON)
    summary.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    summary.goldRate = Text(summary)
    summary.goldTotal = Text(summary)
    summary.mountETA = Text(summary)
    summary.xpRate = Text(summary)
    summary.xpTotal = Text(summary)
    summary.xpETA = Text(summary)
    summary.divider = summary:CreateTexture(nil, "OVERLAY")
    summary.divider:SetColorTexture(1, 1, 1, 0.18)
    summary.divider:SetWidth(1)
    summary.divider:SetPoint("TOP", summary, "TOP", 0, -5)
    summary.divider:SetPoint("BOTTOM", summary, "BOTTOM", 0, 5)
    if EUI.PP and EUI.PP.CreateBorder then
        EUI.PP.CreateBorder(summary, 0, 0, 0, 1, 1, "OVERLAY", 2)
    end
    return summary
end

local gradientFrom = CreateColor(0, 0, 0, 0)
local gradientTo = CreateColor(0, 0, 0, 0)

local function SetBackground(texture, loot, fade)
    local key = loot.Get("bgTexture")
    if key == "none" then
        texture:SetColorTexture(1, 1, 1, 1)
    else
        backgroundTextures = backgroundTextures or EUI.BuildBarTextureTables()
        texture:SetTexture(EUI.ResolveTexturePath(backgroundTextures, key,
            "Interface\\Buttons\\WHITE8X8"))
        texture:SetVertexColor(1, 1, 1, 1)
    end
    local r, g, b, a = loot.Get("bgR"), loot.Get("bgG"), loot.Get("bgB"), loot.Get("bgA")
    gradientFrom:SetRGBA(r, g, b, a)
    gradientTo:SetRGBA(r, g, b, fade and 0 or a)
    texture:SetGradient("HORIZONTAL", gradientFrom, gradientTo)
end

local function ApplySummaryStyle(row, parent, loot)
    local width = loot.Get("width")
    local height = loot.Get("rowHeight")
    local fontSize = loot.Get("textSize")
    local etaFontSize = math.max(8, fontSize - 2)
    local extraHeight = etaFontSize + 4
    local summaryHeight = height + extraHeight
    local style = loot.Get("style")
    if style == "TRAY" then style = "BAR" end
    local barStyle, toast = style == "BAR", style == "TOAST"
    local barWidth = loot.Get("barWidth")

    row:SetSize(width, summaryHeight)
    row:ClearAllPoints()
    if loot.Get("grow") == "UP" then
        -- The native feed reserves one ordinary row for its pinned summary.
        -- Grow the third line away from the loot rows so the extra height does
        -- not overlap the first transient entry.
        row:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, -extraHeight)
    else
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, extraHeight)
    end

    row.icon:ClearAllPoints()
    if barStyle then
        row.bar:SetWidth(math.max(barWidth, 1))
        row.bar:SetShown(barWidth > 0)
        row.icon:SetSize(height - 8, height - 8)
        row.icon:SetPoint("LEFT", barWidth > 0 and barWidth + 5 or 4, 0)
    elseif toast then
        row.bar:Hide()
        row.icon:SetSize(height - 10, height - 10)
        row.icon:SetPoint("LEFT", 6, 0)
    else
        row.bar:Hide()
        row.icon:SetSize(height, height)
        row.icon:SetPoint("LEFT")
    end

    local accent = EUI.ELLESMERE_GREEN
    row.bar:SetColorTexture(accent and accent.r or 0.05, accent and accent.g or 0.82,
        accent and accent.b or 0.62, 1)
    SetBackground(row.bg, loot, barStyle)
    row.iconBg:ClearAllPoints()
    row.iconBg:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.iconBg:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    row.iconBg:SetColorTexture(0, 0, 0, 1)
    row.iconBg:SetShown(barStyle or toast)

    local borderSize = tonumber(loot.Get("borderSize")) or 0
    if EUI.PP and EUI.PP.UpdateBorder then
        if borderSize > 0 and not barStyle then
            local br, bg, bb = loot.Get("borderR"), loot.Get("borderG"), loot.Get("borderB")
            if toast then br, bg, bb = 0.69, 0.54, 0.23 end
            EUI.PP.UpdateBorder(row, borderSize, br, bg, bb, 1)
            EUI.PP.ShowBorder(row)
        else
            EUI.PP.HideBorder(row)
        end
    end

    for _, fontString in ipairs({ row.goldRate, row.goldTotal, row.xpRate, row.xpTotal }) do
        EUI.ApplyModuleFont(fontString, nil, fontSize, "essentials")
    end
    EUI.ApplyModuleFont(row.mountETA, nil, etaFontSize, "essentials")
    EUI.ApplyModuleFont(row.xpETA, nil, etaFontSize, "essentials")
    row.goldTotal:SetTextColor(0.7, 0.7, 0.7)
    row.xpTotal:SetTextColor(0.7, 0.7, 0.7)
    row.mountETA:SetTextColor(0.55, 0.55, 0.55)
    row.xpETA:SetTextColor(0.55, 0.55, 0.55)

    row.goldRate:ClearAllPoints()
    row.goldTotal:ClearAllPoints()
    row.mountETA:ClearAllPoints()
    row.xpRate:ClearAllPoints()
    row.xpTotal:ClearAllPoints()
    row.xpETA:ClearAllPoints()
    local edgeInset = summaryHeight / 2 - 3
    row.goldRate:SetPoint("TOPLEFT", row.icon, "RIGHT", 6, edgeInset)
    row.goldRate:SetPoint("RIGHT", row.divider, "LEFT", -8, 0)
    row.goldTotal:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.goldTotal:SetPoint("RIGHT", row.divider, "LEFT", -8, 0)
    row.mountETA:SetPoint("BOTTOMLEFT", row.icon, "RIGHT", 6, -edgeInset)
    row.mountETA:SetPoint("RIGHT", row.divider, "LEFT", -8, 0)
    row.xpRate:SetPoint("TOPLEFT", row.divider, "RIGHT", 8, edgeInset)
    row.xpRate:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.xpTotal:SetPoint("LEFT", row.divider, "RIGHT", 8, 0)
    row.xpTotal:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.xpETA:SetPoint("BOTTOMLEFT", row.divider, "RIGHT", 8, -edgeInset)
    row.xpETA:SetPoint("RIGHT", row, "RIGHT", -6, 0)
end

local function PaintSummary()
    SyncTracking()
    local parent = FindAnchor()
    if not parent then return end
    local native = FindNativeSummary(parent)

    if not TrackerEnabled() then
        if summary then summary:Hide() end
        if native and NativeTrackerEnabled() then native:Show() end
        return
    end

    if native then native:Hide() end
    local loot = NativeLoot()
    if not loot then return end
    local row = EnsureSummary(parent)
    ApplySummaryStyle(row, parent, loot)

    local s = SessionState()
    local elapsed = Elapsed()
    local divisor = math.max(elapsed, RATE_FLOOR)
    local gross = s.coin + s.items
    local net = gross - s.spent
    local goldPerSecond = gross / divisor
    local mountCost = MountCost()
    local wallet = Plain(GetMoney and GetMoney(), "number") or 0
    local mountRemaining = math.max(0, mountCost - wallet)
    local mountTime = mountRemaining == 0 and EUI.L("Ready")
        or EstimatedDuration(mountRemaining, goldPerSecond)
    local currentXP = Plain(UnitXP and UnitXP("player"), "number")
    local maximumXP = Plain(UnitXPMax and UnitXPMax("player"), "number")
    local xpRemaining = currentXP and maximumXP and math.max(0, maximumXP - currentXP) or 0
    local xpPerSecond = s.xp / divisor
    row.goldRate:SetText(EUI.Lf("%s / hr", Money(gross / divisor * 3600)))
    row.goldTotal:SetText(SessionMoney(net))
    row.mountETA:SetText(EUI.Lf("%dg mount: %s", mountCost / COPPER_PER_GOLD, mountTime))
    row.xpRate:SetText(EUI.Lf("%s / hr", XP(s.xp / divisor * 3600)))
    row.xpTotal:SetText(XP(s.xp))
    row.xpETA:SetText(EUI.Lf("Next level: %s", EstimatedDuration(xpRemaining, xpPerSecond)))
    row:Show()
end

local function InstallHooks()
    if hooksInstalled then return end
    local loot = NativeLoot()
    if not loot or type(hooksecurefunc) ~= "function" then return end
    if type(loot.Apply) == "function" then
        hooksecurefunc(loot, "Apply", function() C_Timer.After(0, PaintSummary) end)
    end
    if type(loot.ApplyStyle) == "function" then
        hooksecurefunc(loot, "ApplyStyle", function() C_Timer.After(0, PaintSummary) end)
    end
    hooksInstalled = true
end

function ns.ResetLootSession()
    CommitElapsed(true)
    local db = RawDB()
    db.lootSessions = type(db.lootSessions) == "table" and db.lootSessions or {}
    stateKey = CharacterKey() or stateKey
    state = EmptyState()
    if stateKey then db.lootSessions[stateKey] = state end
    local legacyKey = LegacyCharacterKey()
    if legacyKey and legacyKey ~= stateKey then db.lootSessions[legacyKey] = state end
    if tracking then SetBaselines() end
    PaintSummary()
end

function ns.ApplyLootSessionTracker()
    InstallHooks()
    SyncTracking()
    C_Timer.After(0, PaintSummary)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("CHAT_MSG_MONEY")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGOUT" then
        CommitElapsed(true)
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            InstallHooks()
            SyncTracking()
            PaintSummary()
        end)
        return
    end
    SyncTracking()
    if not tracking then return end
    if event == "CHAT_MSG_MONEY" then
        local text = Plain((...), "string")
        if text then TrackMoneyGain(text) end
    elseif event == "CHAT_MSG_LOOT" then
        local text = Plain((...), "string")
        if text then TrackLoot(text) end
    elseif event == "PLAYER_MONEY" then
        TrackWallet()
    elseif event == "PLAYER_XP_UPDATE" then
        local unit = ...
        if not unit or unit == "player" then TrackExperience() end
    end
    PaintSummary()
end)

updateTicker = C_Timer.NewTicker(5, function()
    InstallHooks()
    SyncTracking()
    if tracking and SessionState().started and GetTime() - lastCommit >= COMMIT_INTERVAL then
        CommitElapsed(false)
    end
    PaintSummary()
end)
