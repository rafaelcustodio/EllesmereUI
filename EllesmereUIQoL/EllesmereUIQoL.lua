-------------------------------------------------------------------------------
--  EUI_QoL.lua
--  Runtime logic for all Quality-of-Life features toggled in the QoL Features
--  tab of Global Settings. No UI code here -- only gameplay behaviour.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Per-profile storage for QoL "extras" (Secondary Stats + FPS counter).
--  These were account-wide on the EllesmereUIDB root; they now live in the QoL
--  profile DB (folder EllesmereUIQoL) so they travel with profiles, export/
--  import, and module sync. The migration in EllesmereUI_Migration.lua seeds
--  every existing profile from the old account-wide values, so nobody loses
--  their setup. Reads fall back to the frozen account-wide root for any profile
--  that has no per-profile value yet (newly created profiles, sync gaps);
--  writes always go per-profile. Mirrors the crosshair read/fallback pattern.
--
--  This shares EllesmereUIQoLDB with the Cursor / BattleRes / Bloodlust modules
--  -- each NewDB call merges its own defaults into the SAME profile table, and
--  the profile system repoints every handle on a profile swap.
-------------------------------------------------------------------------------
local _qolExtrasDB
local function QoLExtrasProfile()
    if not _qolExtrasDB and EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB then
        _qolExtrasDB = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", { profile = {} })
    end
    return _qolExtrasDB and _qolExtrasDB.profile
end
function EllesmereUI.QoLExtrasGet(k)
    local p = QoLExtrasProfile()
    if p and p[k] ~= nil then return p[k] end
    return EllesmereUIDB and EllesmereUIDB[k]
end
function EllesmereUI.QoLExtrasSet(k, v)
    local p = QoLExtrasProfile()
    if p then p[k] = v; return end
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB[k] = v
end

