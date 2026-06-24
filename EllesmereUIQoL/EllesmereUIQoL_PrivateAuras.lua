-------------------------------------------------------------------------------
--  EllesmereUIQoL_PrivateAuras.lua
--  Private Aura Monitor. Private auras are a restricted Blizzard system (boss
--  mechanics) whose data addons CANNOT read. The only way to show them is to
--  hand Blizzard an anchor frame via C_UnitAuras.AddPrivateAuraAnchor -- Blizzard
--  then renders the (otherwise invisible) icon into our frame. We only control
--  position, size, border scale and the cooldown frame/numbers.
--
--  Mirrors the EXBoss PrivateAuraMonitor approach but follows EllesmereUI's DB /
--  unlock-mode / options conventions (modeled on EllesmereUIQoL_BattleRes.lua).
--
--  Anchors can only be added/removed OUT of combat, so every (re)apply is gated
--  by InCombatLockdown and deferred to PLAYER_REGEN_ENABLED when needed.
-------------------------------------------------------------------------------

local MAX_SLOTS = 5  -- player private-aura slots to expose (extra empty slots render nothing)

-- Sample spells + per-slot durations used only by the preview, so it looks like
-- real auras (real icons + animated, looping cooldowns) instead of static art.
local PREVIEW_SPELLS = { 589, 980, 8680, 146739, 1943 }
local PREVIEW_DURS   = { 16, 22, 12, 28, 19 }

