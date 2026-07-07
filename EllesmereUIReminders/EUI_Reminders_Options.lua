-------------------------------------------------------------------------------
--  EUI_Reminders_Options.lua
--  Options page for the Combat Potion + Lust reminders. Lifted out of the QoL
--  options panel (EUI_QoL_Options.lua) into this standalone addon; registers
--  its own /erem module. Drives the same EllesmereUIDB.* keys as before, so
--  existing settings carry over. BuildReminderSection is the shared builder
--  copied verbatim from the QoL options file.
-------------------------------------------------------------------------------

local function BuildReminderSection(W, parent, y, spec)
    local _, h
    local function enabled() return EllesmereUIDB and EllesmereUIDB[spec.key] end
    local function off() return not enabled() end

    -- Enable toggle row (right half empty)
    local row
    row, h = W:DualRow(parent, y,
        { type="toggle", text=spec.label, tooltip=spec.tooltip,
          getValue=function() return enabled() or false end,
          setValue=function(v)
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB[spec.key] = v
            if not v and spec.hidePreview then spec.hidePreview() end
            EllesmereUI:RefreshPage(true)  -- rebuild so the section shows/hides
          end },
        { type="label", text="" }
    );  y = y - h

    -- Inline eye-preview toggle on the enable row
    do
        local leftRgn = row._leftRegion
        local EYE_VISIBLE   = EllesmereUI.MEDIA_PATH .. "icons\\eui-visible.png"
        local EYE_INVISIBLE = EllesmereUI.MEDIA_PATH .. "icons\\eui-invisible.png"
        local shown = false
        local eye = CreateFrame("Button", nil, leftRgn)
        eye:SetSize(26, 26)
        eye:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
        eye:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        eye:SetAlpha(off() and 0.15 or 0.4)
        local tex = eye:CreateTexture(nil, "OVERLAY"); tex:SetAllPoints()
        local function refresh() tex:SetTexture(shown and EYE_INVISIBLE or EYE_VISIBLE) end
        refresh()
        eye:SetScript("OnEnter", function(self) self:SetAlpha(0.7); EllesmereUI.ShowWidgetTooltip(self, spec.previewLabel) end)
        eye:SetScript("OnLeave", function(self) EllesmereUI.HideWidgetTooltip(); self:SetAlpha(off() and 0.15 or 0.4) end)
        eye:SetScript("OnClick", function()
            if off() then return end
            shown = not shown; refresh()
            if shown then
                if spec.apply then spec.apply() end
                if spec.preview then spec.preview() end
            elseif spec.hidePreview then
                spec.hidePreview()
            end
        end)
        local block = CreateFrame("Frame", nil, eye)
        block:SetAllPoints(); block:SetFrameLevel(eye:GetFrameLevel() + 10); block:EnableMouse(true)
        block:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(eye, EllesmereUI.DisabledTooltip(spec.name)) end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        if off() then block:Show() else block:Hide() end
        EllesmereUI.RegisterWidgetRefresh(function()
            if off() then
                shown = false; refresh(); eye:SetAlpha(0.15); block:Show()
                if spec.hidePreview then spec.hidePreview() end
            else
                eye:SetAlpha(0.4); block:Hide()
            end
        end)
    end

    -- Config section (only while enabled)
    if enabled() then
        _, h = W:SectionHeader(parent, spec.headerText, y);  y = y - h

        -- Reminder Text
        _, h = W:DualRow(parent, y,
            { type="input", text="Reminder Text", inputWidth=180, maxLetters=80,
              getValue=function()
                local t = EllesmereUIDB and EllesmereUIDB[spec.textKey]
                if t and t ~= "" then return t end
                return spec.defaultText
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                v = (v and v:gsub("^%s+", ""):gsub("%s+$", "")) or ""
                if v == "" or v == spec.defaultText then v = nil end
                EllesmereUIDB[spec.textKey] = v
                if spec.apply then spec.apply() end
              end },
            { type="spacer" }
        );  y = y - h

        -- Text Size | Color
        _, h = W:DualRow(parent, y,
            { type="slider", text="Text Size", min=10, max=50, step=1,
              getValue=function() return (EllesmereUIDB and EllesmereUIDB[spec.sizeKey]) or 30 end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB[spec.sizeKey] = v
                if spec.apply then spec.apply() end
              end },
            { type="colorpicker", text="Color",
              getValue=function()
                local c = EllesmereUIDB and EllesmereUIDB[spec.colorKey]
                if c then return c.r, c.g, c.b end
                return spec.defaultColor.r, spec.defaultColor.g, spec.defaultColor.b
              end,
              setValue=function(r, g, b)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB[spec.colorKey] = { r = r, g = g, b = b }
                if spec.apply then spec.apply() end
              end }
        );  y = y - h

        -- Sound
        _, h = W:DualRow(parent, y,
            EllesmereUI.BuildQoLSoundRow("Sound",
                function() return EllesmereUIDB and EllesmereUIDB[spec.soundKey] or "none" end,
                function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB[spec.soundKey] = (v ~= "none" and v) or nil
                end),
            { type="spacer" }
        );  y = y - h

        -- Optional per-reminder extra rows (e.g. the Lust "self only" toggle).
        if spec.extraConfig then
            y = spec.extraConfig(W, parent, y)
        end
    end

    return y