local qolFrame = CreateFrame("Frame")
qolFrame:RegisterEvent("PLAYER_LOGIN")
qolFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    ---------------------------------------------------------------------------
    --  Auto Unwrap Collections (Mounts / Pets / Toys)
    ---------------------------------------------------------------------------
    do
        local busy = false

        -- Dismiss the pending "new item" glow on all mounts that need it,
        -- temporarily narrowing the journal filter so we only iterate collected ones.
        local function AckMountAlerts()
            if not C_MountJournal then return false end
            local pending = C_MountJournal.GetNumMountsNeedingFanfare
                and C_MountJournal.GetNumMountsNeedingFanfare()
            if not pending or pending <= 0 then return false end

            -- Snapshot active filters, force "collected only", sweep, then restore
            local snapshot = {}
            for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
                snapshot[i] = C_MountJournal.GetCollectedFilterSetting(i) and true or false
                C_MountJournal.SetCollectedFilterSetting(i, i == LE_MOUNT_JOURNAL_FILTER_COLLECTED)
            end
            for i = 1, C_MountJournal.GetNumDisplayedMounts() do
                local id = C_MountJournal.GetDisplayedMountID(i)
                if id and C_MountJournal.NeedsFanfare(id) then
                    C_MountJournal.ClearFanfare(id)
                end
            end
            for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
                C_MountJournal.SetCollectedFilterSetting(i, snapshot[i])
            end
            return true
        end

        local function AckPetAlerts()
            if not C_PetJournal or not C_PetJournal.GetNumPetsNeedingFanfare then return false end
            if (C_PetJournal.GetNumPetsNeedingFanfare() or 0) == 0 then return false end
            local any = false
            for _, id in ipairs(C_PetJournal.GetOwnedPetIDs and C_PetJournal.GetOwnedPetIDs() or {}) do
                if id and C_PetJournal.PetNeedsFanfare and C_PetJournal.PetNeedsFanfare(id) then
                    if C_PetJournal.ClearFanfare then C_PetJournal.ClearFanfare(id) end
                    any = true
                end
            end
            return any
        end

        local function AckToyAlerts()
            if not C_ToyBoxInfo or not C_ToyBoxInfo.ClearFanfare then return false end
            local any = false
            -- Fast path via ToyBox.fanfareToys lookup table
            if ToyBox and ToyBox.fanfareToys then
                for id, needs in pairs(ToyBox.fanfareToys) do
                    if needs and id and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.NeedsFanfare(id) then
                        C_ToyBoxInfo.ClearFanfare(id)
                        any = true
                    end
                end
                if any then return true end
            end
            -- Fallback: full scan
            if C_ToyBox and C_ToyBox.GetNumToys and C_ToyBox.GetToyFromIndex then
                for i = 1, C_ToyBox.GetNumToys() do
                    local id = C_ToyBox.GetToyFromIndex(i)
                    if id and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.NeedsFanfare(id) then
                        C_ToyBoxInfo.ClearFanfare(id)
                        any = true
                    end
                end
            end
            return any
        end

        local function DismissCollectionAlerts()
            if not (EllesmereUIDB and EllesmereUIDB.autoUnwrapCollections) then return end
            if busy then return end
            busy = true
            C_Timer.After(0.2, function()
                busy = false
                local changed = AckMountAlerts() or AckPetAlerts() or AckToyAlerts()
                if changed then
                    if CollectionsMicroButton and MainMenuMicroButton_HideAlert then
                        MainMenuMicroButton_HideAlert(CollectionsMicroButton)
                    end
                    if CollectionsMicroButton_SetAlertShown then
                        CollectionsMicroButton_SetAlertShown(false)
                    end
                end
            end)
        end

        EllesmereUI._applyAutoUnwrap = function() end

        hooksecurefunc("MainMenuMicroButton_ShowAlert", function(_, text)
            if not (EllesmereUIDB and EllesmereUIDB.autoUnwrapCollections) then return end
            if text == COLLECTION_UNOPENED_PLURAL or text == COLLECTION_UNOPENED_SINGULAR then
                DismissCollectionAlerts()
            end
        end)

        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("NEW_MOUNT_ADDED")
        f:RegisterEvent("NEW_PET_ADDED")
        f:RegisterEvent("NEW_TOY_ADDED")
        f:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_LOGIN" then
                self:UnregisterEvent("PLAYER_LOGIN")
                -- Defer 3s so ToyBox.fanfareToys is available (avoids
                -- the 1000+ toy fallback scan that spikes the login frame)
                C_Timer.After(3, DismissCollectionAlerts)
                return
            end
            DismissCollectionAlerts()
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Open Containers (incremental cache -- no login spike)
    ---------------------------------------------------------------------------
    do
        local _openableCache = {}  -- itemID -> true/false
        local _failedItems = {}   -- itemID -> true (items that failed to open, skip forever)
        local _cacheBuilt = false
        local function IsEnabled()
            return EllesmereUIDB and EllesmereUIDB.autoOpenContainers == true
        end
        local SLOTS_PER_FRAME = 3  -- check 3 slots per OnUpdate tick

        local function IsOpenableByID(itemID, bag, slot)
            local cached = _openableCache[itemID]
            if cached ~= nil then return cached end
            local tip = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
            if tip and tip.lines then
                for _, line in ipairs(tip.lines) do
                    if line and line.leftText and line.leftText == ITEM_OPENABLE then
                        _openableCache[itemID] = true
                        return true
                    end
                end
            end
            _openableCache[itemID] = false
            return false
        end

        -- Incremental scanner: checks SLOTS_PER_FRAME bag slots per tick.
        -- Once all bags are scanned, hides itself (zero CPU when idle).
        local _scanBag = BACKPACK_CONTAINER
        local _scanSlot = 1
        local _pendingOpens = {}

        local scanFrame = CreateFrame("Frame")
        scanFrame:Hide()
        scanFrame:SetScript("OnUpdate", function(self)
            if not IsEnabled() then self:Hide(); return end
            local checked = 0
            while checked < SLOTS_PER_FRAME do
                local numSlots = C_Container.GetContainerNumSlots(_scanBag)
                if _scanSlot > numSlots then
                    _scanBag = _scanBag + 1
                    _scanSlot = 1
                    if _scanBag > NUM_BAG_SLOTS then
                        -- Full scan complete
                        _cacheBuilt = true
                        self:Hide()
                        -- Open any containers found during scan
                        if #_pendingOpens > 0 and not InCombatLockdown() then
                            local function OpenNext(idx)
                                if idx > #_pendingOpens then wipe(_pendingOpens); return end
                                if InCombatLockdown() then wipe(_pendingOpens); return end
                                local item = _pendingOpens[idx]
                                local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
                                if info and info.itemID and _openableCache[info.itemID] and not _failedItems[info.itemID] then
                                    local prevID = info.itemID
                                    local prevCount = info.stackCount or 1
                                    C_Container.UseContainerItem(item.bag, item.slot)
                                    C_Timer.After(0.5, function()
                                        local after = C_Container.GetContainerItemInfo(item.bag, item.slot)
                                        if after and after.itemID == prevID and (after.stackCount or 1) >= prevCount then
                                            _failedItems[prevID] = true
                                        end
                                        OpenNext(idx + 1)
                                    end)
                                    return
                                end
                                C_Timer.After(0.5, function() OpenNext(idx + 1) end)
                            end
                            OpenNext(1)
                        end
                        return
                    end
                else
                    local info = C_Container.GetContainerItemInfo(_scanBag, _scanSlot)
                    if info and info.itemID then
                        if IsOpenableByID(info.itemID, _scanBag, _scanSlot) then
                            _pendingOpens[#_pendingOpens + 1] = { bag = _scanBag, slot = _scanSlot }
                        end
                    end
                    _scanSlot = _scanSlot + 1
                    checked = checked + 1
                end
            end
        end)

        -- Start incremental scan 2s after login
        C_Timer.After(2, function()
            if not IsEnabled() then return end
            _scanBag = BACKPACK_CONTAINER
            _scanSlot = 1
            wipe(_pendingOpens)
            scanFrame:Show()
        end)

        -- After cache is built, BAG_UPDATE_DELAYED only checks changed slots
        local containerFrame = CreateFrame("Frame")
        if EllesmereUIDB and EllesmereUIDB.autoOpenContainers == true then
            containerFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        end
        containerFrame:SetScript("OnEvent", function()
            if not _cacheBuilt then return end
            if not IsEnabled() then return end
            if InCombatLockdown() then return end
            local toOpen = {}
            for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.itemID then
                        -- Only tooltip-check uncached items (new loot)
                        if _openableCache[info.itemID] == nil then
                            IsOpenableByID(info.itemID, bag, slot)
                        end
                        if _openableCache[info.itemID] and not _failedItems[info.itemID] then
                            toOpen[#toOpen + 1] = { bag = bag, slot = slot }
                        end
                    end
                end
            end
            if #toOpen == 0 then return end
            local function OpenNext(idx)
                if idx > #toOpen then return end
                if InCombatLockdown() then return end
                local item = toOpen[idx]
                local info2 = C_Container.GetContainerItemInfo(item.bag, item.slot)
                if info2 and info2.itemID and _openableCache[info2.itemID] and not _failedItems[info2.itemID] then
                    local prevID = info2.itemID
                    local prevCount = info2.stackCount or 1
                    C_Container.UseContainerItem(item.bag, item.slot)
                    C_Timer.After(0.5, function()
                        local after = C_Container.GetContainerItemInfo(item.bag, item.slot)
                        if after and after.itemID == prevID and (after.stackCount or 1) >= prevCount then
                            _failedItems[prevID] = true
                        end
                        OpenNext(idx + 1)
                    end)
                    return
                end
                C_Timer.After(0.5, function() OpenNext(idx + 1) end)
            end
            C_Timer.After(0.5, function() OpenNext(1) end)
        end)
    end

    ---------------------------------------------------------------------------
    --  Hide Screenshot Status
    ---------------------------------------------------------------------------
    do
        local hooked = false

        local function HideActionStatus()
            local actionStatus = _G.ActionStatus
            if actionStatus then
                actionStatus:Hide()
            end
        end

        local function ApplyScreenshotStatus()
            -- ActionStatus is lazy-created by Blizzard on the first screenshot
            -- event, so it may not exist yet. The ssFrame below catches the
            -- events and hides it immediately after Blizzard shows it.
        end

        EllesmereUI._applyScreenshotStatus = ApplyScreenshotStatus

        local ssFrame = CreateFrame("Frame")
        ssFrame:RegisterEvent("SCREENSHOT_SUCCEEDED")
        ssFrame:RegisterEvent("SCREENSHOT_FAILED")
        ssFrame:SetScript("OnEvent", function()
            if not EllesmereUIDB or EllesmereUIDB.hideScreenshotStatus ~= false then
                -- Hide on next frame so Blizzard's handler runs first
                C_Timer.After(0, HideActionStatus)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Train All Button
    ---------------------------------------------------------------------------
    do
        local trainBtn = nil
        local hooked = false

        -- How many primary profession slots are still free?
        local function FreeProfessionSlots()
            if not GetProfessions then return 2 end
            local a, b = GetProfessions()
            return 2 - (a and 1 or 0) - (b and 1 or 0)
        end

        -- Can skill at index i be purchased given current funds/slots?
        local function SkillIsAffordable(i, wallet, freeSlots)
            if not GetTrainerServiceInfo or not GetTrainerServiceCost then return false, 0, false end
            local _, kind = GetTrainerServiceInfo(i)
            if kind ~= "available" then return false, 0, false end
            local cost, takesProfSlot = GetTrainerServiceCost(i)
            cost = cost or 0
            if cost > wallet then return false, 0, false end
            if takesProfSlot and freeSlots <= 0 then return false, 0, false end
            return true, cost, takesProfSlot
        end

        -- Return total count and total gold cost of everything trainable right now
        local function TrainableSummary()
            if not GetNumTrainerServices then return 0, 0 end
            local n, gold = 0, 0
            local wallet = GetMoney and GetMoney() or 0
            local slots  = FreeProfessionSlots()
            for i = 1, GetNumTrainerServices() do
                local ok, cost = SkillIsAffordable(i, wallet, slots)
                if ok then n = n + 1; gold = gold + cost end
            end
            return n, gold
        end

        local function RefreshButton()
            if not trainBtn then return end
            if not (EllesmereUIDB and EllesmereUIDB.trainAllButton) then
                trainBtn:Hide(); return
            end
            local n = TrainableSummary()
            trainBtn:SetEnabled(n > 0)
            trainBtn:Show()
        end

        local function SpawnButton()
            if not (EllesmereUIDB and EllesmereUIDB.trainAllButton) then return end
            if not ClassTrainerFrame or not ClassTrainerTrainButton then return end
            if trainBtn then trainBtn:Show(); RefreshButton(); return end

            trainBtn = CreateFrame("Button", "EUI_TrainAllButton", ClassTrainerFrame, "MagicButtonTemplate")
            trainBtn:SetText("Train All")
            trainBtn:SetHeight(ClassTrainerTrainButton:GetHeight() or 22)
            trainBtn:SetWidth(80)
            trainBtn:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -2, 0)

            trainBtn:SetScript("OnClick", function()
                local wallet = GetMoney and GetMoney() or 0
                local slots  = FreeProfessionSlots()
                for i = 1, GetNumTrainerServices() do
                    local ok, cost, takesProfSlot = SkillIsAffordable(i, wallet, slots)
                    if ok then
                        BuyTrainerService(i)
                        wallet = wallet - cost
                        if takesProfSlot then slots = slots - 1 end
                    end
                end
            end)

            trainBtn:SetScript("OnEnter", function(self)
                local n, gold = TrainableSummary()
                if n <= 0 then return end
                local msg = string.format("Learn %d skill%s for %s",
                    n, n == 1 and "" or "s",
                    C_CurrencyInfo.GetCoinTextureString(gold))
                EllesmereUI.ShowWidgetTooltip(self, msg)
            end)
            trainBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            if not hooked then
                hooksecurefunc("ClassTrainerFrame_Update", RefreshButton)
                hooked = true
            end
            RefreshButton()
        end

        local function ApplyTrainAllButton()
            if EllesmereUIDB and EllesmereUIDB.trainAllButton then
                EventUtil.ContinueOnAddOnLoaded("Blizzard_TrainerUI", SpawnButton)
                if IsAddOnLoaded and IsAddOnLoaded("Blizzard_TrainerUI") then SpawnButton() end
            elseif trainBtn then
                trainBtn:Hide()
            end
        end

        EllesmereUI._applyTrainAllButton = ApplyTrainAllButton

        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(self, event, addonName)
            if event == "PLAYER_LOGIN" then
                self:UnregisterEvent("PLAYER_LOGIN")
                ApplyTrainAllButton()
            elseif event == "ADDON_LOADED" and addonName == "Blizzard_TrainerUI" then
                self:UnregisterEvent("ADDON_LOADED")
                ApplyTrainAllButton()
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  AH Current Expansion Only
    ---------------------------------------------------------------------------
    do
        local ahFrame = CreateFrame("Frame")
        ahFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
        ahFrame:SetScript("OnEvent", function()
            if not (EllesmereUIDB and EllesmereUIDB.ahCurrentExpansion) then return end
            if not AuctionHouseFrame or not AuctionHouseFrame.SearchBar then return end
            C_Timer.After(0, function()
                local fb = AuctionHouseFrame.SearchBar.FilterButton
                if not fb or not fb.filters then return end
                if not (Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.CurrentExpansionOnly) then return end
                fb.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
                AuctionHouseFrame.SearchBar:UpdateClearFiltersButton()
            end)
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Sell Junk + Auto Repair
    ---------------------------------------------------------------------------
    local merchantFrame = CreateFrame("Frame", "EUI_MerchantHandler", UIParent)
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:SetScript("OnEvent", function()
        if not EllesmereUIDB then return end

        -- Auto sell junk
        if EllesmereUIDB.autoSellJunk ~= false then
            if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
                C_MerchantFrame.SellAllJunkItems()
            end
        end

        -- Auto repair
        if EllesmereUIDB.autoRepair ~= false then
            if CanMerchantRepair() then
                local cost, canRepair = GetRepairAllCost()
                if canRepair and cost > 0 then
                    local useGuild = (EllesmereUIDB.autoRepairGuild ~= false)
                        and IsInGuild()
                        and CanGuildBankRepair()
                        and cost <= GetGuildBankWithdrawMoney()

                    -- Check if we can actually afford the repair
                    if not useGuild and GetMoney() < cost then
                        EllesmereUI.Print("|cff0CD29DEllesmereUI:|r |cffff6060Not enough gold to repair.|r")
                        return
                    end

                    RepairAllItems(useGuild)

                    if useGuild then
                        C_Timer.After(0.5, function()
                            local remainCost, stillNeed = GetRepairAllCost()
                            if stillNeed and remainCost > 0 then
                                if GetMoney() >= remainCost then
                                    RepairAllItems(false)
                                end
                            end
                        end)
                    end

                    local gold = floor(cost / 10000)
                    local silver = floor((cost % 10000) / 100)
                    local src = useGuild and " (guild bank)" or ""
                    EllesmereUI.Print("|cff0CD29DEllesmereUI:|r Repaired all items for " .. gold .. "g " .. silver .. "s." .. src)
                end
            end
        end
    end)

    ---------------------------------------------------------------------------
    --  Quick Loot
    ---------------------------------------------------------------------------
    if EllesmereUIDB and EllesmereUIDB.quickLoot then
        local lootFrame = CreateFrame("Frame")
        lootFrame:RegisterEvent("LOOT_READY")
        lootFrame:SetScript("OnEvent", function()
            if IsShiftKeyDown() then return end
            for i = 1, GetNumLootItems() do
                local index = i
                C_Timer.After(0.05 * index, function()
                    LootSlot(index)
                end)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto-Fill Delete Confirmation
    ---------------------------------------------------------------------------
    do
        for i = 1, 4 do
            local popup = _G["StaticPopup" .. i]
            if popup then
                hooksecurefunc(popup, "Show", function(self)
                    if not self then return end
                    if self.which ~= "DELETE_GOOD_ITEM" and self.which ~= "DELETE_GOOD_QUEST_ITEM" then return end
                    if not (EllesmereUIDB and EllesmereUIDB.autoFillDelete) then return end
                    local editBox = self.editBox or (self.GetEditBox and self:GetEditBox())
                    if not editBox then return end
                    editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
                    editBox:SetFocus()
                end)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Skip Cinematics
    ---------------------------------------------------------------------------
    do
        local cinHooked = false

        local function SetupCinematicHooks()
            if cinHooked then return end
            if not CinematicFrame or not CinematicFrame.HookScript then return end
            cinHooked = true

            CinematicFrame:HookScript("OnKeyDown", function(_, key)
                if not (EllesmereUIDB and EllesmereUIDB.skipCinematics) then return end
                if key == "ESCAPE" then
                    if CinematicFrame:IsShown() and CinematicFrame.closeDialog then
                        CinematicFrame.closeDialog:Hide()
                    end
                end
            end)

            CinematicFrame:HookScript("OnKeyUp", function(_, key)
                if not (EllesmereUIDB and EllesmereUIDB.skipCinematics) then return end
                if key == "SPACE" or key == "ESCAPE" or key == "ENTER" then
                    if CinematicFrame:IsShown() and CinematicFrame.closeDialog then
                        local confirmBtn = _G["CinematicFrameCloseDialogConfirmButton"]
                        if confirmBtn then confirmBtn:Click() end
                    end
                end
            end)

            if MovieFrame and MovieFrame.HookScript then
                MovieFrame:HookScript("OnKeyUp", function(_, key)
                    if not (EllesmereUIDB and EllesmereUIDB.skipCinematics) then return end
                    if key == "SPACE" or key == "ESCAPE" or key == "ENTER" then
                        if MovieFrame:IsShown() and MovieFrame.CloseDialog and MovieFrame.CloseDialog.ConfirmButton then
                            MovieFrame.CloseDialog.ConfirmButton:Click()
                        end
                    end
                end)
            end
        end

        local cinEventFrame = CreateFrame("Frame")
        cinEventFrame:RegisterEvent("CINEMATIC_START")
        cinEventFrame:RegisterEvent("PLAY_MOVIE")
        cinEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        cinEventFrame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_ENTERING_WORLD" then
                self:UnregisterEvent("PLAYER_ENTERING_WORLD")
                SetupCinematicHooks()
                return
            end
            if not (EllesmereUIDB and EllesmereUIDB.skipCinematicsAuto) then return end
            if event == "CINEMATIC_START" then
                if CinematicFrame and CinematicFrame.isRealCinematic then
                    StopCinematic()
                elseif CanCancelScene and CanCancelScene() then
                    CancelScene()
                end
            elseif event == "PLAY_MOVIE" then
                if MovieFrame then MovieFrame:Hide() end
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Insert Keystone
    ---------------------------------------------------------------------------
    do
        local function InsertKeystone()
            if EllesmereUIDB and EllesmereUIDB.autoInsertKeystone == false then return end
            if C_ChallengeMode.GetSlottedKeystoneInfo() then return end
            for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                local slots = C_Container.GetContainerNumSlots(bag)
                for slot = 1, slots do
                    local link = C_Container.GetContainerItemLink(bag, slot)
                    if link and link:find("|Hkeystone:") then
                        C_Container.PickupContainerItem(bag, slot)
                        if CursorHasItem() then
                            C_ChallengeMode.SlotKeystone()
                        end
                        return
                    end
                end
            end
        end

        local ksFrame = CreateFrame("Frame")
        ksFrame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
        ksFrame:RegisterEvent("ADDON_LOADED")
        ksFrame:SetScript("OnEvent", function(self, event, arg1)
            if event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
                InsertKeystone()
            elseif event == "ADDON_LOADED" and arg1 == "Blizzard_ChallengesUI" then
                self:UnregisterEvent("ADDON_LOADED")
                if ChallengesKeystoneFrame then
                    ChallengesKeystoneFrame:HookScript("OnShow", InsertKeystone)
                end
            end
        end)

        if IsAddOnLoaded and IsAddOnLoaded("Blizzard_ChallengesUI") then
            if ChallengesKeystoneFrame then
                ChallengesKeystoneFrame:HookScript("OnShow", InsertKeystone)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Quick Signup (double-click to sign up)
    ---------------------------------------------------------------------------
    do
        local lastClickTime  = 0
        local lastClickEntry = nil
        local DOUBLE_CLICK_THRESHOLD = 0.4
        local installed = false   -- hooks are installed ONCE, on first enable
        local roleFrame           -- classic role-check listener (created on install)

        -- Hooks/listeners are installed only when Quick Signup is turned on, so
        -- nothing touches the LFG execution path unless the feature is in use.
        -- hooksecurefunc/HookScript can't be undone, so the bodies keep their
        -- setting guard for the toggle-off-after-enable case; the role-check
        -- event is registered/unregistered live for true zero cost when off.
        local function InstallQuickSignupHooks()
            if installed then return end
            installed = true

            hooksecurefunc("LFGListSearchEntry_OnClick", function(entry, button)
                if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
                if button == "RightButton" then return end

                local panel = LFGListFrame and LFGListFrame.SearchPanel
                if not panel then return end
                if not LFGListSearchPanelUtil_CanSelectResult(entry.resultID) then return end
                if not panel.SignUpButton or not panel.SignUpButton:IsEnabled() then return end

                local now = GetTime()
                if lastClickEntry == entry.resultID and (now - lastClickTime) < DOUBLE_CLICK_THRESHOLD then
                    if panel.selectedResult ~= entry.resultID then
                        LFGListSearchPanel_SelectResult(panel, entry.resultID)
                    end
                    LFGListSearchPanel_SignUp(panel)
                    lastClickEntry = nil
                    lastClickTime  = 0
                else
                    lastClickEntry = entry.resultID
                    lastClickTime  = now
                end
            end)

            -- Auto-accept role check for Quick Signup. Holding Shift skips the
            -- auto-accept so the dialog stays open (e.g. to type a signup note).
            if LFGListApplicationDialog then
                LFGListApplicationDialog:HookScript("OnShow", function(self)
                    if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
                    if self.SignUpButton:IsEnabled() and not IsShiftKeyDown() then
                        self.SignUpButton:Click()
                    end
                end)
            end

            -- Classic Dungeon Finder role check for Quick Signup
            roleFrame = CreateFrame("Frame")
            roleFrame:SetScript("OnEvent", function()
                if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
                if not UnitInParty("player") then return end
                -- Holding Shift skips the auto role-check accept
                if IsShiftKeyDown() then return end
                local leader, tank, healer, dps = GetLFGRoles()
                if LFDRoleCheckPopupRoleButtonTank.checkButton:IsEnabled() then
                    LFDRoleCheckPopupRoleButtonTank.checkButton:SetChecked(tank)
                end
                if LFDRoleCheckPopupRoleButtonHealer.checkButton:IsEnabled() then
                    LFDRoleCheckPopupRoleButtonHealer.checkButton:SetChecked(healer)
                end
                if LFDRoleCheckPopupRoleButtonDPS.checkButton:IsEnabled() then
                    LFDRoleCheckPopupRoleButtonDPS.checkButton:SetChecked(dps)
                end
                LFDRoleCheckPopupAcceptButton:Enable()
                LFDRoleCheckPopupAcceptButton:Click()
            end)
        end

        -- Called at load and from the options toggle. Installs the hooks on
        -- first enable; toggles the role-check event registration to match.
        EllesmereUI._applyQuickSignup = function()
            local on = EllesmereUIDB and EllesmereUIDB.quickSignup
            if on then InstallQuickSignupHooks() end
            if roleFrame then
                if on then
                    roleFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
                else
                    roleFrame:UnregisterEvent("LFG_ROLE_CHECK_SHOW")
                end
            end
        end

        EllesmereUI._applyQuickSignup()
    end

    ---------------------------------------------------------------------------
    --  Persistent LFG Signup Note
    ---------------------------------------------------------------------------
    do
        local vanilla = LFGListApplicationDialog_Show
        local patched = false

        local function PatchedShow(self, resultID)
            if resultID then
                self.resultID = resultID
                -- In Midnight the apply-phase search result is SECRET: activityID
                -- can be a secret value and activityIDs is a secret table whose
                -- indexing throws. Guard every read so we degrade to a nil
                -- activityID rather than erroring out the whole sign-up dialog.
                pcall(function()
                    -- Degrade to nil up-front so a mid-read throw cannot leave a
                    -- stale activityID from a previous dialog open.
                    self.activityID = nil
                    local info = C_LFGList.GetSearchResultInfo(resultID)
                    if type(info) ~= "table" then return end
                    local aid = info.activityID
                    if issecretvalue(aid) then aid = nil end
                    if aid == nil and info.activityIDs and not issecretvalue(info.activityIDs) then
                        aid = info.activityIDs[1]
                        if issecretvalue(aid) then aid = nil end
                    end
                    self.activityID = aid
                end)
            end
            LFGListApplicationDialog_UpdateRoles(self)
            StaticPopupSpecial_Show(self)
        end

        local function SyncPatch()
            if EllesmereUIDB and EllesmereUIDB.persistSignupNote then
                if not patched then
                    LFGListApplicationDialog_Show = PatchedShow
                    patched = true
                end
            else
                if patched then
                    LFGListApplicationDialog_Show = vanilla
                    patched = false
                end
            end
        end

        EllesmereUI._applyPersistSignupNote = SyncPatch
        SyncPatch()
    end

    ---------------------------------------------------------------------------
    --  Hide Blizzard Party / Raid Manager frame
    --  Implementation moved to the parent (EllesmereUI_BlizzardParty.lua) so the
    --  Raid Frames module shares the exact same logic + saved setting. The QoL
    --  options toggle still drives it via EllesmereUI._applyHideBlizzardPartyFrame.
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Hide Talking Head Frame
    --  The big NPC dialogue rectangle that pops up during quests/dungeons.
    ---------------------------------------------------------------------------
    do
        local function HookTalkingHead()
            local thf = _G.TalkingHeadFrame
            if not thf or EllesmereUI._GetFFD(thf).hooked then return end
            EllesmereUI._GetFFD(thf).hooked = true
            hooksecurefunc(thf, "PlayCurrent", function(self)
                if EllesmereUIDB and EllesmereUIDB.hideTalkingHead then
                    self:Hide()
                end
            end)
        end
        -- TalkingHeadFrame is load-on-demand; hook when it becomes available
        if _G.TalkingHeadFrame then
            HookTalkingHead()
        else
            local hookFrame = CreateFrame("Frame")
            hookFrame:RegisterEvent("ADDON_LOADED")
            hookFrame:SetScript("OnEvent", function(self, _, addon)
                if _G.TalkingHeadFrame then
                    HookTalkingHead()
                    self:UnregisterAllEvents()
                end
            end)
        end
    end

    ---------------------------------------------------------------------------
    --  Instance Reset Announce
    --  After a successful /reset, posts a message to instance chat so the
    --  whole group knows the instance is ready to re-enter.
    ---------------------------------------------------------------------------
    do
        -- Capture the player name once at login; used in the chat message.
        local playerName = UnitName("player") or "Unknown"

        -- We detect a successful reset by watching CHAT_MSG_SYSTEM for the
        -- Blizzard confirmation string.  The exact string varies by locale so
        -- we match the most common substrings used across all WoW clients.
        local RESET_PATTERNS = {
            "has been reset",           -- enUS / enGB
            "wurde zur",                -- deDE (zurückgesetzt)
            "a été réinitialisé",       -- frFR
            "ha sido reiniciada",       -- esES / esMX
            "è stato resettato",        -- itIT
            "foi reiniciada",           -- ptBR / ptPT
            "сброшен",                  -- ruRU
            "已重置",                    -- zhCN / zhTW
            "초기화되었습니다",           -- koKR
        }

        -- Patterns that indicate a reset FAILED because players are still inside.
        local FAIL_PATTERNS = {
            "players still",            -- enUS / enGB: "There are players still inside..."
            "noch spieler",             -- deDE
            "joueurs sont encore",      -- frFR
            "jugadores todavía",        -- esES / esMX
            "giocatori sono ancora",    -- itIT
            "jogadores ainda",          -- ptBR / ptPT
            "игроки ещё",               -- ruRU
            "还有玩家",                  -- zhCN
            "아직 플레이어",             -- koKR
        }

        local function MatchesAny(msg, patterns)
            if not msg then return false end
            local ok, lower = pcall(string.lower, msg)
            if not ok then return false end
            for _, pat in ipairs(patterns) do
                local ok2, result = pcall(string.find, lower, string.lower(pat), 1, true)
                if ok2 and result then
                    return true
                end
            end
            return false
        end

        local resetAnnounceFrame = CreateFrame("Frame")
        resetAnnounceFrame:RegisterEvent("CHAT_MSG_SYSTEM")
        resetAnnounceFrame:SetScript("OnEvent", function(self, event, msg)
            if not (EllesmereUIDB and EllesmereUIDB.instanceResetAnnounce) then return end

            -- Only announce if we are inside an instance group.
            -- IsInGroup(LE_PARTY_CATEGORY_INSTANCE) covers both party and raid
            -- inside an instance; fall back to IsInGroup() for older API.
            local inInstanceGroup = (IsInGroup and LE_PARTY_CATEGORY_INSTANCE and
                                     IsInGroup(LE_PARTY_CATEGORY_INSTANCE))
                                 or (IsInGroup and IsInGroup())

            if not inInstanceGroup then return end

            -- Small delay so Blizzard's own system message renders first.
            if MatchesAny(msg, RESET_PATTERNS) then
                C_Timer.After(0.3, function()
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    local customMsg = (EllesmereUIDB.instanceResetAnnounceMsg and
                                       EllesmereUIDB.instanceResetAnnounceMsg ~= "")
                                      and EllesmereUIDB.instanceResetAnnounceMsg
                                      or "Instance has been reset - you can re-enter now!"
                    SendChatMessage("[EUI] " .. customMsg, channel)
                end)
            elseif MatchesAny(msg, FAIL_PATTERNS) then
                C_Timer.After(0.3, function()
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    SendChatMessage("[EUI] Reset failed - there are still players inside the instance.", channel)
                end)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  24-Hour Clock Fix (Blizzard bug: CVar resets to 12h on every login)
    --  We save the user's preference when they toggle the checkbox, then
    --  restore it on login if Blizzard's bug reset it.
    ---------------------------------------------------------------------------
    do
        local saved = EllesmereUIDB and EllesmereUIDB.clockFormat24h
        -- Restore: only if user previously chose 24h and the CVar got reset
        if saved and GetCVar("timeMgrUseMilitaryTime") ~= "1" then
            C_Timer.After(0.5, function()
                if not TimeManagerFrame then
                    if TimeManager_LoadUI then TimeManager_LoadUI() end
                end
                local cb = TimeManagerMilitaryTimeCheck
                if cb then
                    cb:SetChecked(true)
                    local fn = cb:GetScript("OnClick")
                    if fn then fn(cb) end
                end
            end)
        end
        -- Track: hook the checkbox so we remember whenever the user changes it
        local function HookClockCheckbox()
            local cb = TimeManagerMilitaryTimeCheck
            if not cb then return end
            cb:HookScript("OnClick", function(self)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.clockFormat24h = self:GetChecked() and true or nil
            end)
        end
        -- The TimeManager may not be loaded yet; hook when it appears
        if TimeManagerMilitaryTimeCheck then
            HookClockCheckbox()
        else
            local hookFrame = CreateFrame("Frame")
            hookFrame:RegisterEvent("ADDON_LOADED")
            hookFrame:SetScript("OnEvent", function(self, _, addon)
                if addon == "Blizzard_TimeManager" then
                    self:UnregisterEvent("ADDON_LOADED")
                    HookClockCheckbox()
                end
            end)
        end
    end

end)

-------------------------------------------------------------------------------
--  Guild Chat Privacy
--  Streamer feature: overlay on CommunitiesFrame guild chat, click to reveal.
-------------------------------------------------------------------------------
do
    local overlay
    local function ShowOverlay()
        if not overlay then return end
        if not (EllesmereUIDB and EllesmereUIDB.guildChatPrivacy) then return end
        local cf = CommunitiesFrame
        if not cf or not cf.Chat or not cf.Chat.MessageFrame then return end
        local mf = cf.Chat.MessageFrame
        overlay:SetParent(mf)
        overlay:SetAllPoints(mf)
        overlay:SetFrameLevel(mf:GetFrameLevel() + 20)
        overlay:Show()
    end

    local function ApplyGuildChatPrivacy()
        local enabled = EllesmereUIDB and EllesmereUIDB.guildChatPrivacy
        if not enabled then
            if overlay then overlay:Hide() end
            return
        end

        if not overlay then
            overlay = CreateFrame("Button", nil, UIParent)
            overlay:SetFrameStrata("DIALOG")
            local bg = overlay:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", -2, 0)
            bg:SetPoint("BOTTOMRIGHT", 2, -4)
            bg:SetColorTexture(0.133, 0.133, 0.133, 1)
            local txt = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            txt:SetPoint("CENTER")
            txt:SetText("Click to Show")
            txt:SetTextColor(0.7, 0.7, 0.7, 1)
            overlay:SetScript("OnClick", function(self)
                self:Hide()
            end)
        end

        if CommunitiesFrame then
            ShowOverlay()
            if not overlay._hooked then
                CommunitiesFrame:HookScript("OnShow", ShowOverlay)
                overlay._hooked = true
            end
        else
            local loader = CreateFrame("Frame")
            loader:RegisterEvent("ADDON_LOADED")
            loader:SetScript("OnEvent", function(self, _, addon)
                if addon == "Blizzard_Communities" then
                    self:UnregisterAllEvents()
                    if EllesmereUIDB and EllesmereUIDB.guildChatPrivacy then
                        ShowOverlay()
                        if not overlay._hooked then
                            CommunitiesFrame:HookScript("OnShow", ShowOverlay)
                            overlay._hooked = true
                        end
                    end
                end
            end)
        end
    end
    EllesmereUI._applyGuildChatPrivacy = ApplyGuildChatPrivacy

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplyGuildChatPrivacy()
    end)
end

-------------------------------------------------------------------------------
--  Secondary Stats Display
--  On-screen overlay showing crit/haste/mastery/vers (+ optional tertiaries).
-------------------------------------------------------------------------------
do
    local statsFrame, statsText
    local format = string.format

    local function UpdateSecondaryStats()
        if not statsFrame or not statsFrame:IsShown() then return end
        if not statsFrame._classHex then
            local _, cls = UnitClass("player")
            local cc = cls and EllesmereUI.GetClassColor(cls)
            if cc then
                statsFrame._classR, statsFrame._classG, statsFrame._classB = cc.r, cc.g, cc.b
                statsFrame._classHex = format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
            else
                statsFrame._classR, statsFrame._classG, statsFrame._classB = 1, 1, 1
                statsFrame._classHex = "ffffff"
            end
        end
        local c = EllesmereUI.QoLExtrasGet("secondaryStatsColor")
        local cr, cg, cb
        if c then
            cr, cg, cb = c.r, c.g, c.b
        else
            cr, cg, cb = statsFrame._classR, statsFrame._classG, statsFrame._classB
        end
        local labelHex = c and format("%02x%02x%02x", cr * 255, cg * 255, cb * 255) or statsFrame._classHex

        local crit = GetCritChance("player")
        local haste = UnitSpellHaste("player")
        local mastery = GetMasteryEffect()
        local versRating = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
        local versBase = GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
        local vers = (issecretvalue(versRating) or issecretvalue(versBase)) and versRating or (versRating + versBase)

        local txt =
            format("|cff%sCrit:|r  |cffffffff%.2f%%|r", labelHex, crit) .. "\n" ..
            format("|cff%sHaste:|r  |cffffffff%.2f%%|r", labelHex, haste) .. "\n" ..
            format("|cff%sMastery:|r  |cffffffff%.2f%%|r", labelHex, mastery) .. "\n" ..
            format("|cff%sVers:|r  |cffffffff%.2f%%|r", labelHex, vers)

        if EllesmereUI.QoLExtrasGet("showTertiaryStats") then
            local tc = EllesmereUI.QoLExtrasGet("tertiaryStatsColor")
            local tr, tg, tb
            if tc then
                tr, tg, tb = tc.r, tc.g, tc.b
            else
                tr, tg, tb = statsFrame._classR, statsFrame._classG, statsFrame._classB
            end
            local tertHex = tc and format("%02x%02x%02x", tr * 255, tg * 255, tb * 255) or statsFrame._classHex

            local leech = GetLifesteal()
            local avoidance = GetAvoidance()
            local speed = GetSpeed()
            txt = txt .. "\n" ..
                format("|cff%sLeech:|r  |cffffffff%.2f%%|r", tertHex, leech) .. "\n" ..
                format("|cff%sAvoidance:|r  |cffffffff%.2f%%|r", tertHex, avoidance) .. "\n" ..
                format("|cff%sSpeed:|r  |cffffffff%.2f%%|r", tertHex, speed)
        end

        statsText:SetText(txt)
    end

    local function ApplySecondaryStats()
        local enabled = EllesmereUI.QoLExtrasGet("showSecondaryStats")
        if not enabled then
            if statsFrame then
                statsFrame:Hide()
                statsFrame:UnregisterAllEvents()
            end
            return
        end
        if not statsFrame then
            statsFrame = CreateFrame("Frame", "EUI_SecondaryStats", UIParent)
            statsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -12)
            statsFrame:SetSize(160, 60)
            statsFrame:SetFrameStrata("LOW")
            statsText = statsFrame:CreateFontString(nil, "OVERLAY")
            statsText:SetPoint("TOPLEFT")
            statsText:SetJustifyH("LEFT")
        end
        if statsText then
            local font = EllesmereUI.ResolveFontName(EllesmereUI.GetFontsDB().global)
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(statsText, EllesmereUI.GetFontUseShadow("extras")) end
            statsText:SetFont(font, 12, EllesmereUI.GetFontOutlineFlag("extras"))
        end
        local pos = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
        local scale = 1.0
        if pos then
            if pos.point then
                statsFrame:ClearAllPoints()
                statsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            end
            if pos.scale then
                scale = pos.scale
            end
        end
        if statsText then
            local font = EllesmereUI.ResolveFontName(EllesmereUI.GetFontsDB().global)
            local fontSize = math.floor(12 * scale + 0.5)
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(statsText, EllesmereUI.GetFontUseShadow("extras")) end
            statsText:SetFont(font, fontSize, EllesmereUI.GetFontOutlineFlag("extras"))
        end
        for _, ev in ipairs({
            "UNIT_STATS", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
            "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_SPELL_HASTE",
            "MASTERY_UPDATE", "SPELL_POWER_CHANGED", "PLAYER_DAMAGE_DONE_MODS",
            "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD",
        }) do
            statsFrame:RegisterEvent(ev)
        end
        local _statsPending = false
        statsFrame:SetScript("OnEvent", function(_, _, unit)
            if unit and unit ~= "player" then return end
            if _statsPending then return end
            _statsPending = true
            C_Timer.After(0.5, function()
                _statsPending = false
                UpdateSecondaryStats()
            end)
        end)
        statsFrame:Show()
        UpdateSecondaryStats()
    end
    EllesmereUI._applySecondaryStats = ApplySecondaryStats

    EllesmereUI._getSecondaryStatsFrame = function()
        if not statsFrame then
            ApplySecondaryStats()
        end
        return statsFrame
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplySecondaryStats()
    end)
end

-------------------------------------------------------------------------------
--  FPS Counter
-------------------------------------------------------------------------------
do
    local fpsFrame
    local floor = math.floor

    local function CreateFPSCounter()
        if fpsFrame then return end
        local FONT = EllesmereUI.GetFontPath("extras")
        local FONT_SIZE = EllesmereUI.QoLExtrasGet("fpsTextSize") or 12
        local LABEL_SIZE = FONT_SIZE - 2
        fpsFrame = CreateFrame("Frame", "EUI_FPSCounter", UIParent)
        fpsFrame:SetSize(60, 20)
        fpsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
        fpsFrame:SetFrameStrata("MEDIUM")
        fpsFrame:SetFrameLevel(10)
        fpsFrame:EnableMouse(false)

        local function MakeFS(size)
            local f = fpsFrame:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(f, EllesmereUI.GetFontUseShadow("extras")) end
            f:SetFont(FONT, size, EllesmereUI.GetFontOutlineFlag("extras"))
            f:SetTextColor(1, 1, 1, 1)
            return f
        end

        local fsFps = MakeFS(FONT_SIZE)
        fsFps:SetPoint("LEFT")
        fpsFrame._text = fsFps

        local DIV_W, DIV_H = 1, 10
        local DIV_PAD = 6

        local function MakeDivider()
            local d = fpsFrame:CreateTexture(nil, "OVERLAY")
            d:SetColorTexture(1, 1, 1, 0.25)
            d:SetSize(DIV_W, DIV_H)
            return d
        end

        local divWorld = MakeDivider()
        local fsWorldVal = MakeFS(FONT_SIZE)
        local fsWorldLbl = MakeFS(LABEL_SIZE)
        fpsFrame._divWorld = divWorld
        fpsFrame._textWorld = fsWorldVal

        local divLocal = MakeDivider()
        local fsLocalVal = MakeFS(FONT_SIZE)
        local fsLocalLbl = MakeFS(LABEL_SIZE)
        fpsFrame._divLocal = divLocal
        fpsFrame._textLocal = fsLocalVal

        local function UpdateFPS(self)
            local c = EllesmereUI.QoLExtrasGet("fpsColor")
            local cr, cg, cb, ca = 1, 1, 1, 1
            if c then cr, cg, cb, ca = c.r or 1, c.g or 1, c.b or 1, c.a or 1 end
            fsFps:SetTextColor(cr, cg, cb, ca)
            fsWorldVal:SetTextColor(cr, cg, cb, ca)
            fsWorldLbl:SetTextColor(cr, cg, cb, ca * 0.6)
            fsLocalVal:SetTextColor(cr, cg, cb, ca)
            fsLocalLbl:SetTextColor(cr, cg, cb, ca * 0.6)
            divWorld:SetColorTexture(cr, cg, cb, ca * 0.35)
            divLocal:SetColorTexture(cr, cg, cb, ca * 0.35)

            local fps = floor(GetFramerate() + 0.5)
            fsFps:SetText(fps .. " fps")

            local showWorld = EllesmereUI.QoLExtrasGet("fpsShowWorldMS")
            local _localMS = EllesmereUI.QoLExtrasGet("fpsShowLocalMS")
            local showLocal = (_localMS == nil) and true or _localMS
            local hideLabel = EllesmereUI.QoLExtrasGet("fpsHideLabel")
            local _, _, latHome, latWorld = GetNetStats()

            fsFps:ClearAllPoints()
            fsFps:SetPoint("LEFT", fpsFrame, "LEFT", 0, 0)
            local anchor = fsFps

            if showWorld then
                fsWorldVal:SetText(latWorld .. " ms")
                divWorld:ClearAllPoints()
                divWorld:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                divWorld:Show()
                fsWorldVal:ClearAllPoints()
                fsWorldVal:SetPoint("LEFT", divWorld, "RIGHT", DIV_PAD, 0)
                fsWorldVal:Show()
                if hideLabel then
                    fsWorldLbl:Hide()
                    anchor = fsWorldVal
                else
                    fsWorldLbl:SetText("(world)")
                    fsWorldLbl:ClearAllPoints()
                    fsWorldLbl:SetPoint("LEFT", fsWorldVal, "RIGHT", 3, 0)
                    fsWorldLbl:Show()
                    anchor = fsWorldLbl
                end
            else
                divWorld:Hide(); fsWorldVal:Hide(); fsWorldLbl:Hide()
            end

            if showLocal then
                fsLocalVal:SetText(latHome .. " ms")
                divLocal:ClearAllPoints()
                divLocal:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                divLocal:Show()
                fsLocalVal:ClearAllPoints()
                fsLocalVal:SetPoint("LEFT", divLocal, "RIGHT", DIV_PAD, 0)
                fsLocalVal:Show()
                if hideLabel then
                    fsLocalLbl:Hide()
                    anchor = fsLocalVal
                else
                    fsLocalLbl:SetText("(local)")
                    fsLocalLbl:ClearAllPoints()
                    fsLocalLbl:SetPoint("LEFT", fsLocalVal, "RIGHT", 3, 0)
                    fsLocalLbl:Show()
                    anchor = fsLocalLbl
                end
            else
                divLocal:Hide(); fsLocalVal:Hide(); fsLocalLbl:Hide()
            end

            local totalW = fsFps:GetStringWidth()
            if showWorld then
                totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + fsWorldVal:GetStringWidth()
                if not hideLabel then totalW = totalW + 3 + fsWorldLbl:GetStringWidth() end
            end
            if showLocal then
                totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + fsLocalVal:GetStringWidth()
                if not hideLabel then totalW = totalW + 3 + fsLocalLbl:GetStringWidth() end
            end
            self:SetSize(totalW + 4, 20)
        end

        local elapsed = 0
        fpsFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed < 1 then return end
            elapsed = 0
            UpdateFPS(self)
        end)
        fpsFrame._updateNow = function() elapsed = 0; UpdateFPS(fpsFrame) end
        fpsFrame:Hide()
    end

    EllesmereUI._applyFPSCounter = function()
        local shouldShow = EllesmereUI.QoLExtrasGet("showFPS")
        if shouldShow then
            CreateFPSCounter()
            local sz = EllesmereUI.QoLExtrasGet("fpsTextSize") or 12
            local lblSz = sz - 2
            local fp = EllesmereUI.GetFontPath("extras")
            local outF = EllesmereUI.GetFontOutlineFlag("extras")
            if fpsFrame._text then fpsFrame._text:SetFont(fp, sz, outF) end
            if fpsFrame._textWorld then fpsFrame._textWorld:SetFont(fp, sz, outF) end
            if fpsFrame._textLocal then fpsFrame._textLocal:SetFont(fp, sz, outF) end
            if fpsFrame._lblWorld then fpsFrame._lblWorld:SetFont(fp, lblSz, outF) end
            if fpsFrame._lblLocal then fpsFrame._lblLocal:SetFont(fp, lblSz, outF) end
            local pos = EllesmereUI.QoLExtrasGet("fpsPos")
            if pos and pos.point then
                if pos.scale then pcall(function() fpsFrame:SetScale(pos.scale) end) end
                fpsFrame:ClearAllPoints()
                fpsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            end
            fpsFrame._updateNow()
            fpsFrame:Show()
        elseif fpsFrame then
            fpsFrame:Hide()
        end
    end

    C_Timer.After(2, function()
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key = "EUI_FPS",
                label = "FPS Counter",
                group = "General",
                order = 700,
                getFrame = function()
                    if not fpsFrame then CreateFPSCounter() end
                    return fpsFrame
                end,
                getSize = function()
                    if fpsFrame then return fpsFrame:GetWidth(), fpsFrame:GetHeight() end
                    return 80, 20
                end,
                noResize = true,
                savePos = function(key, point, relPoint, x, y)
                    if not point then return end
                    EllesmereUI.QoLExtrasSet("fpsPos", { point = point, relPoint = relPoint, x = x, y = y })
                    if fpsFrame and not EllesmereUI._unlockActive then
                        fpsFrame:ClearAllPoints()
                        fpsFrame:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                    end
                end,
                loadPos = function()
                    return EllesmereUI.QoLExtrasGet("fpsPos")
                end,
                clearPos = function()
                    EllesmereUI.QoLExtrasSet("fpsPos", nil)
                end,
                applyPos = function()
                    if not fpsFrame then return end
                    local pos = EllesmereUI.QoLExtrasGet("fpsPos")
                    if pos and pos.point then
                        fpsFrame:ClearAllPoints()
                        fpsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            }),
        })
    end)

    C_Timer.After(2.5, function()
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key = "EUI_SecondaryStats",
                label = "Secondary Stats",
                group = "General",
                order = 710,
                getFrame = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    return f
                end,
                getSize = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 160, 60
                end,
                noResize = true,
                savePos = function(key, point, relPoint, x, y)
                    if not point then return end
                    -- Scale lives in this same table; carry it over so a drag doesn't wipe it.
                    local prev = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                    EllesmereUI.QoLExtrasSet("secondaryStatsPos", { point = point, relPoint = relPoint, x = x, y = y, scale = prev and prev.scale })
                    if not EllesmereUI._unlockActive then
                        local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                        if f then
                            f:ClearAllPoints()
                            f:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                        end
                    end
                end,
                loadPos = function()
                    return EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                end,
                clearPos = function()
                    EllesmereUI.QoLExtrasSet("secondaryStatsPos", nil)
                end,
                applyPos = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if not f then return end
                    local pos = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                    if pos and pos.point then
                        f:ClearAllPoints()
                        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            }),
        })
    end)

    local fpsBind = CreateFrame("Button", "EUI_FPSBindBtn", UIParent)
    fpsBind:Hide()
    fpsBind:SetScript("OnClick", function()
        EllesmereUI.QoLExtrasSet("showFPS", not EllesmereUI.QoLExtrasGet("showFPS"))
        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
    end)

    C_Timer.After(1, function()
        if EllesmereUI.QoLExtrasGet("showFPS") then
            EllesmereUI._applyFPSCounter()
        end
        local function ApplyFPSBind()
            if EllesmereUIDB and EllesmereUIDB.fpsToggleKey then
                SetOverrideBindingClick(fpsBind, true, EllesmereUIDB.fpsToggleKey, "EUI_FPSBindBtn")
            end
        end
        if InCombatLockdown() then
            local w = CreateFrame("Frame")
            w:RegisterEvent("PLAYER_REGEN_ENABLED")
            w:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                ApplyFPSBind()
            end)
        else
            ApplyFPSBind()
        end
    end)
