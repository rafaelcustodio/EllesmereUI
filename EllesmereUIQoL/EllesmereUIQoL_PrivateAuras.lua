-------------------------------------------------------------------------------
--  EllesmereUIQoL_PrivateAuras.lua
--  Private Aura Monitor. Private auras are a restricted Blizzard system (boss
--  mechanics) whose data addons CANNOT read. The only way to show them is to
--  hand Blizzard an anchor frame via C_UnitAuras.AddPrivateAuraAnchor -- Blizzard
--  then renders the (otherwise invisible) icon into our frame. We only control
--  position, size, border scale and the cooldown frame/numbers; the icon art,
--  shape, zoom and border color are owned by Blizzard and cannot be changed.
--
--  Layout mirrors Advanced Debuffs (configurable grid: size / spacing / icons
--  per row / rows / grow H+V). Anchors can only be added/removed OUT of combat,
--  so every (re)apply is gated by InCombatLockdown and deferred to
--  PLAYER_REGEN_ENABLED when needed.
-------------------------------------------------------------------------------

local HARD_CAP = 24  -- safety cap on grid cells / private-aura anchors

-- Sample spells + per-slot durations used only by the preview, so it looks like
-- real auras (real icons + animated, looping cooldowns) instead of static art.
local PREVIEW_SPELLS = { 589, 980, 8680, 146739, 1943 }
local PREVIEW_DURS   = { 16, 22, 12, 28, 19 }

local defaults = {
    profile = {
        privateAuras = {
            enabled         = false,
            -- layout (grid) -- same options as Advanced Debuffs
            iconSize        = 40,
            iconSpacing     = 6,
            iconsPerRow     = 3,
            maxRows         = 1,
            growHorizontal  = "RIGHT",  -- LEFT | RIGHT
            growVertical    = "DOWN",   -- DOWN | UP
            -- border / cooldown (only what the anchor API exposes)
            showBorder      = true,
            borderScale     = 1.0,
            showCountdown   = true,     -- cooldown swipe frame
            showNumbers     = true,     -- countdown numbers
            durationOffsetX = 0,
            durationOffsetY = 0,
            pos             = nil,      -- { centerX, centerY } stored after first move
        },
    },
}

local addon = {}
addon.db = nil
local function P()
    return addon.db and addon.db.profile and addon.db.profile.privateAuras
end

local rootFrame                 -- movable container (the unlock-mode anchor)
local slotFrames    = {}        -- real frames the icons render into (grows on demand)
local previewFrames = {}        -- fake icons for positioning (grows on demand)
local anchorIDs     = {}        -- active private-aura anchor IDs
local pendingApply  = false
local previewActive = false
local _previewGen   = 0         -- bumped to invalidate stale preview-cooldown timers
local _previewTextTicker

local C_UA = C_UnitAuras

-------------------------------------------------------------------------------
--  Layout (configurable grid, anchored at the corner opposite the growth
--  direction -- identical to Advanced Debuffs)
-------------------------------------------------------------------------------
local function SlotCount(p)
    local perRow = math.max(1, p.iconsPerRow or 3)
    local rows   = math.max(1, p.maxRows or 1)
    return math.min(perRow * rows, HARD_CAP)
end

local function GetGridSize(p)
    p = p or {}
    local size    = p.iconSize    or 40
    local spacing = p.iconSpacing or 6
    local perRow  = math.max(1, p.iconsPerRow or 3)
    local rows    = math.max(1, p.maxRows or 1)
    local w = perRow * size + (perRow - 1) * spacing
    local h = rows * size + (rows - 1) * spacing
    return w, h
end

local function GridAnchor(p)
    local growH = (p.growHorizontal == "RIGHT") and 1 or -1
    local growV = (p.growVertical   == "UP")    and 1 or -1
    local anchor = (growV == 1 and "BOTTOM" or "TOP") .. (growH == 1 and "LEFT" or "RIGHT")
    return anchor, growH, growV
end

local function GridOffset(p, idx, growH, growV)
    local size    = p.iconSize    or 40
    local spacing = p.iconSpacing or 6
    local perRow  = math.max(1, p.iconsPerRow or 3)
    local step = size + spacing
    local col = (idx - 1) % perRow
    local row = math.floor((idx - 1) / perRow)
    return col * step * growH, row * step * growV
end