end

-------------------------------------------------------------------------------
--  Page: Combat Potion + Lust reminders.
-------------------------------------------------------------------------------
local PAGE_REMINDERS = "Reminders"

local function BuildRemindersPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end

        -- Combat Potion Reminder (toggle + eye, then a config section when on)
        y = BuildReminderSection(W, parent, y, {
            key = "combatPotionReminder",
            name = "Combat Potion Reminder",
            label = "Combat Potion Reminder",
            tooltip = "Pulses an on-screen reminder while a combat potion in your bags is ready to use. Only triggers inside Mythic raids and Mythic+. Potions are auto-detected from your bags.",
            headerText = "COMBAT POTION REMINDER",
            textKey = "combatPotionText",   defaultText = "Combat Potion Ready!",
            sizeKey = "combatPotionTextSize",
            colorKey = "combatPotionColor",  defaultColor = { r = 0.3, g = 1, b = 0.3 },
            soundKey = "combatPotionSound",
            previewLabel = "Preview combat potion reminder",
            apply = function() if EllesmereUI._applyCombatPotion then EllesmereUI._applyCombatPotion() end end,
            preview = function() if EllesmereUI._combatPotionPreview then EllesmereUI._combatPotionPreview() end end,
            hidePreview = function() if EllesmereUI._combatPotionHidePreview then EllesmereUI._combatPotionHidePreview() end end,
        })

        -- Lust Reminder (toggle + eye, then a config section when on)
        y = BuildReminderSection(W, parent, y, {
            key = "lustReminder",
            name = "Lust Reminder",
            label = "Lust Reminder",
            tooltip = "Pulses an on-screen reminder while you are in combat, not affected by Sated/Exhaustion, and a Bloodlust-type cooldown is available (Bloodlust/Heroism, Time Warp, Fury of the Aspects or Primal Rage). Only triggers when your own class can lust, or a lust-capable class is in your group.",
            headerText = "LUST REMINDER",
            textKey = "lustReminderText",   defaultText = "Lust Ready!",
            sizeKey = "lustReminderTextSize",
            colorKey = "lustReminderColor",  defaultColor = { r = 1, g = 0.5, b = 0.1 },
            soundKey = "lustReminderSound",
            previewLabel = "Preview lust reminder",
            apply = function() if EllesmereUI._applyLustReminder then EllesmereUI._applyLustReminder() end end,
            preview = function() if EllesmereUI._lustReminderPreview then EllesmereUI._lustReminderPreview() end end,
            hidePreview = function() if EllesmereUI._lustReminderHidePreview then EllesmereUI._lustReminderHidePreview() end end,
            extraConfig = function(W, parent, y)
                local _, h = W:DualRow(parent, y,
                    { type="toggle", text="Only When My Class Can Lust",
                      tooltip="When on, the reminder only appears if your own class can cast a Bloodlust-type ability. When off, it also appears whenever a lust-capable class is in your group.",
                      getValue=function() return EllesmereUIDB and EllesmereUIDB.lustReminderSelfOnly or false end,
                      setValue=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.lustReminderSelfOnly = v or nil
                      end },
                    { type="spacer" }
                )
                return y - h
            end,
        })

        _, h = W:Spacer(parent, y, 20);  y = y - h

    parent:SetHeight(math.abs(y - yOffset))