end

-------------------------------------------------------------------------------
--  Durability Warning
-------------------------------------------------------------------------------
do
    local durWarnOverlay
    local function CreateDurabilityWarning()
        if durWarnOverlay then return end

        durWarnOverlay = CreateFrame("Frame", nil, UIParent)
        durWarnOverlay:SetSize(400, 40)
        durWarnOverlay:SetFrameStrata("HIGH")
        durWarnOverlay:SetFrameLevel(50)
        durWarnOverlay:EnableMouse(false)
        durWarnOverlay:SetMouseClickEnabled(false)

        local fs = durWarnOverlay:CreateFontString(nil, "OVERLAY")
        fs:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 18, EllesmereUI.GetFontOutlineFlag("extras"))
        fs:SetPoint("CENTER")
        fs:SetText("Low Durability")
        durWarnOverlay._text = fs

        local function ApplySettings()
            durWarnOverlay:ClearAllPoints()
            local pos = EllesmereUIDB and EllesmereUIDB.durWarnPos
            if pos and pos.point then
                durWarnOverlay:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 250)
            else
                local yOff = EllesmereUIDB and EllesmereUIDB.durWarnYOffset or 250
                durWarnOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, yOff)
            end
            durWarnOverlay:SetScale(1)

            local fontPath = EllesmereUI.GetFontPath("extras")
            local durSz = (EllesmereUIDB and EllesmereUIDB.durWarnTextSize) or 30
            fs:SetFont(fontPath, durSz, EllesmereUI.GetFontOutlineFlag("extras"))

            local c = EllesmereUIDB and EllesmereUIDB.durWarnColor
            if c then
                fs:SetTextColor(c.r, c.g, c.b, 1)
            else
                fs:SetTextColor(1, 0.27, 0.27, 1)
            end
        end
        durWarnOverlay._applySettings = ApplySettings

        local ag = fs:CreateAnimationGroup()
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.3)
        fadeOut:SetDuration(0.4)
        fadeOut:SetOrder(1)
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.3)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.4)
        fadeIn:SetOrder(2)
        ag:SetLooping("REPEAT")

        durWarnOverlay._show = function(pct)
            ApplySettings()
            durWarnOverlay._text:SetText("Low Durability (" .. math.floor(pct) .. "%)")
            durWarnOverlay:Show()
            ag:Play()
        end

        durWarnOverlay:SetScript("OnHide", function()
            ag:Stop()
        end)

        durWarnOverlay:Hide()
    end

    EllesmereUI._applyDurWarn = function()
        CreateDurabilityWarning()
        durWarnOverlay._applySettings()
    end
    EllesmereUI._durWarnApplySettings = EllesmereUI._applyDurWarn

    EllesmereUI._durWarnPreview = function()
        CreateDurabilityWarning()
        durWarnOverlay._show(25)
        durWarnOverlay._text:SetText("Low Durability (Preview)")
    end

    EllesmereUI._durWarnHidePreview = function()
        if durWarnOverlay then durWarnOverlay:Hide() end
    end

    local repairWarnFrame = CreateFrame("Frame", nil, UIParent)
    if not (EllesmereUIDB and EllesmereUIDB.repairWarning == false) then
        repairWarnFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        repairWarnFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        repairWarnFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        repairWarnFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    end

    local function CheckDurabilityAndShow()
        if not EllesmereUIDB then return end
        if EllesmereUIDB.repairWarning == false then
            if durWarnOverlay then durWarnOverlay:Hide() end
            return
        end
        if InCombatLockdown() then return end

        local lowestDur = 100
        for slot = 1, 18 do
            local cur, mx = GetInventoryItemDurability(slot)
            if cur and mx and mx > 0 then
                local pct = (cur / mx) * 100
                if pct < lowestDur then lowestDur = pct end
            end
        end

        if lowestDur < (EllesmereUIDB.durWarnThreshold or 40) then
            CreateDurabilityWarning()
            durWarnOverlay._show(lowestDur)
        elseif durWarnOverlay then
            durWarnOverlay:Hide()
        end
    end

    repairWarnFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if durWarnOverlay then durWarnOverlay:Hide() end
            return
        end
        CheckDurabilityAndShow()
    end)
