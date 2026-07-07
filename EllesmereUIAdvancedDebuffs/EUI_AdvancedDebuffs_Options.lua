-------------------------------------------------------------------------------
--  EUI_QoL_AdvancedDebuffs_Options.lua
--  Options page for the Advanced Debuffs player-debuff tracker
--  (registered under EllesmereUIQoL). Mirrors EUI_QoL_BattleRes_Options.lua.
-------------------------------------------------------------------------------

local function DB()
    local fn = _G._EUI_AdvancedDebuffs_DB
    return fn and fn() or nil
end

local function P()
    local d = DB()
    return d and d.profile and d.profile.advancedDebuffs
end

local function Cfg(key, fallback)
    local p = P()
    if not p then return fallback end
    if p[key] == nil then return fallback end
    return p[key]
end

local function Set(key, v)
    local p = P()
    if p then p[key] = v end
end

local function Refresh()
    if _G._EUI_AdvancedDebuffs_Apply then _G._EUI_AdvancedDebuffs_Apply() end
end

local function Enabled() return Cfg("enabled") and true or false end
local function Disabled() return not Enabled() end

-------------------------------------------------------------------------------
--  Static dropdown value tables
-------------------------------------------------------------------------------
local SHAPE_VALUES = {
    none     = "None",
    cropped  = "Cropped",
    square   = "Square",
    circle   = "Circle",
    csquare  = "Curved Square",
    diamond  = "Diamond",
    hexagon  = "Hexagon",
    portrait = "Portrait",
    shield   = "Shield",
}
local SHAPE_ORDER = { "none", "cropped", "---", "square", "circle", "csquare", "diamond", "hexagon", "portrait", "shield" }

local BORDER_VALUES = { none = "None", thin = "Thin", normal = "Normal", heavy = "Heavy", strong = "Strong" }
local BORDER_ORDER  = { "none", "thin", "normal", "heavy", "strong" }

local BORDERMODE_VALUES = { dispel = "Dispel Type", custom = "Custom Color" }
local BORDERMODE_ORDER  = { "dispel", "custom" }

local GROWH_VALUES = { LEFT = "Left", RIGHT = "Right" }
local GROWH_ORDER  = { "LEFT", "RIGHT" }
local GROWV_VALUES = { DOWN = "Down", UP = "Up" }
local GROWV_ORDER  = { "DOWN", "UP" }

-- Blizzard aura filter categories. Toggling one ON excludes (hides) auras that
-- match that category.
local FILTER_DEFS = {
    { key = "PLAYER",                  text = "Hide Self-Cast Debuffs",
      tooltip = "Hide debuffs you applied to yourself (e.g. your own damage-over-time or self effects). On by default so the tracker focuses on threats cast by others." },
    { key = "RAID",                    text = "Hide Raid Debuffs",
      tooltip = "Hide debuffs that Blizzard flags as raid debuffs." },
    { key = "RAID_PLAYER_DISPELLABLE", text = "Hide Dispellable (by you)",
      tooltip = "Hide debuffs that your current class/spec is able to dispel." },
    { key = "CROWD_CONTROL",           text = "Hide Crowd Control",
      tooltip = "Hide crowd-control effects such as stuns, roots, fears and silences." },
    { key = "RAID_IN_COMBAT",          text = "Hide Raid (in combat)",
      tooltip = "Hide raid debuffs that are only relevant while you are in combat." },
    { key = "IMPORTANT",               text = "Hide Important",
      tooltip = "Hide debuffs that Blizzard flags as important boss/encounter auras." },
    { key = "INCLUDE_NAME_PLATE_ONLY", text = "Hide Nameplate-Only",
      tooltip = "Hide debuffs that are intended to show only on enemy nameplates." },
}

local function FilterGet(key)
    local p = P()
    return p and p.filters and p.filters[key] and true or false
end
-- Store an explicit false (not nil) so a turned-off filter persists and is not
-- re-enabled by the default-merge on next login.
local function FilterSet(key, v)
    local p = P(); if not p then return end
    p.filters = p.filters or {}
    p.filters[key] = v and true or false
    Refresh()
end