end

-------------------------------------------------------------------------------
--  Standalone module registration + slash (/erem).
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    EllesmereUI:RegisterModule("EllesmereUIReminders", {
        title       = "Reminders",
        description = "On-screen combat potion and lust reminders.",
        searchTerms = { "reminder", "reminders", "potion", "combat potion", "potion reminder",
                        "consumable", "lust", "bloodlust", "heroism", "time warp", "primal rage" },
        pages       = { PAGE_REMINDERS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_REMINDERS then
                return BuildRemindersPage(pageName, parent, yOffset)
            end
        end,
        onReset     = function()
            if EllesmereUIDB then
                EllesmereUIDB.combatPotionReminder = false
                EllesmereUIDB.combatPotionColor = nil
                EllesmereUIDB.combatPotionTextSize = nil
                EllesmereUIDB.combatPotionYOffset = nil
                EllesmereUIDB.combatPotionPos = nil
                EllesmereUIDB.combatPotionSound = nil
                EllesmereUIDB.combatPotionText = nil
                EllesmereUIDB.lustReminder = false
                EllesmereUIDB.lustReminderColor = nil
                EllesmereUIDB.lustReminderTextSize = nil
                EllesmereUIDB.lustReminderYOffset = nil
                EllesmereUIDB.lustReminderPos = nil
                EllesmereUIDB.lustReminderSound = nil
                EllesmereUIDB.lustReminderText = nil
                EllesmereUIDB.lustReminderSelfOnly = nil
            end
            if EllesmereUI._combatPotionHidePreview then EllesmereUI._combatPotionHidePreview() end
            if EllesmereUI._lustReminderHidePreview then EllesmereUI._lustReminderHidePreview() end
            if EllesmereUI._applyCombatPotion then EllesmereUI._applyCombatPotion() end
            if EllesmereUI._applyLustReminder then EllesmereUI._applyLustReminder() end
        end,
    })

    -- Show in the /eui sidebar under a dedicated "Extras" group. Injected at
    -- runtime into the exposed EllesmereUI tables -- NOT edited into the upstream
    -- ADDON_GROUPS/ADDON_ROSTER literals -- so it never conflicts on a merge.
    -- Idempotent and shared across the fork's split addons (first to load wins).
    EllesmereUI._ForkSidebarInject = EllesmereUI._ForkSidebarInject or function(folder, display, searchName)
        local G, I = EllesmereUI.ADDON_GROUPS, EllesmereUI._addonInfoByFolder
        if not (G and I) then return end
        I[folder] = I[folder] or { folder = folder, display = display, search_name = searchName }
        local grp
        for _, g in ipairs(G) do if g.key == "forkextras" then grp = g; break end end
        if not grp then grp = { key = "forkextras", label = "Extras", members = {} }; G[#G + 1] = grp end
        for _, m in ipairs(grp.members) do if m == folder then return end end
        grp.members[#grp.members + 1] = folder
    end
    EllesmereUI._ForkSidebarInject("EllesmereUIReminders", "Reminders", "EllesmereUI Reminders")

    SLASH_EUIREMINDERS1 = "/erem"
    SlashCmdList.EUIREMINDERS = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIReminders")
    end
end)