end

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

-------------------------------------------------------------------------------
--  Pixel-Perfect UI Scale
-------------------------------------------------------------------------------
do
    local function ApplyPPUIScale()
        local scale = EllesmereUIDB and EllesmereUIDB.ppUIScale
        if not scale then return end
        local mf = EllesmereUI._mainFrame
        local panelScaleBefore
        if mf then panelScaleBefore = mf:GetEffectiveScale() end
        EllesmereUI.PP.SetUIScale(scale)
        if mf and panelScaleBefore then
            local newEff = UIParent:GetEffectiveScale()
            if newEff > 0 then mf:SetScale(panelScaleBefore / newEff) end
        end
    end

    EllesmereUI._applyPPUIScale = ApplyPPUIScale

    local ppScaleFrame = CreateFrame("Frame")
    ppScaleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    ppScaleFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        ApplyPPUIScale()
    end)
end

-------------------------------------------------------------------------------
--  Disable Right Click Targeting
-------------------------------------------------------------------------------
do
    local mlookBtn = CreateFrame("Button", "EUI_MouseLookBtn", UIParent)
    mlookBtn:RegisterForClicks("AnyDown", "AnyUp")
    mlookBtn:SetScript("OnClick", function(_, _, down)
        if down then MouselookStart() else MouselookStop() end
    end)

    local stateFrame = CreateFrame("Frame", "EUI_NoRightClickState", UIParent, "SecureHandlerStateTemplate")

    local function ApplyRightClickTarget()
        if InCombatLockdown() then
            local deferFrame = CreateFrame("Frame")
            deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            deferFrame:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                ApplyRightClickTarget()
            end)
            return
        end
        local db = EllesmereUIDB
        local enemy = db and db.disableRightClickTarget
        local allyCombat = db and db.disableRightClickTargetAllyCombat
        if enemy or allyCombat then
            -- Build the mouseover condition from the two independent toggles.
            -- Enemies fire everywhere. Allies only fire while the player is in
            -- combat (the [combat] conditional), so right clicking friendly NPCs
            -- such as vendors and quest givers still works out of combat.
            local macro = ""
            if enemy then macro = macro .. "[@mouseover,harm,nodead]1;" end
            if allyCombat then macro = macro .. "[@mouseover,help,nodead,combat]1;" end
            macro = macro .. "0"
            SecureStateDriverManager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
            -- [combat] needs regen events so the state re-evaluates on combat
            -- enter/exit even when the mouseover unit has not changed.
            if allyCombat then
                SecureStateDriverManager:RegisterEvent("PLAYER_REGEN_DISABLED")
                SecureStateDriverManager:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
            RegisterStateDriver(stateFrame, "mov", macro)
            stateFrame:SetAttribute("_onstate-mov", [[
                if newstate == 1 then
                    self:SetBindingClick(1, "BUTTON2", "EUI_MouseLookBtn")
                else
                    self:ClearBindings()
                end
            ]])
        else
            UnregisterStateDriver(stateFrame, "mov")
            ClearOverrideBindings(stateFrame)
        end
    end

    EllesmereUI._applyRightClickTarget = ApplyRightClickTarget

    local rcInitFrame = CreateFrame("Frame")
    rcInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rcInitFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        ApplyRightClickTarget()
    end)
