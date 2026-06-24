-------------------------------------------------------------------------------
--  EllesmereUIQoL_AdvancedDebuffs.lua
--  Player debuff tracker. Reads the player's HARMFUL auras via C_UnitAuras and
--  lays them out as a freely-movable grid of custom icons (size / spacing /
--  rows / grow direction), with dispel-type colored borders, a Bloodlust
--  filter, Blizzard filter toggles, stack text and a preview mode.
--
--  SECRET-VALUE SAFE: modern WoW returns "secret values" for boss / restricted
--  aura fields (spellId, duration, applications, dispelName) when read by
--  tainted addon code. Those CANNOT be compared / arithmetic'd / used as table
--  keys -- doing so throws. So display values are produced through the
--  secret-safe C_UnitAuras helpers (duration object -> SetCooldownFromDuration-
--  Object, GetAuraApplicationDisplayCount) and every direct field read is
--  guarded with issecretvalue(). auraInstanceID is a plain handle and is safe.
--
--  Modeled on EllesmereUIQoL_BattleRes.lua (same DB / Apply / unlock-mode /
--  shape-and-border conventions), extended from a single icon to a button pool.
-------------------------------------------------------------------------------

local SHAPE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
local SHAPE_MASKS = {
    circle   = SHAPE_MEDIA .. "circle_mask.tga",
    csquare  = SHAPE_MEDIA .. "csquare_mask.tga",
    diamond  = SHAPE_MEDIA .. "diamond_mask.tga",
    hexagon  = SHAPE_MEDIA .. "hexagon_mask.tga",
    portrait = SHAPE_MEDIA .. "portrait_mask.tga",
    shield   = SHAPE_MEDIA .. "shield_mask.tga",
    square   = SHAPE_MEDIA .. "square_mask.tga",
}
local SHAPE_BORDERS = {
    circle   = SHAPE_MEDIA .. "circle_border.tga",
    csquare  = SHAPE_MEDIA .. "csquare_border.tga",
    diamond  = SHAPE_MEDIA .. "diamond_border.tga",
    hexagon  = SHAPE_MEDIA .. "hexagon_border.tga",
    portrait = SHAPE_MEDIA .. "portrait_border.tga",
    shield   = SHAPE_MEDIA .. "shield_border.tga",
    square   = SHAPE_MEDIA .. "square_border.tga",
}
local BORDER_PX = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }

-- Per-dispel-type border colors (mirrors the DISPEL_COLORS table used by
-- EllesmereUIRaidFrames / Nameplates). The "" key is the no-dispelName /
-- physical (bleed) type, also used as the fallback for secret dispel types.
local DISPEL_COLORS = {
    Magic   = { r = 0.349, g = 0.475, b = 1.0 },
    Curse   = { r = 0.636, g = 0.0,   b = 0.64 },
    Disease = { r = 0.671, g = 0.384, b = 0.098 },
    Poison  = { r = 0.0,   g = 0.706, b = 0.286 },
    [""]    = { r = 0.75,  g = 0.15,  b = 0.15 },
}

-- Bloodlust / Heroism family (plus the related exhaustion/fatigue debuffs).
-- Hidden when the "Filter Bloodlust Debuffs" toggle is on. Ported from the
-- reference addon's default blocklist.
local BLOODLUST_IDS = {
    [390435] = true,  -- Bloodlust
    [57723]  = true,  -- Exhaustion (Heroism)
    [95809]  = true,  -- Insanity (Hunter)
    [80354]  = true,  -- Temporal Displacement
    [308312] = true,  -- Time Trial
    [57724]  = true,  -- Sated
    [160455] = true,  -- Fatigued
    [264689] = true,  -- Fatigued (Hunter)
}

