-------------------------------------------------------------------------------
--  EllesmereUIReminders.lua
--  Combat Potion Reminder + Lust Reminder. Lifted verbatim out of the QoL addon
--  (EllesmereUIQoL.lua) into a standalone child addon so the QoL file stays
--  pristine against upstream. Each sub-block is self-contained (`do...end` with
--  its own event frame) and self-initializes on PLAYER_ENTERING_WORLD; state
--  lives in EllesmereUIDB (central store), so existing settings carry over.
--
--  Uses only parent APIs on the EllesmereUI table (PP, MakeUnlockElement,
--  RegisterUnlockElements, AppendSharedMediaSounds, GetFontPath, EXPRESSWAY, ...)
--  plus EllesmereUIDB -- no dependency on QoL internals.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Reminder sounds (shared by the Combat Potion and Lust reminders)
--  Built-in EllesmereUI sounds + LibSharedMedia sounds appended at login, so
--  the same sound list as the Cooldown Manager's Focus Cast Sound shows here.
-------------------------------------------------------------------------------
do
    local _SOUNDS_DIR = "Interface\\AddOns\\EllesmereUI\\media\\sounds\\"
    local SOUND_PATHS = {
        ["none"]     = nil,
        ["airhorn"]  = _SOUNDS_DIR .. "AirHorn.ogg",
        ["banana"]   = _SOUNDS_DIR .. "BananaPeelSlip.ogg",
        ["bikehorn"] = _SOUNDS_DIR .. "BikeHorn.ogg",
        ["boxing"]   = _SOUNDS_DIR .. "BoxingArenaSound.ogg",
        ["water"]    = _SOUNDS_DIR .. "WaterDrop.ogg",
    }
    local SOUND_NAMES = {
        ["none"]     = "None",
        ["airhorn"]  = "Air Horn",
        ["banana"]   = "Banana Peel Slip",
        ["bikehorn"] = "Bike Horn",
        ["boxing"]   = "Boxing Arena",
        ["water"]    = "Water Drop",
    }
    local SOUND_ORDER = { "none", "airhorn", "banana", "bikehorn", "boxing", "water" }

    EllesmereUI.QOL_SOUND_PATHS = SOUND_PATHS
    EllesmereUI.QOL_SOUND_NAMES = SOUND_NAMES
    EllesmereUI.QOL_SOUND_ORDER = SOUND_ORDER

    -- Append LibSharedMedia sounds (idempotent: duplicate keys are skipped).
    local function EnsureLSM()
        if EllesmereUI.AppendSharedMediaSounds then
            EllesmereUI.AppendSharedMediaSounds(SOUND_PATHS, SOUND_NAMES, SOUND_ORDER)
        end
    end

    -- Play a configured sound by key. nil / "none" / unknown key = silent.
    EllesmereUI.PlayQoLSound = function(key)
        if not key or key == "none" then return end
        local path = SOUND_PATHS[key]
        if path then PlaySoundFile(path, "Master") end
    end

    -- Build a "Sound" dropdown row config (with speaker preview icon) for a cog
    -- popup. getKey/setKey read & write the stored key ("none" stored as nil).
    EllesmereUI.BuildQoLSoundRow = function(label, getKey, setKey)
        EnsureLSM()
        local vals = {}
        for k, v in pairs(SOUND_NAMES) do vals[k] = v end
        vals._menuOpts = {
            itemHeight = 26,
            maxTextWidthPct = 0.8,
            searchable = true,
            iconAtlas = function(key)
                if key == "none" or not SOUND_PATHS[key] then return nil end
                return "common-icon-sound"
            end,
            iconPressedAtlas = function(key)
                if key == "none" then return nil end
                return "common-icon-sound-pressed"
            end,
            iconOnClick = function(key)
                local path = SOUND_PATHS[key]
                if path then PlaySoundFile(path, "Master") end
            end,
            iconTooltip = function() return "Preview Sound" end,
        }
        -- Both naming conventions so the row works in a cog popup (label/get/set)
        -- and in a W:DualRow (text/getValue/setValue).
        return {
            type = "dropdown",
            label = label, text = label,
            values = vals, order = SOUND_ORDER,
            get = getKey, set = setKey,
            getValue = getKey, setValue = setKey,
        }
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); EnsureLSM() end)
end