end

-------------------------------------------------------------------------------
--  Character Crosshair
-------------------------------------------------------------------------------
do
    local crosshairFrame

    -- Crosshair settings: the account-wide EllesmereUIDB root is the inherited
    -- global default (preserved, never cleared); the QoL per-profile DB holds
    -- per-profile settings. Existing users keep their current crosshair until a
    -- profile overrides it.
    -- CrosshairDB() is nil until the Cursor module creates it.
    local function CrosshairDB()
        return _G._ECL_AceDB and _G._ECL_AceDB.profile
    end
    EllesmereUI.GetCrosshairDB = CrosshairDB

    -- Effective read: profile override -> global root -> nil (inline default).
    local function CrosshairGet(k)
        local p = CrosshairDB()
        if p and p[k] ~= nil then return p[k] end
        return EllesmereUIDB and EllesmereUIDB[k]
    end
    EllesmereUI.GetCrosshairValue = CrosshairGet

    -- Item-based range detection for all specs
    local rangedSpecIDs = {
        [102] = true, [105] = true, -- Druid: Balance, Resto
        [1467] = true, [1468] = true, [1470] = true, -- Evoker: Devastation, Preservation, Augmentation
        [253] = true, [254] = true, -- Hunter: Beast Mastery, Marksmanship
        [62] = true, [63] = true, [64] = true, -- Mage: Arcane, Fire, Frost
        [270] = true, -- Monk: Mistweaver
        [65] = true, -- Paladin: Holy
        [256] = true, [257] = true, [258] = true, -- Priest: Discipline, Holy, Shadow
        [262] = true, [264] = true, -- Shaman: Elemental, Restoration
        [265] = true, [266] = true, [267] = true, -- Warlock: Affliction, Demonology, Destruction
    }

    local checkItems = {
        { range = 5,   id = 37727 }, -- Ruby Acorn
        { range = 8,   id = 34368 }, -- Attuned Crystal Cores
        { range = 10,  id = 10699 }, -- Handful of Snowflakes
        { range = 15,  id = 31129 }, -- Blackwhelp Net
        { range = 20,  id = 21519 }, -- Mistletoe
        { range = 25,  id = 13289 }, -- Egan's Blaster
        { range = 30,  id = 17202 }, -- Snowball
        { range = 35,  id = 18904 }, -- Zorbin's Ultra-Shrinker
        { range = 40,  id = 18640 }, -- Happy Fun Rock
        { range = 45,  id = 32698 }, -- Wrangling Rope
        { range = 60,  id = 32825 }, -- Soul Cannon
        { range = 80,  id = 35278 }, -- Reinforced Net
    }

    local DRUID_MELEE_FORMS = { [1] = true, [2] = true }  -- Bear, Cat

    local _, _chPlayerClass = UnitClass("player")
    local _crosshairCutoffRange = 5

    local function RefreshCrosshairCutoffRange()
        local _, classFile = UnitClass("player")
        local specIndex = GetSpecialization()
        if not specIndex then
            _crosshairCutoffRange = 5
            return
        end
        
        local specID = GetSpecializationInfo(specIndex)
        if not specID then
            _crosshairCutoffRange = 5
            return
        end
        
        if classFile == "DRUID" then
            if specID == 102 or specID == 105 then -- Balance, Restoration
                if IsPlayerSpell(197488) then -- Astral Influence
                    _crosshairCutoffRange = 45
                else
                    _crosshairCutoffRange = 40
                end
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "DEMONHUNTER" then
            if specIndex == 3 or (specID ~= 577 and specID ~= 581) then
                _crosshairCutoffRange = 25 -- Devourer
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "EVOKER" then
            if specID == 1467 or specID == 1470 then -- Devastation, Augmentation
                _crosshairCutoffRange = 25
            elseif specID == 1468 then -- Preservation
                _crosshairCutoffRange = 30
            else
                _crosshairCutoffRange = 25
            end
        elseif classFile == "HUNTER" then
            if specID == 253 or specID == 254 then -- Beast Mastery, Marksmanship
                _crosshairCutoffRange = 40
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "PALADIN" then
            if specID == 65 then -- Holy
                _crosshairCutoffRange = 40
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "SHAMAN" then
            if specID == 263 then -- Enhancement
                _crosshairCutoffRange = 5
            else
                _crosshairCutoffRange = 40
            end
        elseif classFile == "MONK" then
            if specID == 270 then -- Mistweaver
                _crosshairCutoffRange = 40
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "PRIEST" or classFile == "MAGE" or classFile == "WARLOCK" then
            _crosshairCutoffRange = 40
        else -- WARRIOR, ROGUE, DEATHKNIGHT
            _crosshairCutoffRange = 5
        end
    end
    RefreshCrosshairCutoffRange()

    EllesmereUI._getCrosshairCutoffRange = function()
        if _chPlayerClass == "DRUID" and DRUID_MELEE_FORMS[GetShapeshiftForm()] then
            return 5
        end
        return _crosshairCutoffRange
    end

    -- True only when there is an attackable, living target out of range.
    local function TargetOutOfRange()
        if not (UnitExists("target") and UnitCanAttack("player", "target")
                and not UnitIsDead("target")) then
            return false
        end
        local cutoff = EllesmereUI._getCrosshairCutoffRange()
        
        local maxRange = nil
        for _, item in ipairs(checkItems) do
            local inRange = C_Item.IsItemInRange(item.id, "target")
            if inRange == true then
                maxRange = item.range
                break
            end
            if item.range >= cutoff then
                break
            end
        end
        
        return (maxRange == nil) or (maxRange > cutoff)
    end

    local function CreateCrosshair()
        if crosshairFrame then return end
        crosshairFrame = CreateFrame("Frame", "EUI_CharacterCrosshair", UIParent)
        -- MEDIUM sits above gameplay HUD but below DIALOG/HIGH panels (talents, character, etc.).
        crosshairFrame:SetFrameStrata("MEDIUM")
        crosshairFrame:SetFrameLevel(100)
        crosshairFrame:EnableMouse(false)
        crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        crosshairFrame:SetSize(1, 1)

        local function MakeArm(layer)
            local t = crosshairFrame:CreateTexture(nil, layer or "OVERLAY")
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            return t
        end
        -- Borders sit on artwork so the overlay arms render on top of them.
        crosshairFrame._hBorder = MakeArm("ARTWORK")
        crosshairFrame._vBorder = MakeArm("ARTWORK")
        crosshairFrame._hBar = MakeArm("OVERLAY")
        crosshairFrame._vBar = MakeArm("OVERLAY")

        -- Optional on-screen warning text shown while the target is out of melee
        -- range (configured in _applyCrosshair; hidden until the OnUpdate shows it).
        crosshairFrame._meleeText = crosshairFrame:CreateFontString(nil, "OVERLAY")
        crosshairFrame._meleeText:Hide()

        -- Throttled recolor/text-toggle when the target is out of melee range.
        -- No-ops unless a melee feature is enabled and the class has a mapped spell.
        local meleeAccum = 0
        crosshairFrame:SetScript("OnUpdate", function(self, elapsed)
            meleeAccum = meleeAccum + elapsed
            if meleeAccum < 0.15 then return end
            meleeAccum = 0
            local nc = self._normalColor
            if not nc then return end
            local colorOn = CrosshairGet("crosshairMeleeColorEnabled")
            local textOn  = CrosshairGet("crosshairMeleeTextEnabled")
            if not (_meleeSpell and (colorOn or textOn)) then
                if self._meleeActive then
                    self._meleeActive = false
                    self._hBar:SetColorTexture(nc.r, nc.g, nc.b, nc.a)
                    self._vBar:SetColorTexture(nc.r, nc.g, nc.b, nc.a)
                    if self._meleeText then self._meleeText:Hide() end
                end
                return
            end
            local outOfRange = TargetOutOfRange()
            if outOfRange ~= self._meleeActive then
                self._meleeActive = outOfRange
                -- Recolor the arms only when the colour feature is on; otherwise
                -- keep them at the normal colour.
                if colorOn then
                    local c = outOfRange and (CrosshairGet("crosshairMeleeColor") or { r = 1, g = 0, b = 0, a = 1 }) or nc
                    self._hBar:SetColorTexture(c.r or 1, c.g or 0, c.b or 0, c.a or 1)
                    self._vBar:SetColorTexture(c.r or 1, c.g or 0, c.b or 0, c.a or 1)
                else
                    self._hBar:SetColorTexture(nc.r, nc.g, nc.b, nc.a)
                    self._vBar:SetColorTexture(nc.r, nc.g, nc.b, nc.a)
                end
                -- Toggle the warning text independently of the colour feature.
                if self._meleeText then
                    if textOn and outOfRange then self._meleeText:Show() else self._meleeText:Hide() end
                end
            end
        end)
    end

    -- Hardcoded presets (the original look): thickness + total arm length. The
    -- options dropdown stamps these onto the H/V Width/Length values, and they
    -- are the fallback here when those values are unset. Cog sliders fine-tune.
    EllesmereUI.CROSSHAIR_PRESETS = {
        Thin   = { width = 1, length = 40 },
        Normal = { width = 2, length = 40 },
        Thick  = { width = 3, length = 40 },
    }

    EllesmereUI._applyCrosshair = function()
        local PP = EllesmereUI.PP
        -- Effective reads (profile override -> global root -> inline default)
        local G = CrosshairGet
        local size = G("crosshairSize") or "None"
        if size == "None" then
            if crosshairFrame then crosshairFrame:Hide() end
            return
        end

        CreateCrosshair()

        local c = G("crosshairColor")
        local cr = c and c.r or 1
        local cg = c and c.g or 1
        local cb = c and c.b or 1
        local ca = c and c.a or 0.75

        -- Preset gives the baseline width/length, sliders override per axis.
        local preset = EllesmereUI.CROSSHAIR_PRESETS[size] or EllesmereUI.CROSSHAIR_PRESETS.Normal
        local hWidth = G("crosshairHWidth") or preset.width
        local vWidth = G("crosshairVWidth") or preset.width
        local hLen   = G("crosshairHLength") or preset.length
        local vLen   = G("crosshairVLength") or preset.length
        local xOff   = G("crosshairXOffset") or 0
        local yOff   = G("crosshairYOffset") or 0
        local bSize  = G("crosshairBorderSize") or 0
        local bc     = G("crosshairBorderColor") or { r = 0, g = 0, b = 0, a = 1 }

        -- (0,0) = screen center
        crosshairFrame:ClearAllPoints()
        crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", xOff, yOff)

        local hBar, vBar = crosshairFrame._hBar, crosshairFrame._vBar
        local hBorder, vBorder = crosshairFrame._hBorder, crosshairFrame._vBorder

        hBar:ClearAllPoints()
        hBar:SetSize(PP.Scale(hLen), PP.Scale(hWidth))
        hBar:SetPoint("CENTER", crosshairFrame, "CENTER", 0, 0)
        hBar:SetColorTexture(cr, cg, cb, ca)

        vBar:ClearAllPoints()
        vBar:SetSize(PP.Scale(vWidth), PP.Scale(vLen))
        vBar:SetPoint("CENTER", crosshairFrame, "CENTER", 0, 0)
        vBar:SetColorTexture(cr, cg, cb, ca)

        -- Base colour for the out-of-melee-range recolor, reset the melee state
        -- so the OnUpdate re-applies the range colour/text next tick if still needed.
        crosshairFrame._normalColor = { r = cr, g = cg, b = cb, a = ca }
        crosshairFrame._meleeActive = false

        -- Out-of-melee warning text: shares the melee-range colour, positioned
        -- relative to the crosshair centre. Hidden here; OnUpdate re-shows it.
        local mt = crosshairFrame._meleeText
        if mt then
            local tSize = G("crosshairMeleeTextSize") or 16
            mt:SetFont(STANDARD_TEXT_FONT, tSize, "OUTLINE")
            local txt = G("crosshairMeleeText")
            if txt == nil or txt == "" then txt = "OUT OF MELEE" end
            mt:SetText(txt)
            local mc = G("crosshairMeleeColor") or { r = 1, g = 0, b = 0, a = 1 }
            mt:SetTextColor(mc.r or 1, mc.g or 0, mc.b or 0, mc.a or 1)
            local tyo = G("crosshairMeleeTextYOffset")
            if tyo == nil then tyo = 40 end
            mt:ClearAllPoints()
            mt:SetPoint("CENTER", crosshairFrame, "CENTER", 0, tyo)
            mt:Hide()
        end

        -- Pixel border: a slightly larger bar of border colour behind each arm.
        if bSize and bSize > 0 then
            local bp = PP.Scale(bSize)
            local br, bg, bb, ba = bc.r or 0, bc.g or 0, bc.b or 0, bc.a or 1
            hBorder:ClearAllPoints()
            hBorder:SetSize(PP.Scale(hLen) + bp * 2, PP.Scale(hWidth) + bp * 2)
            hBorder:SetPoint("CENTER", crosshairFrame, "CENTER", 0, 0)
            hBorder:SetColorTexture(br, bg, bb, ba)
            hBorder:Show()
            vBorder:ClearAllPoints()
            vBorder:SetSize(PP.Scale(vWidth) + bp * 2, PP.Scale(vLen) + bp * 2)
            vBorder:SetPoint("CENTER", crosshairFrame, "CENTER", 0, 0)
            vBorder:SetColorTexture(br, bg, bb, ba)
            vBorder:Show()
        else
            hBorder:Hide()
            vBorder:Hide()
        end

        -- Visibility: always / combat / instances / instances_combat (both).
        local vis = G("crosshairVisibility") or "always"
        local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
        local show = true
        if vis == "combat" then
            show = inCombat
        elseif vis == "instances" then
            show = IsInInstance()
        elseif vis == "instances_combat" then
            show = IsInInstance() and inCombat
        end
        if show then crosshairFrame:Show() else crosshairFrame:Hide() end
    end

    -- Re-evaluate visibility on combat / zone transitions, and refresh the
    -- cached melee spell when the spec changes.
    do
        local visWatch = CreateFrame("Frame")
        visWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
        visWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        visWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
        visWatch:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        visWatch:RegisterEvent("TRAIT_CONFIG_UPDATED")
        visWatch:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "TRAIT_CONFIG_UPDATED" then
                RefreshCrosshairCutoffRange()
            end
            -- _applyCrosshair self-guards: nil DB -> returns, "None" -> hides,
            -- and runs the one-time migration once the profile DB is ready.
            if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
        end)
    end

    C_Timer.After(1, function()
        if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
    end)

    ---------------------------------------------------------------------------
    --  Map Coordinates
    ---------------------------------------------------------------------------
    do
        local coordFrame
        local coordText

        local function CreateCoordFrame()
            if coordFrame then return end
            local mapLoaded = C_AddOns.IsAddOnLoaded("Blizzard_WorldMap")
            if not mapLoaded or not WorldMapFrame then return end

            coordFrame = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
            coordFrame:SetFrameStrata("HIGH")
            coordFrame:SetSize(1, 1)
            coordFrame:SetPoint("BOTTOM", WorldMapFrame.ScrollContainer, "BOTTOM", 0, 10)

            local PP = EllesmereUI.PanelPP
            local fp = EllesmereUI.GetFontPath("extras")
            local outF = EllesmereUI.GetFontOutlineFlag("extras")
            local sz = (EllesmereUIDB and EllesmereUIDB.mapCoordsTextSize) or 12

            local divider = coordFrame:CreateTexture(nil, "OVERLAY")
            divider:SetColorTexture(1, 1, 1, 0.9)
            PP.Size(divider, 2, sz)
            divider:SetPoint("BOTTOM", coordFrame, "BOTTOM", 0, 0)

            local useShadow = EllesmereUI.GetFontUseShadow("extras")

            local cursorFS = coordFrame:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(cursorFS, useShadow) end
            cursorFS:SetFont(fp, sz, outF)
            cursorFS:SetTextColor(1, 1, 1, 0.9)
            cursorFS:SetJustifyH("RIGHT")
            cursorFS:SetPoint("RIGHT", divider, "LEFT", -10, 0)

            local playerFS = coordFrame:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(playerFS, useShadow) end
            playerFS:SetFont(fp, sz, outF)
            playerFS:SetTextColor(1, 1, 1, 0.9)
            playerFS:SetJustifyH("LEFT")
            playerFS:SetPoint("LEFT", divider, "RIGHT", 10, 0)

            coordText = { cursor = cursorFS, player = playerFS, divider = divider }

            local elapsed = 0
            coordFrame:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + dt
                if elapsed < 0.05 then return end
                elapsed = 0
                local mapID = WorldMapFrame:GetMapID()
                if not mapID then
                    cursorFS:SetText("")
                    playerFS:SetText("")
                    divider:Hide()
                    return
                end
                -- Player position (hidden in instances)
                local playerPos = C_Map.GetPlayerMapPosition(mapID, "player")
                local hasPlayer = false
                if playerPos then
                    local px, py = playerPos:GetXY()
                    if px and py and px > 0 and py > 0 then
                        playerFS:SetText("P: " .. format("%.0f, %.0f", px * 100, py * 100))
                        hasPlayer = true
                    end
                end
                if hasPlayer then
                    divider:Show()
                    playerFS:Show()
                else
                    divider:Hide()
                    playerFS:Hide()
                end

                -- Cursor position
                local cText = "0, 0"
                local child = WorldMapFrame.ScrollContainer.Child
                if child and child:IsMouseOver() then
                    local cx, cy = child:GetSize()
                    if cx and cx > 0 and cy and cy > 0 then
                        local scale = child:GetEffectiveScale()
                        local left = child:GetLeft()
                        local top = child:GetTop()
                        if scale and left and top then
                            local curX, curY = GetCursorPosition()
                            local nx = (curX / scale - left) / cx
                            local ny = (top - curY / scale) / cy
                            if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
                                cText = format("%.0f, %.0f", nx * 100, ny * 100)
                            end
                        end
                    end
                end

                cursorFS:SetText("C: " .. cText)
            end)
        end

        EllesmereUI._applyMapCoords = function()
            local enabled = EllesmereUIDB and EllesmereUIDB.mapCoords
            if enabled then
                CreateCoordFrame()
                if coordFrame then
                    local PP = EllesmereUI.PanelPP
                    local fp = EllesmereUI.GetFontPath("extras")
                    local outF = EllesmereUI.GetFontOutlineFlag("extras")
                    local useShadow = EllesmereUI.GetFontUseShadow("extras")
                    local sz = (EllesmereUIDB and EllesmereUIDB.mapCoordsTextSize) or 12
                    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(coordText.cursor, useShadow) end
                    coordText.cursor:SetFont(fp, sz, outF)
                    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(coordText.player, useShadow) end
                    coordText.player:SetFont(fp, sz, outF)
                    PP.Size(coordText.divider, 2, sz)
                    coordFrame:Show()
                end
            elseif coordFrame then
                coordFrame:Hide()
            end
        end

        -- WorldMapFrame is load-on-demand; hook when it loads
        if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            EllesmereUI._applyMapCoords()
        else
            local loader = CreateFrame("Frame")
            loader:RegisterEvent("ADDON_LOADED")
            loader:SetScript("OnEvent", function(self, _, addonName)
                if addonName == "Blizzard_WorldMap" then
                    self:UnregisterEvent("ADDON_LOADED")
                    EllesmereUI._applyMapCoords()
                end
            end)
        end
    end