-- Blizzard aura filter categories. When toggled on, auras matching the category
-- are excluded (same semantics as the reference addon's filter list).
local FILTER_NAMES = {
    "PLAYER", "RAID", "INCLUDE_NAME_PLATE_ONLY", "CROWD_CONTROL",
    "RAID_IN_COMBAT", "RAID_PLAYER_DISPELLABLE", "IMPORTANT",
}

-- Preview spells (icon resolved at runtime; dispelName drives border color).
local PREVIEW_DEFS = {
    { spell = 589,    dispelName = "Magic",   dur = 18, count = 0 },
    { spell = 980,    dispelName = "Curse",   dur = 30, count = 3 },
    { spell = 8680,   dispelName = "Poison",  dur = 12, count = 0 },
    { spell = 146739, dispelName = "Disease", dur = 24, count = 0 },
    { spell = 703,    dispelName = "",        dur = 10, count = 0 },
    { spell = 1943,   dispelName = "",        dur = 16, count = 5 },
}

-- Sits under EllesmereUIQoLDB.profile.advancedDebuffs so it never clobbers the
-- cursor / brez / QoL data already stored in that SavedVariable.
local defaults = {
    profile = {
        -- First-run defaults mirror the reference addon's DebuffTracking block
        -- (atrocityEssentials Core/Defaults.lua): big icons, single row growing
        -- left/down, dispel-colored borders, reverse swipe, and the PLAYER
        -- filter on so your own self-applied debuffs are hidden by default.
        advancedDebuffs = {
            enabled        = false,   -- opt-in; everything below is tuned for when it's on
            hideBlizzard   = true,    -- hide Blizzard's DebuffFrame while enabled (avoids doubles)
            -- layout (grid)
            iconSize       = 52,
            iconSpacing    = 1,
            iconsPerRow    = 5,
            maxRows        = 1,
            growHorizontal = "LEFT",  -- LEFT | RIGHT
            growVertical   = "DOWN",  -- DOWN | UP
            -- appearance (shape system shared with BattleRes)
            shape          = "none",
            iconZoom       = 11,      -- percent
            borderSize     = "thin",  -- none / thin / normal / heavy / strong
            borderMode     = "dispel",-- dispel | custom
            borderColor    = { r = 0.8, g = 0, b = 0, a = 1 },
            -- text / cooldown
            showDuration   = true,    -- show Blizzard's built-in cooldown countdown
            countSize      = 14,
            countOffsetX   = 0,
            countOffsetY   = 0,
            swipe          = true,
            reverse        = true,
            -- filtering
            filters        = { PLAYER = true },  -- hide self-cast debuffs by default
            filterBloodlust = true,   -- hide the Bloodlust / Heroism debuff family
            -- position
            pos            = nil,     -- { centerX, centerY } stored after first move
        },
    },
}

local addon = {}
addon.db = nil
local function P()
    return addon.db and addon.db.profile and addon.db.profile.advancedDebuffs
end

local frame                 -- container
local pool = {}             -- button pool
local renderList = {}       -- scratch list of auras to show
local _filterStrings = {}   -- scratch filter strings
local previewActive = false
local _blizzHidden = false

local C_UA = C_UnitAuras

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function _isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-------------------------------------------------------------------------------
--  Button creation + styling
-------------------------------------------------------------------------------
local function CreateAuraButton(parent)
    local b = CreateFrame("Button", nil, parent)

    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetAllPoints(b)

    b.borderTex = b:CreateTexture(nil, "OVERLAY")  -- custom-shape border overlay
    b.borderTex:Hide()

    b.Cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.Cooldown:SetAllPoints(b)
    b.Cooldown:SetDrawEdge(false)
    b.Cooldown:SetFrameLevel(b:GetFrameLevel() + 1)

    -- Stack count (we render this one ourselves; the value comes from a
    -- secret-safe display API so SetText never touches a secret directly).
    b.Count = b.Cooldown:CreateFontString(nil, "OVERLAY")

    b:SetScript("OnEnter", function(self)
        if previewActive or not self._auraInstanceID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetUnitDebuffByAuraInstanceID then
            GameTooltip:SetUnitDebuffByAuraInstanceID("player", self._auraInstanceID)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return b
end

-- Static styling (shape / zoom / border existence / fonts). Depends only on the
-- profile, not on the aura, so it runs on Apply and once per new button.
local function StyleButton(b, p)
    local PP = EllesmereUI and EllesmereUI.PP
    local shape = p.shape or "none"
    local bs = BORDER_PX[p.borderSize or "thin"] or 1
    local size = p.iconSize or 30

    b:SetSize(size, size)
    b.Icon:ClearAllPoints(); b.Icon:SetAllPoints(b)
    if b.Cooldown then
        b.Cooldown:ClearAllPoints(); b.Cooldown:SetAllPoints(b)
        b.Cooldown:SetDrawSwipe(p.swipe ~= false)
        b.Cooldown:SetReverse(p.reverse and true or false)
        b.Cooldown:SetHideCountdownNumbers(p.showDuration == false)
    end

    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT
    local flag = (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE"
    b.Count:SetFont(fontPath, p.countSize or 11, flag)
    b.Count:ClearAllPoints()
    b.Count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2 + (p.countOffsetX or 0), 2 + (p.countOffsetY or 0))

    b._shape = shape

    -- BASE CASE: "none" / "cropped" -- plain texture, PP pixel border.
    if shape == "none" or shape == "cropped" then
        if b._mask then
            if b.Cooldown and not b.Cooldown:IsForbidden() then
                pcall(b.Cooldown.RemoveMaskTexture, b.Cooldown, b._mask)
                if b.Cooldown.SetSwipeTexture then pcall(b.Cooldown.SetSwipeTexture, b.Cooldown, "") end
            end
            b.Icon:RemoveMaskTexture(b._mask)
            b._mask:SetTexture(nil)
            b._mask:Hide()
            b._mask = nil
        end
        b.borderTex:Hide()

        local z = (p.iconZoom or 11) / 100
        if shape == "cropped" then
            b.Icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif z > 0 then
            b.Icon:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            b.Icon:SetTexCoord(0, 1, 0, 1)
        end

        if PP then
            if not PP.GetBorders(b) then PP.CreateBorder(b, 0, 0, 0, 1, 1, "OVERLAY", 2) end
            if bs > 0 then
                if PP.SetBorderSize then PP.SetBorderSize(b, bs) end
                PP.ShowBorder(b)
            else
                PP.HideBorder(b)
            end
        end
        return
    end

    -- CUSTOM SHAPE: mask + shape-matching border overlay.
    if PP then PP.HideBorder(b) end

    local maskPath = SHAPE_MASKS[shape]
    if maskPath then
        if not b._mask then
            b._mask = b:CreateMaskTexture()
            b._mask:SetAllPoints(b.Icon)
            b.Icon:AddMaskTexture(b._mask)
        end
        b._mask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        b._mask:Show()
        b.Icon:SetTexCoord(0, 1, 0, 1)
        if b.Cooldown and not b.Cooldown:IsForbidden() then
            pcall(b.Cooldown.AddMaskTexture, b.Cooldown, b._mask)
            if b.Cooldown.SetSwipeTexture then pcall(b.Cooldown.SetSwipeTexture, b.Cooldown, maskPath) end
        end
    end

    local borderPath = SHAPE_BORDERS[shape]
    if borderPath and bs > 0 then
        b.borderTex:SetTexture(borderPath)
        b.borderTex:ClearAllPoints()
        b.borderTex:SetPoint("TOPLEFT", b, "TOPLEFT", -bs, bs)
        b.borderTex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", bs, -bs)
        b.borderTex:Show()
    else
        b.borderTex:Hide()
    end
end

-- Per-aura border color. Secret-safe: dispelName is only read through a
-- table lookup after confirming it is a plain (non-secret) value; otherwise we
-- fall back to the neutral/physical color.
local function ApplyBorderColor(b, p, dispelName)
    local r, g, bl, a
    if (p.borderMode or "dispel") == "custom" then
        local c = p.borderColor
        r, g, bl, a = (c and c.r) or 0, (c and c.g) or 0, (c and c.b) or 0, (c and c.a) or 1
    else
        local c
        if dispelName ~= nil and not _isSecret(dispelName) and DISPEL_COLORS[dispelName] then
            c = DISPEL_COLORS[dispelName]
        else
            c = DISPEL_COLORS[""]
        end
        r, g, bl, a = c.r, c.g, c.b, 1
    end

    local shape = b._shape or "none"
    if shape == "none" or shape == "cropped" then
        local PP = EllesmereUI and EllesmereUI.PP
        if PP and PP.GetBorders(b) then PP.SetBorderColor(b, r, g, bl, a) end
    elseif b.borderTex:IsShown() then
        b.borderTex:SetVertexColor(r, g, bl, a)
    end
end

-- `aura` carries auraInstanceID (a plain handle) + icon. Everything else is
-- fetched through secret-safe APIs (live) or read from the plain preview table.
local function UpdateAuraButton(b, aura, p)
    local id = aura.auraInstanceID
    b._auraInstanceID = id
    b.Icon:SetTexture(aura.icon)

    if previewActive then
        -- Preview data is plain; safe to read/compare directly.
        local cnt = aura.count or 0
        b.Count:SetText((cnt and cnt > 1) and cnt or "")
        if aura.duration and aura.duration > 0 and aura.expirationTime then
            b.Cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
            b.Cooldown:Show()
        else
            b.Cooldown:Clear()
        end
    else
        -- Stack count via the display API (returns "" / nil below the min).
        local cnt = C_UA and C_UA.GetAuraApplicationDisplayCount
            and C_UA.GetAuraApplicationDisplayCount("player", id, 2, 999)
        b.Count:SetText(cnt or "")

        -- Duration via the opaque duration object (never read in Lua).
        local durObj = C_UA and C_UA.GetAuraDuration and C_UA.GetAuraDuration("player", id)
        if durObj and b.Cooldown.SetCooldownFromDurationObject then
            b.Cooldown:SetCooldownFromDurationObject(durObj)
            b.Cooldown:Show()
        else
            b.Cooldown:Clear()
        end
    end

    ApplyBorderColor(b, p, aura.dispelName)
    b:Show()
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
local function GetGridSize(p)
    p = p or {}
    local size    = p.iconSize    or 30
    local spacing = p.iconSpacing or 4
    local perRow  = p.iconsPerRow or 8
    local rows    = p.maxRows     or 2
    local w = perRow * size + (perRow - 1) * spacing
    local h = rows * size + (rows - 1) * spacing
    return w, h
end

local function PositionButtons(p)
    local size    = p.iconSize    or 30
    local spacing = p.iconSpacing or 4
    local perRow  = p.iconsPerRow or 8
    local growH   = (p.growHorizontal == "RIGHT") and 1 or -1
    local growV   = (p.growVertical   == "UP")    and 1 or -1
    -- Anchor the grid at the corner opposite the growth direction so the first
    -- icon sits in that corner and the grid grows inward.
    local anchor = (growV == 1 and "BOTTOM" or "TOP") .. (growH == 1 and "LEFT" or "RIGHT")
    local step = size + spacing

    local shown = 0
    for i = 1, #pool do
        local b = pool[i]
        if b:IsShown() then
            local col = shown % perRow
            local row = math.floor(shown / perRow)
            b:ClearAllPoints()
            b:SetPoint(anchor, frame, anchor, col * step * growH, row * step * growV)
            shown = shown + 1
        end
    end
end

local function RenderList(list, p)
    local maxVisible = (p.iconsPerRow or 8) * (p.maxRows or 2)
    local n = math.min(#list, maxVisible)
    while #pool < n do
        local b = CreateAuraButton(frame)
        StyleButton(b, p)
        pool[#pool + 1] = b
    end
    for i = 1, #pool do
        local b = pool[i]
        if i <= n then
            UpdateAuraButton(b, list[i], p)
        else
            b:Hide()
        end
    end
    PositionButtons(p)
end

-------------------------------------------------------------------------------
--  Filtering + aura gathering
-------------------------------------------------------------------------------
local function BuildFilterStrings(p)
    wipe(_filterStrings)
    if p.filters then
        for _, name in ipairs(FILTER_NAMES) do
            if p.filters[name] then
                _filterStrings[#_filterStrings + 1] = "HARMFUL|" .. name
            end
        end
    end
    return _filterStrings
end

local function ShouldShow(aura, p, filterStrings)
    if not aura then return false end

    -- Bloodlust/Heroism filter -- only when the spellID is a plain (non-secret)
    -- value; secret-tagged auras (boss / restricted) can't be matched.
    if p.filterBloodlust then
        local sid = aura.spellId
        if sid ~= nil and not _isSecret(sid) and BLOODLUST_IDS[sid] then
            return false
        end
    end

    if filterStrings and #filterStrings > 0 and aura.auraInstanceID
        and C_UA and C_UA.IsAuraFilteredOutByInstanceID then
        for _, f in ipairs(filterStrings) do
            local out = C_UA.IsAuraFilteredOutByInstanceID("player", aura.auraInstanceID, f)
            if not _isSecret(out) and out == false then
                return false  -- aura matches an excluded category
            end
        end
    end

    return true
end

local function RefreshAuras()
    if previewActive then return end
    if not frame or not addon.db then return end
    local p = P()
    if not p or not p.enabled then return end

    wipe(renderList)
    local filterStrings = BuildFilterStrings(p)

    if AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura("player", "HARMFUL", nil, function(aura)
            if aura and ShouldShow(aura, p, filterStrings) then
                renderList[#renderList + 1] = aura
            end
        end, true)
    end

    -- auraInstanceID is a plain handle (non-secret), safe to sort on.
    table.sort(renderList, function(a, b)
        return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
    end)

    RenderList(renderList, p)
end

-------------------------------------------------------------------------------
--  Position
-------------------------------------------------------------------------------
local function ApplyPosition()
    if not frame then return end
    local p = P()
    if not p then return end
    local pos = p.pos
    frame:ClearAllPoints()
    if pos and pos.centerX and pos.centerY then
        frame:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
end

local function SavePosition()
    if not frame or not addon.db then return end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end
    local fw, fh = frame:GetSize()
    local cx = left + fw / 2 - UIParent:GetWidth() / 2
    local cy = bottom + fh / 2 - UIParent:GetHeight() / 2
    local p = P(); if p then p.pos = { centerX = cx, centerY = cy } end
end

-------------------------------------------------------------------------------
--  Blizzard DebuffFrame hide (alpha-based: reversible, low taint)
-------------------------------------------------------------------------------
local function ApplyBlizzardHide(p)
    local df = _G.DebuffFrame
    if not df then return end
    local want = p and p.enabled and p.hideBlizzard
    if want then
        if not _blizzHidden then
            df:SetAlpha(0)
            if df.SetMouseClickEnabled then df:SetMouseClickEnabled(false) end
            _blizzHidden = true
        end
    elseif _blizzHidden then
        df:SetAlpha(1)
        if df.SetMouseClickEnabled then df:SetMouseClickEnabled(true) end
        _blizzHidden = false
    end
end

-------------------------------------------------------------------------------
--  Visibility
-------------------------------------------------------------------------------
local function UpdateVisibility(p)
    p = p or P()
    if not frame then return end
    if previewActive then
        frame:Show()
        return
    end
    if p and p.enabled then
        frame:Show()
    else
        frame:Hide()
    end
end

-------------------------------------------------------------------------------
--  Frame creation
-------------------------------------------------------------------------------
local function CreateContainer()
    if frame then return frame end
    frame = CreateFrame("Frame", "EllesmereUIAdvancedDebuffs", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(GetGridSize(P()))
    frame:Hide()
    return frame
end

-------------------------------------------------------------------------------
--  Preview
-------------------------------------------------------------------------------
local function ShowPreview()
    if not frame then CreateContainer() end
    local p = P(); if not p then return end
    previewActive = true

    local w, h = GetGridSize(p)
    frame:SetSize(w, h)
    for i = 1, #pool do StyleButton(pool[i], p) end

    local list = {}
    local now = GetTime()
    for i, e in ipairs(PREVIEW_DEFS) do
        local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.spell)) or 134400
        list[i] = {
            icon           = icon,
            count          = e.count or 0,
            dispelName     = e.dispelName,
            duration       = e.dur,
            expirationTime = now + e.dur,
            auraInstanceID = -i,
            spellId        = e.spell,
        }
    end
    RenderList(list, p)
    frame:Show()
end
_G._EUI_AdvancedDebuffs_ShowPreview = ShowPreview

local function HidePreview()
    previewActive = false
    RefreshAuras()
    UpdateVisibility()
end
_G._EUI_AdvancedDebuffs_HidePreview = HidePreview

_G._EUI_AdvancedDebuffs_IsPreviewActive = function() return previewActive end

-------------------------------------------------------------------------------
--  Apply (settings entry point)
-------------------------------------------------------------------------------
local function Apply()
    if not addon.db then return end
    if not frame then CreateContainer() end
    local p = P(); if not p then return end

    local w, h = GetGridSize(p)
    frame:SetSize(w, h)
    for i = 1, #pool do StyleButton(pool[i], p) end

    ApplyPosition()
    ApplyBlizzardHide(p)
    UpdateVisibility(p)

    if previewActive then
        ShowPreview()
    else
        RefreshAuras()
    end
end
_G._EUI_AdvancedDebuffs_Apply = Apply

-- Reset every setting back to defaults (used by the QoL panel's reset button).
local function ResetDefaults()
    local p = P(); if not p then return end
    previewActive = false
    wipe(p)
    for k, v in pairs(defaults.profile.advancedDebuffs) do
        if type(v) == "table" then
            local t = {}
            for k2, v2 in pairs(v) do t[k2] = v2 end
            p[k] = t
        else
            p[k] = v
        end
    end
    Apply()
end
_G._EUI_AdvancedDebuffs_Reset = ResetDefaults

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local _eventFrame
local function _registerEvents()
    if _eventFrame then return end
    _eventFrame = CreateFrame("Frame")
    _eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    _eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _eventFrame:SetScript("OnEvent", function()
        if previewActive then return end
        RefreshAuras()
    end)
end

-------------------------------------------------------------------------------
--  Unlock mode registration
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end

    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EUI_AdvancedDebuffs",
            label = "Advanced Debuffs",
            group = "Quality of Life",
            order = 605,
            noResize = true,        -- grid size is driven by the options sliders
            noAnchorTarget = true,  -- size changes; nothing should anchor to it
            isHidden = function()
                local p = P()
                return not p or not p.enabled
            end,
            getFrame = function()
                if not frame then CreateContainer() end
                return frame
            end,
            getSize = function()
                return GetGridSize(P())
            end,
            savePos = function(_, point, relPoint, x, y)
                local p = P(); if not p then return end
                if frame and frame:GetLeft() then
                    SavePosition()
                else
                    p.pos = { centerX = x, centerY = y }
                end
            end,
            loadPos = function()
                local p = P()
                if p and p.pos then
                    return { point = "CENTER", relPoint = "CENTER", x = p.pos.centerX, y = p.pos.centerY }
                end
                return nil
            end,
            clearPos = function()
                local p = P(); if p then p.pos = nil end
            end,
            applyPos = function()
                ApplyPosition()
            end,
        }),
    })
end
_G._EUI_AdvancedDebuffs_RegisterUnlock = RegisterUnlock

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not EllesmereUI or not EllesmereUI.Lite or not EllesmereUI.Lite.NewDB then
        return
    end
    addon.db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", defaults, true)
    _G._EUI_AdvancedDebuffs_DB = function() return addon.db end
    CreateContainer()
    _registerEvents()
    Apply()
    RegisterUnlock()
end)