-------------------------------------------------------------------------------
--  Border color swatch (custom mode only)
-------------------------------------------------------------------------------
local function MakeBorderColorSwatches()
    return {
        { tooltip = "Custom Color",
          hasAlpha = true,
          getValue = function()
              local c = Cfg("borderColor")
              if c then return c.r or 0, c.g or 0, c.b or 0, c.a or 1 end
              return 0, 0, 0, 1
          end,
          setValue = function(r, g, b, a)
              Set("borderColor", { r = r, g = g, b = b, a = a or 1 })
              Refresh()
          end,
          refreshAlpha = function()
              if Disabled() or Cfg("borderMode") ~= "custom" then return 0.15 end
              return 1
          end },
    }
end

-------------------------------------------------------------------------------
--  Page builder
-------------------------------------------------------------------------------
local function BuildAdvancedDebuffsPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PP
    local y = yOffset
    local _, h, row

    if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
    parent._showRowDivider = true

    -- ── ADVANCED DEBUFFS ──────────────────────────────────────────────
    _, h = W:SectionHeader(parent, "ADVANCED DEBUFFS", y); y = y - h

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Advanced Debuffs",
          tooltip="Track your active debuffs as a freely-movable grid of custom icons. Use Unlock Mode (/eui) to drag it into place.",
          getValue=function() return Enabled() end,
          setValue=function(v)
              Set("enabled", v)
              if not v and _G._EUI_AdvancedDebuffs_HidePreview then
                  _G._EUI_AdvancedDebuffs_HidePreview()
              end
              Refresh(); EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Preview",
          tooltip="Show sample debuffs so you can position and style the grid without waiting for real ones to appear.",
          disabled=Disabled,
          getValue=function()
              return _G._EUI_AdvancedDebuffs_IsPreviewActive
                  and _G._EUI_AdvancedDebuffs_IsPreviewActive() or false
          end,
          setValue=function(v)
              if v then
                  if _G._EUI_AdvancedDebuffs_ShowPreview then _G._EUI_AdvancedDebuffs_ShowPreview() end
              else
                  if _G._EUI_AdvancedDebuffs_HidePreview then _G._EUI_AdvancedDebuffs_HidePreview() end
              end
          end })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Hide Blizzard Debuffs",
          tooltip="Hide the default Blizzard debuff icons while this feature is enabled, so your debuffs aren't shown twice.",
          disabled=Disabled,
          getValue=function() return Cfg("hideBlizzard") and true or false end,
          setValue=function(v) Set("hideBlizzard", v); Refresh() end },
        { type="spacer" })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="slider", text="Icon Size",
          tooltip="Width and height of each debuff icon, in pixels.",
          disabled=Disabled,
          min=16, max=80, step=1, isPercent=false,
          getValue=function() return Cfg("iconSize") or 52 end,
          setValue=function(v) Set("iconSize", v); Refresh() end },
        { type="slider", text="Icon Spacing",
          tooltip="Gap between adjacent icons, in pixels.",
          disabled=Disabled,
          min=0, max=20, step=1, isPercent=false,
          getValue=function() return Cfg("iconSpacing") or 1 end,
          setValue=function(v) Set("iconSpacing", v); Refresh() end })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="slider", text="Icons Per Row",
          tooltip="How many icons fit in a row before wrapping to the next row.",
          disabled=Disabled,
          min=1, max=20, step=1, isPercent=false,
          getValue=function() return Cfg("iconsPerRow") or 5 end,
          setValue=function(v) Set("iconsPerRow", v); Refresh() end },
        { type="slider", text="Max Rows",
          tooltip="Maximum number of rows shown at once. Debuffs beyond Icons Per Row × Max Rows are not displayed.",
          disabled=Disabled,
          min=1, max=10, step=1, isPercent=false,
          getValue=function() return Cfg("maxRows") or 1 end,
          setValue=function(v) Set("maxRows", v); Refresh() end })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Grow Horizontal",
          tooltip="Direction the row grows from its anchor point: to the Left or to the Right.",
          disabled=Disabled,
          values=GROWH_VALUES, order=GROWH_ORDER,
          getValue=function() return Cfg("growHorizontal") or "LEFT" end,
          setValue=function(v) Set("growHorizontal", v); Refresh() end },
        { type="dropdown", text="Grow Vertical",
          tooltip="Direction extra rows are added: Down or Up.",
          disabled=Disabled,
          values=GROWV_VALUES, order=GROWV_ORDER,
          getValue=function() return Cfg("growVertical") or "DOWN" end,
          setValue=function(v) Set("growVertical", v); Refresh() end })
    y = y - h

    -- ── APPEARANCE ────────────────────────────────────────────────────
    _, h = W:SectionHeader(parent, "APPEARANCE", y); y = y - h

    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Icon Shape",
          tooltip="Mask applied to each icon. 'Cropped' trims the icon into a rectangle; the rest are full shape masks.",
          disabled=Disabled,
          values=SHAPE_VALUES, order=SHAPE_ORDER,
          getValue=function() return Cfg("shape") or "none" end,
          setValue=function(v) Set("shape", v); Refresh() end },
        { type="dropdown", text="Border Size",
          tooltip="Thickness of the icon border, or None to hide it.",
          disabled=Disabled,
          values=BORDER_VALUES, order=BORDER_ORDER,
          getValue=function() return Cfg("borderSize") or "thin" end,
          setValue=function(v) Set("borderSize", v); Refresh() end })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Border Color Mode",
          tooltip="Dispel Type colors each border by the debuff's school (Magic, Curse, Disease, Poison, physical). Custom Color uses a single color for every icon.",
          disabled=Disabled,
          values=BORDERMODE_VALUES, order=BORDERMODE_ORDER,
          getValue=function() return Cfg("borderMode") or "dispel" end,
          setValue=function(v) Set("borderMode", v); Refresh(); EllesmereUI:RefreshPage() end },
        { type="multiSwatch", text="Custom Border Color",
          tooltip="Border color used when Border Color Mode is set to Custom Color.",
          disabled=function() return Disabled() or Cfg("borderMode") ~= "custom" end,
          disabledTooltip="Set Border Color Mode to Custom Color to use this.",
          swatches = MakeBorderColorSwatches() })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="slider", text="Icon Zoom",
          tooltip="Zooms into the icon art to trim its built-in border. Only applies when Icon Shape is None or Cropped.",
          disabled=function()
              if Disabled() then return true end
              local s = Cfg("shape") or "none"
              return s ~= "none" and s ~= "cropped"
          end,
          disabledTooltip=function()
              if Disabled() then return "Advanced Debuffs" end
              return "This option requires Icon Shape to be set to None or Cropped."
          end,
          min=0, max=20, step=0.5, isPercent=false,
          getValue=function() return Cfg("iconZoom") or 11 end,
          setValue=function(v) Set("iconZoom", v); Refresh() end },
        { type="toggle", text="Show Duration Text",
          tooltip="Show the built-in cooldown countdown numbers on each icon (its size follows the icon size).",
          disabled=Disabled,
          getValue=function() return Cfg("showDuration") ~= false end,
          setValue=function(v) Set("showDuration", v); Refresh() end })
    y = y - h

    -- ── TEXT & COOLDOWN ───────────────────────────────────────────────
    _, h = W:SectionHeader(parent, "TEXT & COOLDOWN", y); y = y - h

    row, h = W:DualRow(parent, y,
        { type="slider", text="Count Size",
          tooltip="Font size of the stack-count number shown on stacking debuffs.",
          disabled=Disabled,
          min=8, max=20, step=1, isPercent=false,
          getValue=function() return Cfg("countSize") or 14 end,
          setValue=function(v) Set("countSize", v); Refresh() end },
        { type="toggle", text="Cooldown Swipe",
          tooltip="Show the radial sweep animation that fills as the debuff's time runs out.",
          disabled=Disabled,
          getValue=function() return Cfg("swipe") ~= false end,
          setValue=function(v) Set("swipe", v); Refresh() end })
    y = y - h

    -- Inline directions cog on Count Size: stack-count X/Y position (addon-standard).
    do
        local rgn = row._leftRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Count Position",
            rows = {
                { type="slider", label="X Offset", min=-30, max=30, step=1,
                  get=function() return Cfg("countOffsetX") or 0 end,
                  set=function(v) Set("countOffsetX", v); Refresh() end },
                { type="slider", label="Y Offset", min=-30, max=30, step=1,
                  get=function() return Cfg("countOffsetY") or 0 end,
                  set=function(v) Set("countOffsetY", v); Refresh() end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        PP.Point(cogBtn, "RIGHT", rgn._control or rgn, "LEFT", -6, 0)
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
        local function UpdateAlpha() cogBtn:SetAlpha(Disabled() and 0.15 or 0.4) end
        EllesmereUI.RegisterWidgetRefresh(UpdateAlpha)
        UpdateAlpha()
        cogBtn:SetScript("OnClick", function(self) if not Disabled() then cogShow(self) end end)
        cogBtn:SetScript("OnEnter", function(self) if not Disabled() then self:SetAlpha(0.75) end end)
        cogBtn:SetScript("OnLeave", function() UpdateAlpha() end)
    end

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Reverse Swipe",
          tooltip="Reverse the cooldown sweep direction (the swipe shrinks instead of growing).",
          disabled=Disabled,
          getValue=function() return Cfg("reverse") and true or false end,
          setValue=function(v) Set("reverse", v); Refresh() end },
        { type="spacer" })
    y = y - h

    -- ── FILTERS ───────────────────────────────────────────────────────
    _, h = W:SectionHeader(parent, "FILTERS", y); y = y - h

    for i = 1, #FILTER_DEFS, 2 do
        local a = FILTER_DEFS[i]
        local b = FILTER_DEFS[i + 1]
        local leftCfg = { type="toggle", text=a.text, tooltip=a.tooltip, disabled=Disabled,
            getValue=function() return FilterGet(a.key) end,
            setValue=function(v) FilterSet(a.key, v) end }
        local rightCfg
        if b then
            rightCfg = { type="toggle", text=b.text, tooltip=b.tooltip, disabled=Disabled,
                getValue=function() return FilterGet(b.key) end,
                setValue=function(v) FilterSet(b.key, v) end }
        else
            rightCfg = { type="spacer" }
        end
        row, h = W:DualRow(parent, y, leftCfg, rightCfg)
        y = y - h
    end

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Filter Bloodlust Debuffs",
          tooltip="Hide Bloodlust / Heroism and the related Exhaustion / Sated / Fatigued debuffs, which are rarely useful to track.",
          disabled=Disabled,
          getValue=function() return Cfg("filterBloodlust") ~= false end,
          setValue=function(v) Set("filterBloodlust", v); Refresh() end },
        { type="spacer" })
    y = y - h

    _, h = W:Spacer(parent, y, 20); y = y - h

    parent:SetHeight(math.abs(y - yOffset))
