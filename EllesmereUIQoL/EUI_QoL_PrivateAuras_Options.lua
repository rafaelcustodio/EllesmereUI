-------------------------------------------------------------------------------
--  EUI_QoL_PrivateAuras_Options.lua
--  Options page for the Private Aura Monitor (registered under EllesmereUIQoL).
--  Mirrors EUI_QoL_AdvancedDebuffs_Options.lua.
-------------------------------------------------------------------------------

local function DB()
    local fn = _G._EUI_PrivateAuras_DB
    return fn and fn() or nil
end

local function P()
    local d = DB()
    return d and d.profile and d.profile.privateAuras
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
    if _G._EUI_PrivateAuras_Apply then _G._EUI_PrivateAuras_Apply() end
end

local function Enabled() return Cfg("enabled") and true or false end
local function Disabled() return not Enabled() end

local GROW_VALUES = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
local GROW_ORDER  = { "RIGHT", "LEFT", "UP", "DOWN" }

-------------------------------------------------------------------------------
--  Page builder
-------------------------------------------------------------------------------
local function BuildPrivateAurasPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h, row

    if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
    parent._showRowDivider = true

    -- ── PRIVATE AURAS ─────────────────────────────────────────────────
    _, h = W:SectionHeader(parent, "PRIVATE AURAS", y); y = y - h

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Private Auras",
          tooltip="Show your private auras (restricted boss/dungeon mechanics) as a movable row of icons. Their art and timer are drawn by Blizzard; you control position and size here. Real icons only appear while a mechanic is active -- use Preview to position the row, and Unlock Mode (/eui) to drag it.",
          getValue=function() return Enabled() end,
          setValue=function(v)
              Set("enabled", v)
              if not v and _G._EUI_PrivateAuras_HidePreview then
                  _G._EUI_PrivateAuras_HidePreview()
              end
              Refresh(); EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Preview",
          tooltip="Show placeholder icons in every slot so you can position and size the row without waiting for a real private aura.",
          disabled=Disabled,
          getValue=function()
              return _G._EUI_PrivateAuras_IsPreviewActive
                  and _G._EUI_PrivateAuras_IsPreviewActive() or false
          end,
          setValue=function(v)
              if v then
                  if _G._EUI_PrivateAuras_ShowPreview then _G._EUI_PrivateAuras_ShowPreview() end
              else
                  if _G._EUI_PrivateAuras_HidePreview then _G._EUI_PrivateAuras_HidePreview() end
              end
          end })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="slider", text="Slots",
          tooltip="How many private-aura slots to display. The game shows mechanics in fixed slots; extra slots stay empty until used.",
          disabled=Disabled,
          min=1, max=5, step=1, isPercent=false,
          getValue=function() return Cfg("slots") or 3 end,
          setValue=function(v) Set("slots", v); Refresh() end },
        { type="slider", text="Icon Size",
          tooltip="Width and height of each private-aura icon, in pixels.",
          disabled=Disabled,
          min=20, max=128, step=1, isPercent=false,
          getValue=function() return Cfg("iconSize") or 40 end,
          setValue=function(v) Set("iconSize", v); Refresh() end })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="slider", text="Icon Spacing",
          tooltip="Gap between adjacent icons, in pixels.",
          disabled=Disabled,
          min=0, max=60, step=1, isPercent=false,
          getValue=function() return Cfg("iconSpacing") or 6 end,
          setValue=function(v) Set("iconSpacing", v); Refresh() end },
        { type="dropdown", text="Grow Direction",
          tooltip="Direction the slots line up from the anchor: Right, Left, Up or Down.",
          disabled=Disabled,
          values=GROW_VALUES, order=GROW_ORDER,
          getValue=function() return Cfg("growDir") or "RIGHT" end,
          setValue=function(v) Set("growDir", v); Refresh() end })
    y = y - h

    -- ── APPEARANCE & COOLDOWN ─────────────────────────────────────────
    _, h = W:SectionHeader(parent, "APPEARANCE & COOLDOWN", y); y = y - h

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Show Border",
          tooltip="Show the icon border drawn by Blizzard around each private aura.",
          disabled=Disabled,
          getValue=function() return Cfg("showBorder") ~= false end,
          setValue=function(v) Set("showBorder", v); Refresh() end },
        { type="slider", text="Border Scale",
          tooltip="Thickness multiplier for the icon border.",
          disabled=function() return Disabled() or Cfg("showBorder") == false end,
          disabledTooltip="Enable Show Border to adjust this.",
          min=0.1, max=3, step=0.1, isPercent=false,
          getValue=function() return Cfg("borderScale") or 1.0 end,
          setValue=function(v) Set("borderScale", v); Refresh() end })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Show Cooldown Swipe",
          tooltip="Show the radial cooldown sweep over each icon.",
          disabled=Disabled,
          getValue=function() return Cfg("showCountdown") ~= false end,
          setValue=function(v) Set("showCountdown", v); Refresh() end },
        { type="toggle", text="Show Countdown Numbers",
          tooltip="Show the numeric countdown on each icon. Independent of the swipe -- you can have numbers without the sweep, or vice versa. Use the cog to nudge their position.",
          disabled=Disabled,
          getValue=function() return Cfg("showNumbers") ~= false end,
          setValue=function(v) Set("showNumbers", v); Refresh() end })
    y = y - h

    -- Inline directions cog on Show Countdown Numbers: timer X/Y position
    -- (addon-standard, like the Action Bars text offsets).
    do
        local PP = EllesmereUI.PP
        local rgn = row._rightRegion
        local function isDisabled() return Disabled() or Cfg("showNumbers") == false end
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Timer Position",
            rows = {
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return Cfg("durationOffsetX") or 0 end,
                  set=function(v) Set("durationOffsetX", v); Refresh() end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return Cfg("durationOffsetY") or 0 end,
                  set=function(v) Set("durationOffsetY", v); Refresh() end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        PP.Point(cogBtn, "RIGHT", rgn._control or rgn, "LEFT", -6, 0)
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
        local function UpdateAlpha() cogBtn:SetAlpha(isDisabled() and 0.15 or 0.4) end
        EllesmereUI.RegisterWidgetRefresh(UpdateAlpha)
        UpdateAlpha()
        cogBtn:SetScript("OnClick", function(self) if not isDisabled() then cogShow(self) end end)
        cogBtn:SetScript("OnEnter", function(self) if not isDisabled() then self:SetAlpha(0.75) end end)
        cogBtn:SetScript("OnLeave", function() UpdateAlpha() end)
    end

    _, h = W:Spacer(parent, y, 20); y = y - h

    parent:SetHeight(math.abs(y - yOffset))
end

_G._EUI_BuildPrivateAurasPage = BuildPrivateAurasPage
