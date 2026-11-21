-------------------------------------------------------------------------------
-- Crafted-item icon for EllesmereUI's player cast bar.
--
-- Blizzard exposes the exact recipe ID through TRADE_SKILL_CRAFT_BEGIN, while
-- UnitCastingInfo supplies only the generic profession spell icon on Forever.
-- Resolve the profession pane's recipe/output icon and repaint only casts the
-- client itself identifies as trade skills.  Ellesmere remains the owner of
-- the cast bar, its layout, and every non-crafting icon.
-------------------------------------------------------------------------------
local _, ns = ...

local activeRecipe
local hookedBars = setmetatable({}, { __mode = "k" })
local events = CreateFrame("Frame")

local function IsSecret(value)
    return _G.issecretvalue and _G.issecretvalue(value)
end

local function UsableTexture(texture)
    if IsSecret(texture) or texture == nil then return end
    local kind = type(texture)
    if kind == "number" then
        return texture > 0 and texture or nil
    elseif kind == "string" then
        return texture ~= "" and texture or nil
    end
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then return end
    local ok, result = pcall(func, ...)
    if ok and not IsSecret(result) then return result end
end

-- The profession list paints recipeInfo.icon directly, so it is the authority
-- for the icon the player saw before pressing Create.  Forever can return an
-- unrelated icon from GetRecipeOutputItemData when that function is called
-- without the profession form's reagent transaction (Roasted Boar Meat is one
-- known example), so output data is deliberately only a fallback here.
local function ResolveRecipeIcon(recipeID)
    if IsSecret(recipeID) or recipeID == nil then return end
    local trade = _G.C_TradeSkillUI
    if not trade then return end

    local info = SafeCall(trade.GetRecipeInfo, recipeID)
    local icon = type(info) == "table" and UsableTexture(info.icon)
    if icon then return icon end

    local recraftValue = type(info) == "table" and info.isRecraft or nil
    local isRecraft = not IsSecret(recraftValue) and recraftValue == true or false
    local recipeLevel = type(info) == "table" and info.unlockedRecipeLevel or nil
    if IsSecret(recipeLevel) then recipeLevel = nil end
    local schematic = SafeCall(trade.GetRecipeSchematic, recipeID, isRecraft, recipeLevel)
    icon = type(schematic) == "table" and UsableTexture(schematic.icon)
    if icon then return icon end

    local output = SafeCall(trade.GetRecipeOutputItemData, recipeID)
    icon = type(output) == "table" and UsableTexture(output.icon)
    if icon then return icon end

    local itemID = type(output) == "table" and output.itemID
        or type(schematic) == "table" and schematic.outputItemID
    if not IsSecret(itemID) and itemID ~= nil and C_Item and C_Item.GetItemIconByID then
        return UsableTexture(SafeCall(C_Item.GetItemIconByID, itemID))
    end
end

local function RefreshRecipeIcon(ticket)
    if activeRecipe ~= ticket then return end
    ticket.icon = ResolveRecipeIcon(ticket.recipeID) or ticket.icon
    if ticket.icon and ns.ApplyCraftingCastIcon then
        ns.ApplyCraftingCastIcon(true)
    end
end

local function CaptureRecipe(recipeID)
    if IsSecret(recipeID) or recipeID == nil then return end
    local ticket = {
        recipeID = recipeID,
        expires = GetTime() + 900,
    }
    activeRecipe = ticket
    RefreshRecipeIcon(ticket)

    -- Item information can arrive one frame after the craft-begin event.
    if not ticket.icon then
        C_Timer.After(0, function() RefreshRecipeIcon(ticket) end)
        C_Timer.After(0.20, function() RefreshRecipeIcon(ticket) end)
    end
end

local function PlayerIsCrafting()
    local ok, result = pcall(function()
        local name, _, _, _, _, isTradeSkill = UnitCastingInfo("player")
        if name == nil then
            name, _, _, _, _, isTradeSkill = UnitChannelInfo("player")
        end
        return name ~= nil and isTradeSkill == true
    end)
    return ok and result == true
end

local function PlayerCastBar()
    local player = _G.EllesmereUIUnitFrames_Player
    return player and player.Castbar
end

local function PaintCraftIcon(bar)
    local ticket = activeRecipe
    if not ns.Get("useCraftedItemIcon") or not ticket or not ticket.icon then return end
    if GetTime() > ticket.expires or not PlayerIsCrafting() then return end

    bar = bar or PlayerCastBar()
    if not (bar and bar.Icon and bar.Icon.SetTexture) then return end
    bar.Icon:SetTexture(ticket.icon)

    -- A batch can run for much longer than a single cast.  Every verified
    -- trade-skill repaint renews the fallback lifetime; Blizzard's explicit
    -- cast-stopped event normally clears the recipe first.
    ticket.expires = GetTime() + 900
end

local function HookPlayerCastBar()
    local bar = PlayerCastBar()
    if not bar or hookedBars[bar] then return end

    local originalStart = bar.PostCastStart
    local originalChannel = bar.PostChannelStart
    local wrappedStart = function(self, ...)
        if originalStart then originalStart(self, ...) end
        PaintCraftIcon(self)
    end
    local wrappedChannel
    if originalChannel == originalStart or originalChannel == nil then
        wrappedChannel = wrappedStart
    else
        wrappedChannel = function(self, ...)
            originalChannel(self, ...)
            PaintCraftIcon(self)
        end
    end

    bar.PostCastStart = wrappedStart
    bar.PostChannelStart = wrappedChannel
    hookedBars[bar] = true
end

function ns.ApplyCraftingCastIcon(repaint)
    HookPlayerCastBar()
    if repaint then PaintCraftIcon() end
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("TRADE_SKILL_CRAFT_BEGIN")
events:RegisterEvent("UPDATE_TRADESKILL_CAST_STOPPED")
events:RegisterEvent("UNIT_SPELLCAST_START")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:SetScript("OnEvent", function(_, event, unitOrRecipe)
    if event == "TRADE_SKILL_CRAFT_BEGIN" then
        CaptureRecipe(unitOrRecipe)
        return
    end
    if event == "UPDATE_TRADESKILL_CAST_STOPPED" then
        activeRecipe = nil
        return
    end
    if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if unitOrRecipe == "player" then activeRecipe = nil end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        activeRecipe = nil
        C_Timer.After(0, HookPlayerCastBar)
        return
    end
    if unitOrRecipe == "player" then
        -- Run after Ellesmere's cast driver has assigned the generic icon.
        C_Timer.After(0, function()
            HookPlayerCastBar()
            PaintCraftIcon()
        end)
    end
end)