end

_G._EUI_BuildAdvancedDebuffsPage = BuildAdvancedDebuffsPage

-------------------------------------------------------------------------------
--  Standalone module registration. Advanced Debuffs used to be a sub-page of
--  the QoL panel; it now lives in its own addon folder and registers its own
--  module (sidebar entry in /eui, plus a /ead slash). Its settings still live
--  under EllesmereUIQoLDB (see the feature file), so nothing resets.
-------------------------------------------------------------------------------
local PAGE_ADVDEBUFFS = "Advanced Debuffs"
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    EllesmereUI:RegisterModule("EllesmereUIAdvancedDebuffs", {
        title       = "Advanced Debuffs",
        description = "Player debuff tracker with a freely-movable icon grid.",
        searchTerms = { "debuff", "debuffs", "advanced debuffs", "aura", "dispel", "bloodlust" },
        pages       = { PAGE_ADVDEBUFFS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_ADVDEBUFFS then
                return BuildAdvancedDebuffsPage(pageName, parent, yOffset)
            end
        end,
        onReset     = function()
            if _G._EUI_AdvancedDebuffs_Reset then _G._EUI_AdvancedDebuffs_Reset() end
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
    EllesmereUI._ForkSidebarInject("EllesmereUIAdvancedDebuffs", "Advanced Debuffs", "EllesmereUI Advanced Debuffs")

    SLASH_EUIADVDEBUFFS1 = "/ead"
    SlashCmdList.EUIADVDEBUFFS = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIAdvancedDebuffs")
    end
end)