-------------------------------------------------------------------------------
--  Frame creation (slot + preview frames are created on demand)
-------------------------------------------------------------------------------
local function MakePreviewFrame(parent)
    local PP = EllesmereUI and EllesmereUI.PP
    local pf = CreateFrame("Frame", nil, parent)
    pf:EnableMouse(false)
    pf.tex = pf:CreateTexture(nil, "ARTWORK")
    pf.tex:SetAllPoints(pf)
    pf.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim the icon's stock border
    if PP then PP.CreateBorder(pf, 0, 0, 0, 1, 1, "OVERLAY", 2) end

    -- Cooldown draws the SWIPE only; we render the timer ourselves so the swipe
    -- and the numbers are independent (and the numbers can be offset freely).
    pf.cd = CreateFrame("Cooldown", nil, pf, "CooldownFrameTemplate")
    pf.cd:SetAllPoints(pf)
    pf.cd:SetDrawEdge(false)
    pf.cd:SetHideCountdownNumbers(true)
    pf.cd:Hide()

    pf.textHost = CreateFrame("Frame", nil, pf)
    pf.textHost:SetAllPoints(pf)
    pf.textHost:SetFrameLevel(pf.cd:GetFrameLevel() + 5)
    pf.timer = pf.textHost:CreateFontString(nil, "OVERLAY")
    pf.timer:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT, 12,
        (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE")
    pf.timer:SetText("")

    pf:Hide()
    return pf
end

local function EnsureRoot()
    if not rootFrame then
        rootFrame = CreateFrame("Frame", "EllesmereUIPrivateAuras", UIParent)
        rootFrame:SetFrameStrata("MEDIUM")
        rootFrame:SetSize(GetGridSize(P()))
        rootFrame:EnableMouse(false)
    end
end

local function EnsureSlot(i)
    EnsureRoot()
    if not slotFrames[i] then
        local f = CreateFrame("Frame", nil, rootFrame)
        f:EnableMouse(false)
        slotFrames[i] = f
    end
    if not previewFrames[i] then
        previewFrames[i] = MakePreviewFrame(slotFrames[i])
        local sp = PREVIEW_SPELLS[((i - 1) % #PREVIEW_SPELLS) + 1]
        local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sp)) or 134400
        previewFrames[i].tex:SetTexture(tex)
    end
end

-- Kept for callers/back-compat: just makes sure the root exists.
local function EnsureFrames()
    EnsureRoot()
end

-------------------------------------------------------------------------------
--  Position
-------------------------------------------------------------------------------
local function ApplyPosition()
    if not rootFrame then return end
    local p = P(); if not p then return end
    local pos = p.pos
    rootFrame:ClearAllPoints()
    if pos and pos.centerX and pos.centerY then
        rootFrame:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
    else
        rootFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -250)
    end
end

local function SavePosition()
    if not rootFrame or not addon.db then return end
    local left, bottom = rootFrame:GetLeft(), rootFrame:GetBottom()
    if not left or not bottom then return end
    local fw, fh = rootFrame:GetSize()
    local cx = left + fw / 2 - UIParent:GetWidth() / 2
    local cy = bottom + fh / 2 - UIParent:GetHeight() / 2
    local p = P(); if p then p.pos = { centerX = cx, centerY = cy } end
end

-------------------------------------------------------------------------------
--  Slot layout (safe in combat) -- positions slot + preview frames in the grid
-------------------------------------------------------------------------------
local function LayoutSlots(p)
    local sz = p.iconSize or 40
    local n  = SlotCount(p)
    rootFrame:SetSize(GetGridSize(p))
    local anchor, growH, growV = GridAnchor(p)

    for i = 1, n do
        EnsureSlot(i)
        local ox, oy = GridOffset(p, i, growH, growV)
        local f = slotFrames[i]
        f:SetSize(sz, sz)
        f:ClearAllPoints()
        f:SetPoint(anchor, rootFrame, anchor, ox, oy)
        f:Show()
        previewFrames[i]:SetSize(sz, sz)
    end
    for i = n + 1, #slotFrames do
        if slotFrames[i] then slotFrames[i]:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Anchor management (out-of-combat only)
-------------------------------------------------------------------------------
local function RemoveAllAnchors()
    if C_UA and C_UA.RemovePrivateAuraAnchor then
        for i = 1, #anchorIDs do
            if anchorIDs[i] then pcall(C_UA.RemovePrivateAuraAnchor, anchorIDs[i]) end
        end
    end
    wipe(anchorIDs)