-------------------------------------------------------------------------------
--  Combat Potion Reminder
--  Flashes an on-screen reminder while a combat potion in your bags is off
--  cooldown, but only inside Mythic raids (difficulty 16/233) and Mythic+
--  (active keystone runs). Potions are auto-detected from the bags so the
--  feature works with any potion (retail or otherwise) without configuration.
-------------------------------------------------------------------------------
do
    -- API resolution (these were relocated under C_Item / C_Container on retail).
    local GetInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local GetCD          = (C_Item and C_Item.GetItemCooldown) or (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    local NumSlots       = C_Container and C_Container.GetContainerNumSlots
    local SlotItemID     = C_Container and C_Container.GetContainerItemID

    local DEFAULT_TEXT = "Combat Potion Ready!"

    local trackedPotions = {}   -- [itemID] = true, refreshed on bag changes
    local potionOverlay
    local potionTicker
    local previewActive = false

    -- True only inside Mythic raid or an active Mythic+ keystone run.
    local function InMythicContent()
        if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
           and C_ChallengeMode.IsChallengeModeActive() then
            return true
        end
        local _, instType, diffID = GetInstanceInfo()
        if instType == "raid" and (diffID == 16 or diffID == 233) then
            return true  -- 16 = fixed-20 Mythic, 233 = flexible Mythic
        end
        return false
    end

    -- Rebuild the tracked-potion set from every bag (potions are class 0 / subclass 1).
    local function ScanPotions()
        wipe(trackedPotions)
        if not (NumSlots and SlotItemID and GetInfoInstant) then return end
        for bag = 0, 5 do
            local slots = NumSlots(bag)
            if slots then
                for slot = 1, slots do
                    local itemID = SlotItemID(bag, slot)
                    if itemID then
                        local _, _, _, _, _, classID, subClassID = GetInfoInstant(itemID)
                        if classID == 0 and subClassID == 1 then
                            trackedPotions[itemID] = true
                        end
                    end
                end
            end
        end
    end

    -- True if at least one tracked potion is off cooldown (ignores the GCD).
    local function AnyPotionReady()
        if not next(trackedPotions) then return false end
        local now = GetTime()
        for itemID in pairs(trackedPotions) do
            local start, duration = GetCD(itemID)
            if start ~= nil then
                local dur = duration or 0
                if dur <= 2 or (start + dur - now) <= 0 then
                    return true
                end
            end
        end
        return false
    end

    -- True if a tracked potion is on a genuine (non-GCD) cooldown, i.e. one has
    -- actually been consumed. WoW exposes no clean way to tell a combat potion
    -- from a healing/mana potion (both are class 0 / subclass 1), so a ready
    -- healing potion left in the bags would otherwise keep the reminder up even
    -- after the player drank their combat potion. Dismiss while anything is on
    -- cooldown; it naturally re-shows once the potion comes back up.
    local function AnyPotionOnCooldown()
        local now = GetTime()
        for itemID in pairs(trackedPotions) do
            local start, duration = GetCD(itemID)
            if start and start > 0 then
                local dur = duration or 0
                if dur > 2 and (start + dur - now) > 0 then
                    return true
                end
            end
        end
        return false
    end

    local function CreatePotionOverlay()
        if potionOverlay then return end

        potionOverlay = CreateFrame("Frame", nil, UIParent)
        potionOverlay:SetSize(400, 40)
        potionOverlay:SetFrameStrata("HIGH")
        potionOverlay:SetFrameLevel(50)
        potionOverlay:EnableMouse(false)
        potionOverlay:SetMouseClickEnabled(false)

        local fs = potionOverlay:CreateFontString(nil, "OVERLAY")
        fs:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 18, EllesmereUI.GetFontOutlineFlag("extras"))
        fs:SetPoint("CENTER")
        fs:SetText(DEFAULT_TEXT)
        potionOverlay._text = fs

        local function ApplySettings()
            potionOverlay:ClearAllPoints()
            local pos = EllesmereUIDB and EllesmereUIDB.combatPotionPos
            if pos and pos.point then
                potionOverlay:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 200)
            else
                local yOff = EllesmereUIDB and EllesmereUIDB.combatPotionYOffset or 200
                potionOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, yOff)
            end
            potionOverlay:SetScale(1)

            local fontPath = EllesmereUI.GetFontPath("extras")
            local sz = (EllesmereUIDB and EllesmereUIDB.combatPotionTextSize) or 30
            fs:SetFont(fontPath, sz, EllesmereUI.GetFontOutlineFlag("extras"))

            local c = EllesmereUIDB and EllesmereUIDB.combatPotionColor
            if c then
                fs:SetTextColor(c.r, c.g, c.b, 1)
            else
                fs:SetTextColor(0.3, 1, 0.3, 1)
            end

            local txt = EllesmereUIDB and EllesmereUIDB.combatPotionText
            fs:SetText((txt and txt ~= "") and txt or DEFAULT_TEXT)
        end
        potionOverlay._applySettings = ApplySettings

        -- Slow, gentle pulse so a persistent reminder still draws the eye
        -- without the urgency of the durability flash.
        local ag = fs:CreateAnimationGroup()
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.55)
        fadeOut:SetDuration(0.8)
        fadeOut:SetOrder(1)
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.55)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.8)
        fadeIn:SetOrder(2)
        ag:SetLooping("REPEAT")

        potionOverlay._show = function()
            ApplySettings()  -- also refreshes the (possibly custom) text
            potionOverlay:Show()
            ag:Play()
        end

        potionOverlay:SetScript("OnHide", function() ag:Stop() end)
        -- Position once on creation so the frame always has a valid anchor for
        -- the unlock-mode mover. getFrame must NOT re-apply afterwards, or it
        -- would snap the frame back to the saved pos mid-drag.
        ApplySettings()
        potionOverlay:Hide()
    end

    local function HideOverlay()
        if potionOverlay then potionOverlay:Hide() end
    end

    -- Single periodic evaluation; cheap and early-outs when disabled / not eligible.
    local function Evaluate()
        if previewActive then return end
        if not (EllesmereUIDB and EllesmereUIDB.combatPotionReminder) then
            HideOverlay()
            return
        end
        if not InMythicContent() then
            HideOverlay()
            return
        end
        if AnyPotionReady() and not AnyPotionOnCooldown() then
            CreatePotionOverlay()
            -- Play the alert sound only on the hidden->shown edge, not every tick.
            if not potionOverlay:IsShown() then
                EllesmereUI.PlayQoLSound(EllesmereUIDB and EllesmereUIDB.combatPotionSound)
            end
            potionOverlay._show()
        else
            HideOverlay()
        end
    end

    EllesmereUI._applyCombatPotion = function()
        CreatePotionOverlay()
        potionOverlay._applySettings()
    end
    EllesmereUI._combatPotionApplySettings = EllesmereUI._applyCombatPotion

    EllesmereUI._combatPotionPreview = function()
        previewActive = true
        CreatePotionOverlay()
        potionOverlay._show()
    end
    EllesmereUI._combatPotionHidePreview = function()
        previewActive = false
        HideOverlay()
        Evaluate()
    end

    local potionFrame = CreateFrame("Frame")
    potionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    potionFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    potionFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    potionFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    potionFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    potionFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    potionFrame:RegisterEvent("CHALLENGE_MODE_START")
    potionFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    potionFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE_DELAYED" then
            ScanPotions()
        end
        Evaluate()
    end)

    -- Safety-net ticker: BAG_UPDATE_COOLDOWN fires when a cooldown starts but not
    -- reliably when it ends, so poll once a second to catch the potion coming up.
    potionTicker = C_Timer.NewTicker(1, Evaluate)

    -- Unlock-mode mover: lets the reminder be repositioned by dragging, like any
    -- other element. The mover shows whenever the feature is enabled (even out of
    -- combat / outside Mythic content, when the live overlay itself is hidden).
    local function RegisterPotionUnlock()
        if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
        local MK = EllesmereUI.MakeUnlockElement
        if not MK then return end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key = "EUI_CombatPotion",
                label = "Combat Potion Reminder",
                group = "Quality of Life",
                order = 602,
                noResize = true,
                isHidden = function()
                    return not (EllesmereUIDB and EllesmereUIDB.combatPotionReminder)
                end,
                getFrame = function()
                    CreatePotionOverlay()
                    return potionOverlay
                end,
                getSize = function()
                    if potionOverlay then return potionOverlay:GetWidth(), potionOverlay:GetHeight() end
                    return 400, 40
                end,
                savePos = function(_, point, relPoint, x, y)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then return end
                    EllesmereUIDB.combatPotionPos = { point = point, relPoint = relPoint, x = x, y = y }
                    if potionOverlay and not EllesmereUI._unlockActive then
                        potionOverlay._applySettings()
                    end
                end,
                loadPos = function()
                    return EllesmereUIDB and EllesmereUIDB.combatPotionPos
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.combatPotionPos = nil end
                end,
                applyPos = function()
                    if potionOverlay then potionOverlay._applySettings() end
                end,
            }),
        })
    end
    _G._EUI_CombatPotion_RegisterUnlock = RegisterPotionUnlock
    C_Timer.After(2, RegisterPotionUnlock)