end

-------------------------------------------------------------------------------
--  Hide Error Messages
--  Swallows the red UIErrorsFrame spam (e.g. "Not enough rage", "Ability is
--  not ready yet") while keeping a short whitelist of genuinely useful errors
--  visible. The OnEvent override is only installed while the option is on, so
--  it costs nothing for anyone who leaves it off.
-------------------------------------------------------------------------------
do
    local origOnEvent
    local installed = false

    -- Errors worth keeping even while the rest are hidden. Built lazily so we
    -- only touch the ERR_* globals when someone actually enables the feature.
    local keep
    local function BuildKeepList()
        if keep then return end
        keep = {}
        for _, msg in ipairs({
            ERR_INV_FULL, ERR_QUEST_LOG_FULL, ERR_RAID_GROUP_ONLY,
            ERR_PARTY_LFG_BOOT_LIMIT, ERR_PARTY_LFG_BOOT_DUNGEON_COMPLETE,
            ERR_PARTY_LFG_BOOT_IN_COMBAT, ERR_PARTY_LFG_BOOT_IN_PROGRESS,
            ERR_PARTY_LFG_BOOT_LOOT_ROLLS, ERR_PARTY_LFG_TELEPORT_IN_COMBAT,
            ERR_PET_SPELL_DEAD, ERR_PLAYER_DEAD,
            SPELL_FAILED_TARGET_NO_POCKETS, ERR_ALREADY_PICKPOCKETED,
        }) do
            if msg then keep[msg] = true end
        end
    end

    -- The group-kick "not eligible" line is a format string, so it needs a
    -- pattern match rather than a plain equality check.
    local function IsBootNotEligible(err)
        if type(err) ~= "string" or not ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S then return false end
        local ok, found = pcall(function()
            return err:find(string.format(ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S, ".+"))
        end)
        return (ok and found) and true or false
    end

    local function FilteredOnEvent(self, event, id, err, ...)
        if event == "UI_ERROR_MESSAGE" then
            if keep[err] or IsBootNotEligible(err) then
                return origOnEvent(self, event, id, err, ...)
            end
            return
        end
        return origOnEvent(self, event, id, err, ...)
    end

    local function ApplyHideErrorMessages()
        local on = EllesmereUIDB and EllesmereUIDB.hideErrorMessages
        if on and not installed then
            BuildKeepList()
            origOnEvent = UIErrorsFrame:GetScript("OnEvent")
            UIErrorsFrame:SetScript("OnEvent", FilteredOnEvent)
            UIParent:UnregisterEvent("PING_SYSTEM_ERROR")
            installed = true
        elseif not on and installed then
            UIErrorsFrame:SetScript("OnEvent", origOnEvent)
            origOnEvent = nil
            UIParent:RegisterEvent("PING_SYSTEM_ERROR")
            installed = false
        end
    end
    EllesmereUI._applyHideErrorMessages = ApplyHideErrorMessages

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if EllesmereUIDB and EllesmereUIDB.hideErrorMessages then
            ApplyHideErrorMessages()
        end
    end)