end

local function ApplyAnchors()
    EnsureRoot()
    local p = P(); if not p then return end

    -- Adding/removing private-aura anchors is restricted in combat.
    if InCombatLockdown and InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = false

    RemoveAllAnchors()
    LayoutSlots(p)
    ApplyPosition()

    if not (p.enabled and C_UA and C_UA.AddPrivateAuraAnchor) then
        rootFrame:Hide()
        return
    end
    rootFrame:Show()

    local sz       = p.iconSize or 40
    local bScale   = p.showBorder and (p.borderScale or 1.0) or -100
    local borderPx = (sz / 16) * bScale
    local n        = SlotCount(p)
    local dox, doy = p.durationOffsetX or 0, p.durationOffsetY or 0
    local hasOffset = (dox ~= 0 or doy ~= 0)  -- positions the numbers, not the swipe

    for i = 1, n do
        local f = slotFrames[i]
        local durationAnchor
        if hasOffset then
            durationAnchor = {
                point = "CENTER", relativeTo = f, relativePoint = "CENTER",
                offsetX = dox, offsetY = doy,
            }
        end
        local ok, id = pcall(C_UA.AddPrivateAuraAnchor, {
            unitToken            = "player",
            auraIndex            = i,
            parent               = f,
            showCountdownFrame   = p.showCountdown == true,
            showCountdownNumbers = p.showNumbers == true,
            isContainer          = false,
            iconInfo = {
                iconAnchor = {
                    point = "CENTER", relativeTo = f, relativePoint = "CENTER",
                    offsetX = 0, offsetY = 0,
                },
                iconWidth   = sz,
                iconHeight  = sz,
                borderScale = borderPx,
            },
            durationAnchor = durationAnchor,
        })
        if ok and id then anchorIDs[#anchorIDs + 1] = id end
    end
end

-------------------------------------------------------------------------------
--  Preview (fake icons -- real ones only appear when a private aura is active)
-------------------------------------------------------------------------------
local function HidePreviewFrames()
    for i = 1, #previewFrames do
        if previewFrames[i] then previewFrames[i]:Hide() end
    end
end

local function FormatTime(s)
    if not s or s <= 0 then return "" end
    if s >= 60 then return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60)) end
    if s >= 10 then return string.format("%d", math.floor(s)) end
    return string.format("%.1f", s)
end