end

-------------------------------------------------------------------------------
--  Lust Reminder
--  Flashes an on-screen reminder while you are NOT under a Sated/Exhaustion
--  effect and a Bloodlust-type cooldown is available. "Lust" covers every
--  spell that shares the Sated debuff family: Bloodlust/Heroism (Shaman),
--  Time Warp (Mage), Fury of the Aspects (Evoker) and Primal Rage (Hunter pet).
--  The reminder only ever shows when lust is actually reachable: either your
--  own class can cast it or a lust-capable class is in your group. It is gated
--  to combat so it never nags out in the open world. Readiness is inferred from
--  the absence of the Sated debuff (whose 10-min window outlasts the spell's own
--  cooldown), so no secret-tainting cooldown read is ever needed.
-------------------------------------------------------------------------------
do
    -- API resolution (relocated under C_UnitAuras on retail).
    local GetPlayerAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID

    local DEFAULT_TEXT = "Lust Ready!"

    -- Classes that can grant a Bloodlust-type haste buff. Hunters only qualify
    -- with a Ferocity pet (handled separately via the known-spell check).
    local LUST_CLASSES = { SHAMAN = true, MAGE = true, EVOKER = true, HUNTER = true }

    -- Lust spells the local player might be able to cast, keyed by class token.
    -- Shamans know one of Bloodlust/Heroism depending on faction; we test both.
    local PLAYER_LUST_SPELLS = {
        SHAMAN = { 2825, 32182 },   -- Bloodlust / Heroism
        MAGE   = { 80353 },          -- Time Warp
        EVOKER = { 390386 },         -- Fury of the Aspects
        HUNTER = { 264667 },         -- Primal Rage (Ferocity pet)
    }

    -- The shared "you already had lust" debuffs that block another one. Kept in
    -- sync with the Cooldown Manager's SATED_DEBUFFS list (battle-tested set).
    local SATED_IDS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435, 428628 }

    local lustOverlay
    local lustTicker
    local previewActive = false

    local _cachedClass
    local function GetPlayerClass()
        if not _cachedClass then
            local _, cls = UnitClass("player")
            _cachedClass = cls
        end
        return _cachedClass
    end

    -- True if the player knows the given lust spell (player book or pet book).
    local function SpellUsable(sid)
        if IsSpellKnown(sid) then return true end
        if IsSpellKnown(sid, true) then return true end   -- pet spellbook (Hunter)
        if IsPlayerSpell and IsPlayerSpell(sid) then return true end
        return false
    end

    -- True if the player owns a usable lust spell.
    -- NOTE: we deliberately never read the spell's *cooldown*. In Midnight the
    -- cooldown's start/duration are secret values that taint on comparison.
    -- It's also unnecessary: the Sated-family debuff (10 min) always outlasts a
    -- lust spell's own cooldown (5-6 min), so "not Sated" already implies the
    -- spell is off cooldown -- for the caster and for any lust-class groupmate
    -- (everyone shares the same Sated edge). IsSpellKnown is a clean boolean.
    local function PlayerKnowsLust()
        local spells = PLAYER_LUST_SPELLS[GetPlayerClass()]
        if not spells then return false end
        for _, sid in ipairs(spells) do
            if SpellUsable(sid) then return true end
        end
        return false
    end

    -- True if a *group member other than the player* belongs to a lust class.
    -- (party units already exclude the player; raid units include them, so skip
    -- the player's own raid slot.)
    local function OtherGroupMemberCanLust()
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local u = "raid" .. i
                if not UnitIsUnit(u, "player") then
                    local _, cls = UnitClass(u)
                    if cls and LUST_CLASSES[cls] then return true end
                end
            end
        elseif IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do
                local _, cls = UnitClass("party" .. i)
                if cls and LUST_CLASSES[cls] then return true end
            end
        end
        return false
    end

    -- True while any Sated-family debuff is on the player (another lust is wasted).
    local function PlayerSated()
        if GetPlayerAura then
            for _, id in ipairs(SATED_IDS) do
                if GetPlayerAura(id) then return true end
            end
        end
        return false
    end

    local function CreateLustOverlay()
        if lustOverlay then return end

        lustOverlay = CreateFrame("Frame", nil, UIParent)
        lustOverlay:SetSize(400, 40)
        lustOverlay:SetFrameStrata("HIGH")
        lustOverlay:SetFrameLevel(50)
        lustOverlay:EnableMouse(false)
        lustOverlay:SetMouseClickEnabled(false)

        local fs = lustOverlay:CreateFontString(nil, "OVERLAY")
        fs:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 18, EllesmereUI.GetFontOutlineFlag("extras"))
        fs:SetPoint("CENTER")
        fs:SetText(DEFAULT_TEXT)
        lustOverlay._text = fs

        local function ApplySettings()
            lustOverlay:ClearAllPoints()
            local pos = EllesmereUIDB and EllesmereUIDB.lustReminderPos
            if pos and pos.point then
                lustOverlay:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 150)
            else
                local yOff = EllesmereUIDB and EllesmereUIDB.lustReminderYOffset or 150
                lustOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, yOff)
            end
            lustOverlay:SetScale(1)

            local fontPath = EllesmereUI.GetFontPath("extras")
            local sz = (EllesmereUIDB and EllesmereUIDB.lustReminderTextSize) or 30
            fs:SetFont(fontPath, sz, EllesmereUI.GetFontOutlineFlag("extras"))

            local c = EllesmereUIDB and EllesmereUIDB.lustReminderColor
            if c then
                fs:SetTextColor(c.r, c.g, c.b, 1)
            else
                fs:SetTextColor(1, 0.5, 0.1, 1)
            end

            local txt = EllesmereUIDB and EllesmereUIDB.lustReminderText
            fs:SetText((txt and txt ~= "") and txt or DEFAULT_TEXT)
        end
        lustOverlay._applySettings = ApplySettings

        -- Slow, gentle pulse, matching the combat potion reminder.
        local ag = fs:CreateAnimationGroup()
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.55)
        fadeOut:SetDuration(0.8)
        fadeOut:SetOrder(1)
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.55)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.8)
        fadeIn:SetOrder(2)
        ag:SetLooping("REPEAT")

        lustOverlay._show = function()
            ApplySettings()  -- also refreshes the (possibly custom) text
            lustOverlay:Show()
            ag:Play()
        end

        lustOverlay:SetScript("OnHide", function() ag:Stop() end)
        -- Position once on creation so the frame always has a valid anchor for
        -- the unlock-mode mover. getFrame must NOT re-apply afterwards, or it
        -- would snap the frame back to the saved pos mid-drag.
        ApplySettings()
        lustOverlay:Hide()
    end

    local function HideOverlay()
        if lustOverlay then lustOverlay:Hide() end
    end

    -- Single periodic evaluation; cheap and early-outs when disabled / not eligible.
    local function Evaluate()
        if previewActive then return end
        if not (EllesmereUIDB and EllesmereUIDB.lustReminder) then
            HideOverlay()
            return
        end
        -- Lust matters during the fight: gate to combat so it never nags idle.
        if not InCombatLockdown() then
            HideOverlay()
            return
        end

        -- Eligibility: either you can lust yourself, or a groupmate's class can.
        -- When "self only" is on, ignore groupmates and require your own class to
        -- be lust-capable, so the reminder never nags classes that can't lust.
        local selfOnly = EllesmereUIDB and EllesmereUIDB.lustReminderSelfOnly
        local eligible = PlayerKnowsLust() or (not selfOnly and OtherGroupMemberCanLust())
        if not eligible then
            HideOverlay()
            return
        end
        -- Already lusted (or someone lusted you): a second one would be wasted.
        -- While not Sated, a lust is necessarily available (see PlayerKnowsLust).
        if PlayerSated() then
            HideOverlay()
            return
        end

        CreateLustOverlay()
        -- Play the alert sound only on the hidden->shown edge, not every tick.
        if not lustOverlay:IsShown() then
            EllesmereUI.PlayQoLSound(EllesmereUIDB and EllesmereUIDB.lustReminderSound)
        end
        lustOverlay._show()
    end

    EllesmereUI._applyLustReminder = function()
        CreateLustOverlay()
        lustOverlay._applySettings()
    end
    EllesmereUI._lustReminderApplySettings = EllesmereUI._applyLustReminder

    EllesmereUI._lustReminderPreview = function()
        previewActive = true
        CreateLustOverlay()
        lustOverlay._show()
    end
    EllesmereUI._lustReminderHidePreview = function()
        previewActive = false
        HideOverlay()
        Evaluate()
    end

    local lustFrame = CreateFrame("Frame")
    lustFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    lustFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    lustFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    lustFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    lustFrame:RegisterEvent("UNIT_AURA")
    lustFrame:RegisterEvent("UNIT_PET")
    lustFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" and unit ~= "player" then return end
        if event == "UNIT_PET" and unit ~= "player" then return end
        Evaluate()
    end)

    -- Safety-net ticker: the Sated debuff fading doesn't always fire a clean
    -- UNIT_AURA edge, so poll once a second to catch it wearing off.
    lustTicker = C_Timer.NewTicker(1, Evaluate)

    -- Unlock-mode mover: lets the reminder be repositioned by dragging, like any
    -- other element. The mover shows whenever the feature is enabled (even out of
    -- combat, when the live overlay itself is hidden).
    local function RegisterLustUnlock()
        if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
        local MK = EllesmereUI.MakeUnlockElement
        if not MK then return end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key = "EUI_LustReminder",
                label = "Lust Reminder",
                group = "Quality of Life",
                order = 603,
                noResize = true,
                isHidden = function()
                    return not (EllesmereUIDB and EllesmereUIDB.lustReminder)
                end,
                getFrame = function()
                    CreateLustOverlay()
                    return lustOverlay
                end,
                getSize = function()
                    if lustOverlay then return lustOverlay:GetWidth(), lustOverlay:GetHeight() end
                    return 400, 40
                end,
                savePos = function(_, point, relPoint, x, y)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then return end
                    EllesmereUIDB.lustReminderPos = { point = point, relPoint = relPoint, x = x, y = y }
                    if lustOverlay and not EllesmereUI._unlockActive then
                        lustOverlay._applySettings()
                    end
                end,
                loadPos = function()
                    return EllesmereUIDB and EllesmereUIDB.lustReminderPos
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.lustReminderPos = nil end
                end,
                applyPos = function()
                    if lustOverlay then lustOverlay._applySettings() end
                end,
            }),
        })
    end
    _G._EUI_LustReminder_RegisterUnlock = RegisterLustUnlock
    C_Timer.After(2, RegisterLustUnlock)
end