end

-------------------------------------------------------------------------------
--  Hide Tutorial Pop-ups
-------------------------------------------------------------------------------
do
    local function Enabled()
        return EllesmereUIDB and EllesmereUIDB.hideTutorials
    end

    -- "i" circles are MainHelpPlateButtons, matched by a method copied from the
    -- Blizzard mixin. Blizzard_HelpPlate is load-on-demand; resolve lazily and
    -- only cache once it exists.
    local fingerprint
    local function GetFingerprint()
        if not fingerprint and MainHelpPlateButtonMixin then
            fingerprint = MainHelpPlateButtonMixin.ShowTooltip
        end
        return fingerprint
    end

    local hiddenByUs = setmetatable({}, { __mode = "k" })
    local function HideButton(btn)
        btn:SetAlpha(0)
        btn:EnableMouse(false)
        hiddenByUs[btn] = true
    end

    -- Hoisted out of the pcall so we reuse one function instead of allocating a
    -- closure on every call (this runs on each panel open + each HelpTip show).
    local function DoHideOpenTips()
        for tip in HelpTip.framePool:EnumerateActive() do
            if tip:IsShown() then
                local info = tip.info
                if info and info.cvarBitfield and info.bitfieldFlag then
                    SetCVarBitfield(info.cvarBitfield, info.bitfieldFlag, true)
                end
                tip:Hide()
            end
        end
    end
    local function HideOpenTips()
        if not (HelpTip and HelpTip.framePool and HelpTip.framePool.EnumerateActive) then return end
        pcall(DoHideOpenTips)
    end

    local HideButtonsUnder
    local function ScanChildren(...)
        for i = 1, select("#", ...) do
            HideButtonsUnder((select(i, ...)))
        end
    end
    function HideButtonsUnder(root)
        if not root then return end
        local fp = GetFingerprint()
        if not fp then return end
        if root.ShowTooltip == fp then HideButton(root) end
        if root.GetChildren then ScanChildren(root:GetChildren()) end
    end

    -- One-time full walk (no allocation, never on a timer) to catch panels that
    -- are already open the moment the feature is switched on.
    local function SweepAll()
        local fp = GetFingerprint()
        if not fp then return end
        local frame = EnumerateFrames()
        while frame do
            if frame.ShowTooltip == fp then HideButton(frame) end
            frame = EnumerateFrames(frame)
        end
    end

    local function RestoreButtons()
        for btn in pairs(hiddenByUs) do
            btn:SetAlpha(1)
            btn:EnableMouse(true)
            hiddenByUs[btn] = nil
        end
    end

    -- Core hooks (HelpTip + ShowUIPanel) install once, only via ApplyHideTutorials
    -- when the feature is enabled. Each body also gates on Enabled().
    local coreHooked = false
    local function InstallCoreHooks()
        if coreHooked then return end
        coreHooked = true
        if HelpTip and HelpTip.Show then
            hooksecurefunc(HelpTip, "Show", function()
                if Enabled() then HideOpenTips() end
            end)
        end
        if ShowUIPanel then
            hooksecurefunc("ShowUIPanel", function(frame)
                if Enabled() and frame then
                    HideButtonsUnder(frame)
                    HideOpenTips()
                end
            end)
        end
    end

    local tooltipHooked = false
    local function InstallTooltipHook()
        if tooltipHooked or not HelpPlateTooltip then return end
        tooltipHooked = true
        if HelpPlate and HelpPlate.ShowTutorialTooltip then
            hooksecurefunc(HelpPlate, "ShowTutorialTooltip", function()
                if Enabled() and HelpPlateTooltip then HelpPlateTooltip:Hide() end
            end)
        end
        if HelpPlateTooltip.Init then
            hooksecurefunc(HelpPlateTooltip, "Init", function(self)
                if Enabled() then self:Hide() end
            end)
        end
    end

    local weSetCVar = false
    local function ApplyHideTutorials()
        if Enabled() then
            InstallCoreHooks()
            InstallTooltipHook()
            pcall(SetCVar, "hideHelptips", "1")
            pcall(SetCVar, "showTutorials", "0")
            weSetCVar = true
            SweepAll()
            HideOpenTips()
        else
            if weSetCVar then
                pcall(SetCVar, "hideHelptips", "0")
                pcall(SetCVar, "showTutorials", "1")
                weSetCVar = false
            end
            RestoreButtons()
        end
    end
    EllesmereUI._applyHideTutorials = ApplyHideTutorials

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" then
            -- Gated: nothing is hooked while the feature is off.
            if addon == "Blizzard_HelpPlate" and Enabled() then
                InstallTooltipHook()
            end
            return
        end
        ApplyHideTutorials()  -- PLAYER_LOGIN
    end)