-- Self-scheduling loop so each preview icon shows an animated, repeating
-- cooldown. The generation token invalidates timers from a previous render.
local function ArmSlotLoop(i, gen)
    if gen ~= _previewGen or not previewActive then return end
    local pf = previewFrames[i]
    if not pf or not pf:IsShown() then return end
    local dur = PREVIEW_DURS[((i - 1) % #PREVIEW_DURS) + 1] or 15
    pf._expiration = GetTime() + dur
    pf.cd:SetCooldown(GetTime(), dur)  -- drives the swipe; harmless when hidden
    C_Timer.After(dur, function() ArmSlotLoop(i, gen) end)
end

local function StartPreviewCooldowns(n)
    _previewGen = _previewGen + 1
    local gen = _previewGen
    for i = 1, n do
        ArmSlotLoop(i, gen)
    end
end

local function _updatePreviewText()
    if not previewActive then return end
    local p = P(); if not p then return end
    local n = SlotCount(p)
    for i = 1, n do
        local pf = previewFrames[i]
        if pf and pf.timer:IsShown() and pf._expiration then
            local rem = pf._expiration - GetTime()
            pf.timer:SetText(rem > 0 and FormatTime(rem) or "")
        end
    end
end

-- Full live render of the preview icons (real spell art + animated cooldowns).
local function RenderPreview(p)
    local PP = EllesmereUI and EllesmereUI.PP
    local sz = p.iconSize or 40
    local n  = SlotCount(p)
    local dox, doy = p.durationOffsetX or 0, p.durationOffsetY or 0

    LayoutSlots(p)
    ApplyPosition()
    rootFrame:Show()

    for i = 1, n do
        local f  = slotFrames[i]
        local pf = previewFrames[i]
        pf:ClearAllPoints()
        pf:SetSize(sz, sz)
        pf:SetPoint("CENTER", f, "CENTER", 0, 0)
        pf:SetFrameStrata("DIALOG")

        -- Border thickness scales with Border Scale (mirrors the real anchor's
        -- borderScale = iconSize/16 * scale), and reflects Show Border.
        if PP then
            if p.showBorder ~= false then
                if PP.SetBorderSize then
                    local bpx = math.max(1, math.min(8, math.floor((sz / 16) * (p.borderScale or 1.0) + 0.5)))
                    PP.SetBorderSize(pf, bpx)
                end
                PP.ShowBorder(pf)
            else
                PP.HideBorder(pf)
            end
        end

        -- Swipe covers the icon; timer is our own text, offset independently.
        local cd = pf.cd
        if p.showCountdown ~= false then
            cd:ClearAllPoints(); cd:SetAllPoints(pf)
            cd:SetDrawSwipe(true)
            cd:Show()
        else
            cd:Hide()
        end

        local tm = pf.timer
        tm:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
            math.max(8, math.floor(sz * 0.4 + 0.5)),
            (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE")
        tm:ClearAllPoints()
        tm:SetPoint("CENTER", pf, "CENTER", dox, doy)
        if p.showNumbers ~= false then tm:Show() else tm:SetText(""); tm:Hide() end

        pf:Show()
    end

    -- Hide any preview frames beyond the current count.
    for i = n + 1, #previewFrames do
        if previewFrames[i] then previewFrames[i]:Hide() end
    end

    StartPreviewCooldowns(n)
end

local function ShowPreview()
    EnsureRoot()
    local p = P(); if not p then return end
    previewActive = true
    RemoveAllAnchors()  -- don't run real anchors while previewing
    RenderPreview(p)
    if not _previewTextTicker then
        _previewTextTicker = C_Timer.NewTicker(0.1, _updatePreviewText)
    end
end
_G._EUI_PrivateAuras_ShowPreview = ShowPreview

local function HidePreview()
    previewActive = false
    _previewGen = _previewGen + 1  -- stop the looping preview cooldowns
    if _previewTextTicker then _previewTextTicker:Cancel(); _previewTextTicker = nil end
    HidePreviewFrames()
    ApplyAnchors()
end
_G._EUI_PrivateAuras_HidePreview = HidePreview

_G._EUI_PrivateAuras_IsPreviewActive = function() return previewActive end

-------------------------------------------------------------------------------
--  Apply (settings entry point)
-------------------------------------------------------------------------------
local function Apply()
    if not addon.db then return end
    EnsureRoot()
    if previewActive then
        RemoveAllAnchors()        -- preview overrides the real anchors
        RenderPreview(P())
    else
        ApplyAnchors()
    end
end
_G._EUI_PrivateAuras_Apply = Apply

local function ResetDefaults()
    local p = P(); if not p then return end
    previewActive = false
    _previewGen = _previewGen + 1
    if _previewTextTicker then _previewTextTicker:Cancel(); _previewTextTicker = nil end
    HidePreviewFrames()
    wipe(p)
    for k, v in pairs(defaults.profile.privateAuras) do
        p[k] = v
    end
    Apply()
end
_G._EUI_PrivateAuras_Reset = ResetDefaults

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local _eventFrame
local function _registerEvents()
    if _eventFrame then return end
    _eventFrame = CreateFrame("Frame")
    _eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingApply then ApplyAnchors() end
        else
            ApplyAnchors()  -- re-register anchors after zoning
        end
    end)
end

-------------------------------------------------------------------------------
--  Unlock mode registration (the new anchor)
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end

    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EUI_PrivateAuras",
            label = "Private Auras",
            group = "Quality of Life",
            order = 607,
            noResize = true,        -- size driven by the options sliders
            noAnchorTarget = true,
            isHidden = function()
                local p = P()
                return not p or not p.enabled
            end,
            getFrame = function()
                EnsureRoot()
                return rootFrame
            end,
            getSize = function()
                return GetGridSize(P())
            end,
            savePos = function(_, point, relPoint, x, y)
                local p = P(); if not p then return end
                if rootFrame and rootFrame:GetLeft() then
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
_G._EUI_PrivateAuras_RegisterUnlock = RegisterUnlock

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
    _G._EUI_PrivateAuras_DB = function() return addon.db end
    EnsureRoot()
    _registerEvents()
    Apply()
    RegisterUnlock()
end)