local defaults = {
    profile = {
        privateAuras = {
            enabled         = false,
            slots           = 3,
            iconSize        = 40,
            iconSpacing     = 6,
            growDir         = "RIGHT",  -- RIGHT | LEFT | UP | DOWN
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
local slotFrames   = {}         -- [1..MAX_SLOTS] real frames the icons render into
local previewFrames = {}        -- [1..MAX_SLOTS] fake icons for positioning
local anchorIDs    = {}         -- [1..N] active private-aura anchor IDs
local pendingApply = false
local previewActive = false
local _previewGen   = 0  -- bumped to invalidate stale preview-cooldown timers

local C_UA = C_UnitAuras

-------------------------------------------------------------------------------
--  Layout helpers (group is centered on rootFrame, like the EXBoss monitor)
-------------------------------------------------------------------------------
local function GetGridSize(p)
    p = p or {}
    local sz   = p.iconSize or 40
    local step = sz + (p.iconSpacing or 6)
    local n    = math.max(1, p.slots or 3)
    local dir  = p.growDir or "RIGHT"
    if dir == "RIGHT" or dir == "LEFT" then
        return step * n - (p.iconSpacing or 6), sz
    end
    return sz, step * n - (p.iconSpacing or 6)
end

local function GetSlotOffset(p, idx)
    local sz   = p.iconSize or 40
    local step = sz + (p.iconSpacing or 6)
    local dir  = p.growDir or "RIGHT"
    local totalW, totalH = GetGridSize(p)
    local dx = (totalW - sz) * 0.5
    local dy = (totalH - sz) * 0.5
    local i = idx - 1
    if dir == "RIGHT" then return -dx + i * step, 0 end
    if dir == "LEFT"  then return  dx - i * step, 0 end
    if dir == "UP"    then return 0, -dy + i * step end
    return 0, dy - i * step  -- DOWN
end

-------------------------------------------------------------------------------
--  Frame creation
-------------------------------------------------------------------------------
local function MakePreviewFrame(parent)
    local PP = EllesmereUI and EllesmereUI.PP
    local pf = CreateFrame("Frame", nil, parent)
    pf:EnableMouse(false)
    pf.tex = pf:CreateTexture(nil, "ARTWORK")
    pf.tex:SetAllPoints(pf)
    pf.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim the icon's stock border
    if PP then PP.CreateBorder(pf, 0, 0, 0, 1, 1, "OVERLAY", 2) end

    -- Fake cooldown so the preview shows an animated swipe / numbers / offset.
    pf.cd = CreateFrame("Cooldown", nil, pf, "CooldownFrameTemplate")
    pf.cd:SetAllPoints(pf)
    pf.cd:SetDrawEdge(false)
    pf.cd:Hide()

    pf:Hide()
    return pf
end

local function EnsureFrames()
    if not rootFrame then
        rootFrame = CreateFrame("Frame", "EllesmereUIPrivateAuras", UIParent)
        rootFrame:SetFrameStrata("MEDIUM")
        rootFrame:SetSize(GetGridSize(P()))
        rootFrame:EnableMouse(false)
    end
    for i = 1, MAX_SLOTS do
        if not slotFrames[i] then
            local f = CreateFrame("Frame", nil, rootFrame)
            f:EnableMouse(false)
            slotFrames[i] = f
        end
        if not previewFrames[i] then
            previewFrames[i] = MakePreviewFrame(slotFrames[i])
            local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(PREVIEW_SPELLS[i])) or 134400
            previewFrames[i].tex:SetTexture(tex)
        end
    end
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

-- Lay out slot/preview frames for the current settings (safe in combat).
local function LayoutSlots(p)
    local sz = p.iconSize or 40
    local n  = math.max(1, math.min(MAX_SLOTS, p.slots or 3))
    rootFrame:SetSize(GetGridSize(p))
    for i = 1, MAX_SLOTS do
        local f = slotFrames[i]
        f:SetSize(sz, sz)
        f:ClearAllPoints()
        if i <= n then
            local ox, oy = GetSlotOffset(p, i)
            f:SetPoint("CENTER", rootFrame, "CENTER", ox, oy)
            f:Show()
        else
            f:Hide()
        end
        local pf = previewFrames[i]
        pf:SetSize(sz, sz)
    end
end

local function ApplyAnchors()
    if not rootFrame then return end
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
    local n        = math.max(1, math.min(MAX_SLOTS, p.slots or 3))
    local dox, doy = p.durationOffsetX or 0, p.durationOffsetY or 0
    local hasOffset = p.showCountdown and (dox ~= 0 or doy ~= 0)

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
    for i = 1, MAX_SLOTS do
        if previewFrames[i] then previewFrames[i]:Hide() end
    end
end

-- Self-scheduling loop so each preview icon shows an animated, repeating
-- cooldown. The generation token invalidates timers from a previous render.
local function ArmSlotLoop(i, gen)
    if gen ~= _previewGen or not previewActive then return end
    local pf = previewFrames[i]
    if not pf or not pf.cd:IsShown() then return end
    local dur = PREVIEW_DURS[i] or 15
    pf.cd:SetCooldown(GetTime(), dur)
    C_Timer.After(dur, function() ArmSlotLoop(i, gen) end)
end

local function StartPreviewCooldowns(n)
    _previewGen = _previewGen + 1
    local gen = _previewGen
    for i = 1, n do
        ArmSlotLoop(i, gen)
    end
end

-- Full live render of the preview icons. Re-runs on every settings change so
-- size / spacing / grow / slots / border / cooldown options update immediately,
-- using real spell art and animated cooldowns (matching Advanced Debuffs).
local function RenderPreview(p)
    local PP = EllesmereUI and EllesmereUI.PP
    local sz = p.iconSize or 40
    local n  = math.max(1, math.min(MAX_SLOTS, p.slots or 3))
    local dox, doy = p.durationOffsetX or 0, p.durationOffsetY or 0

    LayoutSlots(p)      -- sizes rootFrame + slotFrames and positions them
    ApplyPosition()
    rootFrame:Show()

    for i = 1, MAX_SLOTS do
        local f  = slotFrames[i]
        local pf = previewFrames[i]
        pf:ClearAllPoints()
        pf:SetSize(sz, sz)
        pf:SetPoint("CENTER", f, "CENTER", 0, 0)
        pf:SetFrameStrata("DIALOG")

        -- Border: thickness scales with Border Scale (mirrors the real anchor's
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

        -- Cooldown swipe / numbers / timer offset.
        local cd = pf.cd
        if p.showCountdown ~= false then
            cd:ClearAllPoints()
            cd:SetSize(sz, sz)
            cd:SetPoint("CENTER", pf, "CENTER", dox, doy)
            cd:SetHideCountdownNumbers(p.showNumbers == false)
            cd:SetDrawSwipe(true)
            cd:Show()
        else
            cd:Hide()
        end

        if i <= n then pf:Show() else pf:Hide() end
    end

    StartPreviewCooldowns(n)
end

local function ShowPreview()
    EnsureFrames()
    local p = P(); if not p then return end
    previewActive = true
    RemoveAllAnchors()  -- don't run real anchors while previewing
    RenderPreview(p)
end
_G._EUI_PrivateAuras_ShowPreview = ShowPreview

local function HidePreview()
    previewActive = false
    _previewGen = _previewGen + 1  -- stop the looping preview cooldowns
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
    EnsureFrames()
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
                if not rootFrame then EnsureFrames() end
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
    EnsureFrames()
    _registerEvents()
    Apply()
    RegisterUnlock()
end)