end

-------------------------------------------------------------------------------
--  Group Death Announcer
--  Shows a large center-screen "<name> DIED!" alert when a party or raid
--  member dies. Midnight removed the combat log, so deaths are detected by
--  polling group units for an alive -> dead transition (feign death and the
--  player's own death are excluded). Fully gated: no ticker runs while the
--  option is off or while solo.
-------------------------------------------------------------------------------
do
    local POLL_INTERVAL = 0.35
    local alertOverlay
    local ticker
    local watcher
    local installed = false
    local deadState = {}   -- [guid] = true while dead/ghost, false while alive

    local DEFAULT_TEXT_SIZE = 34

    -- Applies the configured font size and saved position (or the default
    -- center-top placement) to the overlay.
    local function ApplyOverlaySettings()
        if not alertOverlay then return end
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
            or EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
        local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("extras"))
            or "OUTLINE"
        local size = (EllesmereUIDB and EllesmereUIDB.groupDeathTextSize) or DEFAULT_TEXT_SIZE
        alertOverlay._text:SetFont(fontPath, size, outline)
        -- Keep the frame (and therefore the unlock-mode mover) compact and sized
        -- to roughly the alert text rather than a fixed wide box.
        alertOverlay:SetSize(size * 7, size + 14)

        alertOverlay:ClearAllPoints()
        local pos = EllesmereUIDB and EllesmereUIDB.groupDeathAlertPos
        if pos and pos.point then
            alertOverlay:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        else
            alertOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
        end
    end

    local function CreateAlertOverlay()
        if alertOverlay then return end

        alertOverlay = CreateFrame("Frame", nil, UIParent)
        alertOverlay:SetSize(240, 50)
        alertOverlay:SetFrameStrata("HIGH")
        alertOverlay:SetFrameLevel(60)
        alertOverlay:EnableMouse(false)
        alertOverlay:SetMouseClickEnabled(false)

        local fs = alertOverlay:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER")
        alertOverlay._text = fs
        ApplyOverlaySettings()

        -- Quick fade-in, brief hold, fade-out; hide when finished.
        local ag = alertOverlay:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.15); fadeIn:SetOrder(1)
        local hold = ag:CreateAnimation("Alpha")
        hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.6); hold:SetOrder(2)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.6); fadeOut:SetOrder(3)
        ag:SetScript("OnFinished", function() alertOverlay:Hide() end)
        alertOverlay._ag = ag

        alertOverlay:SetScript("OnHide", function() ag:Stop() end)
        alertOverlay:Hide()
    end

    local function ShowAlert(name, classToken)
        if not name then return end
        CreateAlertOverlay()
        ApplyOverlaySettings()

        local colored = name
        local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        if c then
            colored = "|c" .. (c.colorStr or "ffffffff") .. name .. "|r"
        end
        local skull = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t"
        alertOverlay._text:SetText(skull .. " " .. colored .. " |cffff2020DIED!|r")

        alertOverlay._ag:Stop()
        alertOverlay:SetAlpha(1)
        alertOverlay:Show()
        alertOverlay._ag:Play()
    end

    -- Configurable death alert sound (default "none"). The cog dropdown lists the
    -- bundled EllesmereUI sounds plus any SharedMedia sounds, mirroring Chat's
    -- "Whisper Sound". Played on the "Master" channel so it stays audible even
    -- when the SFX slider is low. Tables are exposed on EllesmereUI so the options
    -- file can build the same dropdown.
    local _SOUNDS_DIR = "Interface\\AddOns\\EllesmereUI\\media\\sounds\\"
    local GROUP_DEATH_SOUND_PATHS = {
        ["none"]     = nil,
        ["airhorn"]  = _SOUNDS_DIR .. "AirHorn.ogg",
        ["banana"]   = _SOUNDS_DIR .. "BananaPeelSlip.ogg",
        ["bikehorn"] = _SOUNDS_DIR .. "BikeHorn.ogg",
        ["boxing"]   = _SOUNDS_DIR .. "BoxingArenaSound.ogg",
        ["water"]    = _SOUNDS_DIR .. "WaterDrop.ogg",
    }
    local GROUP_DEATH_SOUND_NAMES = {
        ["none"]     = "None",
        ["airhorn"]  = "Air Horn",
        ["banana"]   = "Banana Peel Slip",
        ["bikehorn"] = "Bike Horn",
        ["boxing"]   = "Boxing Arena",
        ["water"]    = "Water Drop",
    }
    local GROUP_DEATH_SOUND_ORDER = {
        "none", "airhorn", "banana", "bikehorn", "boxing", "water",
    }
    -- SharedMedia sounds are appended at PLAYER_LOGIN (see the boot frame at the
    -- end of this block), NOT here: this do-block runs at addon load, before
    -- other addons have registered their LibSharedMedia sounds, so an append now
    -- would miss them. (Chat's whisper-sound append runs from its PLAYER_LOGIN
    -- init for the same reason.) The tables are exposed now by reference, so the
    -- login append fills the same tables the options dropdown reads.
    EllesmereUI._groupDeathSoundPaths = GROUP_DEATH_SOUND_PATHS
    EllesmereUI._groupDeathSoundNames = GROUP_DEATH_SOUND_NAMES
    EllesmereUI._groupDeathSoundOrder = GROUP_DEATH_SOUND_ORDER

    local function PlayDeathSound()
        local key = EllesmereUIDB and EllesmereUIDB.groupDeathSoundKey
        if not key or key == "none" then return end
        local path = GROUP_DEATH_SOUND_PATHS[key]
        if path then PlaySoundFile(path, "Master") end
    end

    local function ForEachGroupUnit(fn)
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local u = "raid" .. i
                if UnitExists(u) and not UnitIsUnit(u, "player") then fn(u) end
            end
        elseif IsInGroup() then
            for i = 1, 4 do
                local u = "party" .. i
                if UnitExists(u) then fn(u) end
            end
        end
    end

    -- Minimum gap between death sounds. On a group wipe many members die within
    -- the same poll (and across consecutive polls), which would otherwise fire
    -- the sound once per corpse and turn into a spammy overlapping mess. The
    -- cooldown collapses a burst of deaths into a single sound. It is only
    -- applied in larger groups (raids, > 5 players); in a party of 5 or fewer
    -- deaths are sparse enough that no throttling is needed.
    local SOUND_COOLDOWN = 3.0
    local COOLDOWN_MIN_GROUP = 5
    local lastSoundTime = 0

    local function TryPlayDeathSound()
        if GetNumGroupMembers() > COOLDOWN_MIN_GROUP then
            local now = GetTime()
            if now - lastSoundTime < SOUND_COOLDOWN then return end
            lastSoundTime = now
        end
        PlayDeathSound()
    end

    local function Poll()
        if not (EllesmereUIDB and EllesmereUIDB.announceGroupDeaths) then return end
        local seen = {}
        local newlyDeadName, newlyDeadClass, newlyDeadCount
        ForEachGroupUnit(function(u)
            local guid = UnitGUID(u)
            if not guid then return end
            seen[guid] = true
            if not UnitIsConnected(u) then return end
            local dead = (UnitIsDeadOrGhost(u) and not UnitIsFeignDeath(u)) and true or false
            -- prev == false means we previously saw this unit alive; a nil prev
            -- (first sighting / just (re)joined) primes the state silently so we
            -- never announce someone who was already dead when we started.
            if deadState[guid] == false and dead then
                local _, classToken = UnitClass(u)
                newlyDeadName = UnitName(u)
                newlyDeadClass = classToken
                newlyDeadCount = (newlyDeadCount or 0) + 1
            end
            deadState[guid] = dead
        end)
        for guid in pairs(deadState) do
            if not seen[guid] then deadState[guid] = nil end
        end
        -- Show a single alert per poll (the overlay is one frame, so multiple
        -- ShowAlert calls would just clobber each other anyway) and play at most
        -- one sound, throttled by the cooldown, no matter how many died.
        if newlyDeadCount then
            ShowAlert(newlyDeadName, newlyDeadClass)
            TryPlayDeathSound()
        end
    end

    local function StartTicker()
        if ticker then return end
        wipe(deadState)
        Poll()  -- prime alive/dead state without announcing
        ticker = C_Timer.NewTicker(POLL_INTERVAL, Poll)
    end

    local function StopTicker()
        if ticker then ticker:Cancel(); ticker = nil end
        wipe(deadState)
        if alertOverlay then alertOverlay:Hide() end
    end

    local function UpdateActive()
        if EllesmereUIDB and EllesmereUIDB.announceGroupDeaths and IsInGroup() then
            StartTicker()
        else
            StopTicker()
        end
    end

    local function ApplyAnnounceGroupDeaths()
        local on = EllesmereUIDB and EllesmereUIDB.announceGroupDeaths
        if on and not installed then
            watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
            watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
            installed = true
        elseif not on and installed then
            watcher:UnregisterAllEvents()
            installed = false
        end
        UpdateActive()
    end
    EllesmereUI._applyAnnounceGroupDeaths = ApplyAnnounceGroupDeaths

    -- Fires a sample alert (with sound) so the look/sound can be checked without
    -- a real death. Uses your own name/class purely as preview text.
    EllesmereUI._announceGroupDeathsPreview = function()
        local _, classToken = UnitClass("player")
        ShowAlert(UnitName("player"), classToken)
        PlayDeathSound()
    end

    -- Visual-only preview (used by the Text Size slider so dragging it doesn't
    -- repeatedly fire the sound).
    EllesmereUI._groupDeathShowVisual = function()
        local _, classToken = UnitClass("player")
        ShowAlert(UnitName("player"), classToken)
    end

    EllesmereUI._groupDeathPlaySound = PlayDeathSound

    -- Re-apply font size / position (called from the Text Size slider and from
    -- unlock mode when the saved position changes).
    EllesmereUI._applyGroupDeathAlert = function()
        CreateAlertOverlay()
        ApplyOverlaySettings()
    end

    -- Register the alert with Unlock Mode so its position can be dragged.
    C_Timer.After(2, function()
        if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
        local MK = EllesmereUI.MakeUnlockElement
        if not MK then return end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key      = "EUI_GroupDeathAlert",
                label    = "Group Death Alert",
                group    = "Quality of Life",
                order    = 720,
                noResize = true,
                isHidden = function()
                    return not (EllesmereUIDB and EllesmereUIDB.announceGroupDeaths)
                end,
                getFrame = function()
                    CreateAlertOverlay()
                    return alertOverlay
                end,
                getSize = function()
                    local size = (EllesmereUIDB and EllesmereUIDB.groupDeathTextSize) or DEFAULT_TEXT_SIZE
                    return size * 7, size + 14
                end,
                savePos = function(_, point, relPoint, x, y)
                    if not point then return end
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.groupDeathAlertPos = { point = point, relPoint = relPoint, x = x, y = y }
                    if alertOverlay and not EllesmereUI._unlockActive then
                        ApplyOverlaySettings()
                    end
                end,
                loadPos = function()
                    local pos = EllesmereUIDB and EllesmereUIDB.groupDeathAlertPos
                    if pos and pos.point then return pos end
                    return { point = "CENTER", relPoint = "CENTER", x = 0, y = 180 }
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.groupDeathAlertPos = nil end
                    if alertOverlay then ApplyOverlaySettings() end
                end,
                applyPos = function()
                    CreateAlertOverlay()
                    ApplyOverlaySettings()
                end,
            }),
        })
    end)

    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function() UpdateActive() end)

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        -- Append SharedMedia sounds now, at login, once other addons have
        -- registered theirs -- this is the same timing Chat's whisper-sound
        -- dropdown uses. Idempotent: AppendSharedMediaSounds skips keys that
        -- are already present, and the tables are the very ones the options
        -- dropdown (and PlayDeathSound) read, so both pick up the SM sounds.
        if EllesmereUI.AppendSharedMediaSounds then
            EllesmereUI.AppendSharedMediaSounds(
                GROUP_DEATH_SOUND_PATHS, GROUP_DEATH_SOUND_NAMES, GROUP_DEATH_SOUND_ORDER)
        end
        if EllesmereUIDB and EllesmereUIDB.announceGroupDeaths then
            ApplyAnnounceGroupDeaths()
        end
    end)
end

