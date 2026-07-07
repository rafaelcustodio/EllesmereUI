-------------------------------------------------------------------------------
--  EUI_RaidControl_Options.lua
--  Options page for Raid Control. This used to be a toggle injected into the
--  BlizzardSkin options panel; it now lives in its own addon and registers a
--  standalone module (sidebar entry in /eui, plus a /erc slash).
--
--  The feature exposes three globals (defined in EllesmereUIRaidControl.lua):
--    EllesmereUI_IsRaidControlEnabled(), EllesmereUI_EnableRaidControl(),
--    EllesmereUI_DisableRaidControl(). State lives in EllesmereUIDB.raidControl.
-------------------------------------------------------------------------------

local PAGE_RAIDCTRL = "Raid Control"

local function BuildRaidControlPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end

    local _, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Raid Control",
          tooltip="A compact, movable raid-management panel: target markers, ready check, role poll, main tank/assist, countdown, difficulty, convert to raid/party, restrict pings and more. The button appears whenever you are in a group. Position it via Unlock Mode. Enabling requires a reload before you can position it.",
          getValue=function()
              return EllesmereUI_IsRaidControlEnabled and EllesmereUI_IsRaidControlEnabled() or false
          end,
          setValue=function(v)
              if v then
                  if EllesmereUI_EnableRaidControl then EllesmereUI_EnableRaidControl() end
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Reload the UI to position Raid Control via Unlock Mode.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
              else
                  if EllesmereUI_DisableRaidControl then EllesmereUI_DisableRaidControl() end
              end
          end },
        { type="spacer" })
    y = y - h

    _, h = W:Spacer(parent, y, 20); y = y - h

    parent:SetHeight(math.abs(y - yOffset))
end

-------------------------------------------------------------------------------
--  Standalone module registration + slash.
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    EllesmereUI:RegisterModule("EllesmereUIRaidControl", {
        title       = "Raid Control",
        description = "A compact, movable raid-management panel.",
        searchTerms = { "raid control", "raid", "marker", "markers", "world marker", "ready check",
                        "role poll", "main tank", "main assist", "countdown", "convert", "disband",
                        "restrict pings", "raid tools", "raid menu" },
        pages       = { PAGE_RAIDCTRL },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_RAIDCTRL then
                return BuildRaidControlPage(pageName, parent, yOffset)
            end
        end,
        onReset     = function()
            if EllesmereUI_DisableRaidControl then EllesmereUI_DisableRaidControl() end
            if EllesmereUIDB then EllesmereUIDB.raidControlPos = nil end
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
    EllesmereUI._ForkSidebarInject("EllesmereUIRaidControl", "Raid Control", "EllesmereUI Raid Control")

    SLASH_EUIRAIDCONTROL1 = "/erc"
    SlashCmdList.EUIRAIDCONTROL = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIRaidControl")
    end
end)
