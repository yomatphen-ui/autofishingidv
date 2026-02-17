-- AUTO FISHING FISCH v8.2 ULTIMATE (Rayfield Edition)
-- Multi-Platform Spot Rotation + Safe Mode
-- Anti Luck Decay: Rotasi 3 spot otomatis
-- Mobile Compatible UI via Rayfield
-- v8.1: Optimized cast-after-catch delay
-- v8.2: Direct re-equip in handler + faster main loop

-- Load Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

print("=== AUTO FISHING v8.2 ULTIMATE (Rayfield) ===")
print("=== Direct Re-equip + Fast Loop ===")

-- Settings (defaults from screenshot)
getgenv().AutoFishSettings = {
    Enabled = false,
    Debug = false,

    -- Safe Mode
    SafeMode = true,
    StuckTimeout = 30,
    MaxConsecutiveFails = 5,
    AutoRestart = true,

    -- Cast
    CastPowerMin = 0.50,
    CastPowerMax = 0.50,
    CastDelayMin = 0.1,
    CastDelayMax = 0.1,
    HoldTimeMin = 0.20,
    HoldTimeMax = 0.25,

    -- Minigame
    AutoComplete = true,
    MinigameDelayMin = 2.1,
    MinigameDelayMax = 2.3,

    -- Rod
    AutoDetectRod = true,
    UseAnyRod = true,
    SpecificRodName = "",
    UnequipAfterCatch = true,
    UnequipDelay = 0.1,
    ReequipDelay = 0.1,

    -- Sell
    AutoSell = false,
    SellInterval = 60,

    -- Teleport & Platform + SPOT ROTATION
    SafeSpotEnabled = false,
    SafeSpotPosition = Vector3.new(-48.78, 0.62, -1285.83),
    CreatePlatform = true,
    PlatformSize = Vector3.new(20, 1, 20),
    LockCharacter = true,

    -- Spot Rotation (v8.0)
    SpotRotationEnabled = true,
    SpotRotationInterval = 5,
    SpotOffset = 40,

    -- Anti-Pattern
    RandomPause = true,
    PauseChance = 7,
    PauseDelayMin = 3,
    PauseDelayMax = 7,
}

-- Stats
local Stats = {
    startTime = tick(),
    casts = 0,
    fish = 0,
    failed = 0,
    pauses = 0,
    sells = 0,
    lastSellTime = 0,
    consecutiveFails = 0,
    stuckResets = 0,
    lastStateChange = tick(),
    spotCastsAtCurrentSpot = 0,
    spotRotations = 0,
}

-- State
local State = {
    isCasting = false,
    inMinigame = false,
    isEquipping = false,
    isPaused = false,
    currentState = "Idle",
    lastCastTime = 0,
    rodEquipped = false,
    currentRodName = "None"
}

local function debug(...)
    if getgenv().AutoFishSettings.Debug then
        print("[DEBUG]", ...)
    end
end

local function randomDelay(min, max)
    return math.random(min * 100, max * 100) / 100
end

local function setState(newState)
    State.currentState = newState
    Stats.lastStateChange = tick()
    debug("State:", newState)
end

-- Random pause
local function randomPause()
    if not getgenv().AutoFishSettings.RandomPause then return end

    if math.random(1, 100) <= getgenv().AutoFishSettings.PauseChance then
        State.isPaused = true
        Stats.pauses = Stats.pauses + 1

        local pauseTime = randomDelay(
            getgenv().AutoFishSettings.PauseDelayMin,
            getgenv().AutoFishSettings.PauseDelayMax
        )

        setState("Paused (" .. string.format("%.1f", pauseTime) .. "s)")
        task.wait(pauseTime)
        State.isPaused = false
        setState("Ready")
    end
end

-- ==================== SELL ====================

local function sellAllFish()
    debug("=== SELLING ALL FISH ===")
    setState("Selling...")

    local success, result = pcall(function()
        local remoteFunctions = ReplicatedStorage:FindFirstChild("GameRemoteFunctions")
        if not remoteFunctions then
            warn("GameRemoteFunctions not found!")
            return false
        end

        local sellRemote = remoteFunctions:FindFirstChild("SellAllFishFunction")
        if not sellRemote then
            warn("SellAllFishFunction not found!")
            warn("Available remotes:")
            for _, remote in pairs(remoteFunctions:GetChildren()) do
                warn("  -", remote.Name, "(" .. remote.ClassName .. ")")
            end
            return false
        end

        local sellResult = sellRemote:InvokeServer()
        debug("Sell result:", sellResult)

        Stats.sells = Stats.sells + 1
        Stats.lastSellTime = tick()

        debug("Sold! Total:", Stats.sells)
        setState("Sold (#" .. Stats.sells .. ")")

        Rayfield:Notify({Title = "Auto Sell", Content = "Sold all fish!", Duration = 2})
        return true
    end)

    if not success then
        warn("Sell error:", result)
        setState("Sell failed")
        Rayfield:Notify({Title = "Error", Content = "Sell failed! Check F9", Duration = 3})
    end

    task.wait(1)
    setState("Ready")

    return success
end

local function startAutoSell()
    task.spawn(function()
        while true do
            task.wait(5)

            if not getgenv().AutoFishSettings.AutoSell then
                continue
            end

            local timeSinceLastSell = tick() - Stats.lastSellTime

            if timeSinceLastSell >= getgenv().AutoFishSettings.SellInterval then
                debug("Auto-sell triggered (interval reached)")
                sellAllFish()
            end
        end
    end)
end

-- ==================== ROD FUNCTIONS ====================

local function findAnyRod()
    local char = LocalPlayer.Character
    if char then
        for _, tool in pairs(char:GetChildren()) do
            if tool:IsA("Tool") and tool:FindFirstChild("Cast") then
                return tool
            end
        end
    end

    for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Cast") then
            return tool
        end
    end

    return nil
end

local function findRodByName(name)
    local char = LocalPlayer.Character
    if char then
        local tool = char:FindFirstChild(name)
        if tool and tool:IsA("Tool") and tool:FindFirstChild("Cast") then
            return tool
        end
    end

    local tool = LocalPlayer.Backpack:FindFirstChild(name)
    if tool and tool:IsA("Tool") and tool:FindFirstChild("Cast") then
        return tool
    end

    return nil
end

local function getRod()
    if getgenv().AutoFishSettings.UseAnyRod then
        return findAnyRod()
    else
        if getgenv().AutoFishSettings.SpecificRodName ~= "" then
            return findRodByName(getgenv().AutoFishSettings.SpecificRodName)
        else
            return findAnyRod()
        end
    end
end

local function isRodEquipped()
    local char = LocalPlayer.Character
    if not char then return false end

    for _, tool in pairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Cast") then
            State.currentRodName = tool.Name
            return true
        end
    end

    State.currentRodName = "None"
    return false
end

local function unequipRod()
    if State.isEquipping then return false end

    setState("Unequipping rod")

    local char = LocalPlayer.Character
    if not char then return false end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    pcall(function()
        humanoid:UnequipTools()
    end)

    task.wait(0.05) -- v8.1: 0.15 -> 0.05
    State.rodEquipped = false
    State.currentRodName = "None"
    setState("Unequipped")
    return true
end

local function equipRod()
    if State.isEquipping then
        debug("Already equipping")
        return false
    end

    State.isEquipping = true
    setState("Equipping rod")

    local char = LocalPlayer.Character
    if not char then
        State.isEquipping = false
        return false
    end

    if isRodEquipped() then
        State.rodEquipped = true
        State.isEquipping = false

        local rod = getRod()
        if rod then
            local toolReady = rod:FindFirstChild("ToolReady")
            if toolReady then
                pcall(function()
                    toolReady:FireServer(tick())
                end)
            end
        end

        setState("Rod ready")
        return true
    end

    local rodTool = getRod()

    if not rodTool then
        warn("No fishing rod found!")
        State.isEquipping = false
        setState("No rod found")
        return false
    end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        State.isEquipping = false
        return false
    end

    humanoid:EquipTool(rodTool)
    task.wait(0.2) -- v8.2: 0.3 -> 0.2 equip confirm

    if not isRodEquipped() then
        warn("Equip failed")
        State.isEquipping = false
        setState("Equip failed")
        return false
    end

    State.rodEquipped = true

    local equippedRod = getRod()
    if equippedRod then
        local toolReady = equippedRod:FindFirstChild("ToolReady")
        if toolReady then
            pcall(function()
                toolReady:FireServer(tick())
            end)
            task.wait(0.05) -- v8.2: 0.1 -> 0.05
        end
    end

    State.isEquipping = false
    setState("Equipped: " .. State.currentRodName)
    return true
end

-- ==================== MULTI-PLATFORM SPOT ROTATION (v8.0) ====================

local FishingPlatforms = {}
local CurrentSpotIndex = 1
local CharacterLocked = false
local LockedPosition = nil

local function getSpotPositions()
    local basePos = getgenv().AutoFishSettings.SafeSpotPosition
    local offset = getgenv().AutoFishSettings.SpotOffset

    return {
        [1] = basePos,
        [2] = basePos + Vector3.new(offset, 0, 0),
        [3] = basePos + Vector3.new(offset * 2, 0, 0),
    }
end

local function lockCharacter()
    if CharacterLocked then return end

    local char = LocalPlayer.Character
    if not char then return end

    local humanoidRootPart = char:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    CharacterLocked = true
    LockedPosition = humanoidRootPart.CFrame

    debug("Character locked!")
    Rayfield:Notify({Title = "Lock", Content = "Character locked in place", Duration = 2})

    task.spawn(function()
        while CharacterLocked and getgenv().AutoFishSettings.LockCharacter do
            task.wait(0.1)

            local currentChar = LocalPlayer.Character
            if currentChar then
                local hrp = currentChar:FindFirstChild("HumanoidRootPart")
                if hrp and LockedPosition then
                    hrp.CFrame = LockedPosition
                    hrp.Velocity = Vector3.new(0, 0, 0)
                    hrp.RotVelocity = Vector3.new(0, 0, 0)

                    local humanoid = currentChar:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        humanoid.WalkSpeed = 0
                        humanoid.JumpPower = 0
                    end
                end
            end
        end
    end)
end

local function unlockCharacter()
    if not CharacterLocked then return end

    CharacterLocked = false
    LockedPosition = nil

    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end

    debug("Character unlocked!")
    Rayfield:Notify({Title = "Unlock", Content = "Character unlocked", Duration = 2})
end

local function createAllPlatforms()
    for i, plat in pairs(FishingPlatforms) do
        if plat and plat.Parent then
            plat:Destroy()
        end
    end
    FishingPlatforms = {}

    local spots = getSpotPositions()
    local colors = {
        [1] = Color3.fromRGB(0, 170, 255),
        [2] = Color3.fromRGB(0, 255, 127),
        [3] = Color3.fromRGB(255, 170, 0),
    }

    for i = 1, 3 do
        local platform = Instance.new("Part")
        platform.Name = "FishingPlatform_" .. LocalPlayer.Name .. "_Spot" .. i
        platform.Size = getgenv().AutoFishSettings.PlatformSize
        platform.Position = spots[i]
        platform.Anchored = true
        platform.CanCollide = true
        platform.Transparency = 0.8
        platform.Material = Enum.Material.ForceField
        platform.Color = colors[i]
        platform.TopSurface = Enum.SurfaceType.Smooth
        platform.BottomSurface = Enum.SurfaceType.Smooth
        platform.Parent = workspace

        FishingPlatforms[i] = platform
        debug("Platform " .. i .. " created at:", tostring(spots[i]))
    end

    debug("All 3 platforms created!")
    Rayfield:Notify({Title = "Platforms", Content = "3 Platforms created!", Duration = 2})
end

local function removeAllPlatforms()
    for i, plat in pairs(FishingPlatforms) do
        if plat and plat.Parent then
            plat:Destroy()
            debug("Platform " .. i .. " removed")
        end
    end
    FishingPlatforms = {}
    debug("All platforms removed")
end

local function teleportToSpot(spotIndex)
    debug("=== TELEPORTING TO SPOT " .. spotIndex .. " ===")
    setState("Moving to Spot " .. spotIndex)

    local char = LocalPlayer.Character
    if not char then
        warn("Character not found!")
        return false
    end

    local humanoidRootPart = char:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then
        warn("HumanoidRootPart not found!")
        return false
    end

    if CharacterLocked then
        CharacterLocked = false
        LockedPosition = nil

        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end

        task.wait(0.2)
    end

    if getgenv().AutoFishSettings.CreatePlatform then
        if #FishingPlatforms == 0 or not FishingPlatforms[1] or not FishingPlatforms[1].Parent then
            createAllPlatforms()
            task.wait(0.5)
        end
    end

    local spots = getSpotPositions()
    local targetPos = spots[spotIndex]
    humanoidRootPart.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))

    CurrentSpotIndex = spotIndex
    debug("Teleported to Spot " .. spotIndex .. ":", tostring(targetPos))

    if getgenv().AutoFishSettings.LockCharacter then
        task.wait(0.5)
        lockCharacter()
    end

    setState("At Spot " .. spotIndex)
    Rayfield:Notify({Title = "Teleport", Content = "Spot " .. spotIndex .. "/3 | Rotation active", Duration = 2})

    task.wait(1)
    setState("Ready")

    return true
end

local function teleportToSafeSpot()
    return teleportToSpot(CurrentSpotIndex)
end

local function checkSpotRotation()
    if not getgenv().AutoFishSettings.SpotRotationEnabled then return end
    if not getgenv().AutoFishSettings.SafeSpotEnabled then return end

    Stats.spotCastsAtCurrentSpot = Stats.spotCastsAtCurrentSpot + 1

    debug("Spot " .. CurrentSpotIndex .. " catches: " .. Stats.spotCastsAtCurrentSpot .. "/" .. getgenv().AutoFishSettings.SpotRotationInterval)

    if Stats.spotCastsAtCurrentSpot >= getgenv().AutoFishSettings.SpotRotationInterval then
        Stats.spotCastsAtCurrentSpot = 0
        Stats.spotRotations = Stats.spotRotations + 1

        local nextSpot = (CurrentSpotIndex % 3) + 1

        debug("ROTATING: Spot " .. CurrentSpotIndex .. " -> Spot " .. nextSpot)
        Rayfield:Notify({Title = "Rotation", Content = "Rotating to Spot " .. nextSpot .. "...", Duration = 2})

        State.isPaused = true

        unequipRod()
        task.wait(0.3)

        teleportToSpot(nextSpot)
        task.wait(1)

        equipRod()
        task.wait(0.5)
        setupMinigame()
        task.wait(0.5)

        State.isPaused = false
        State.isCasting = false
        State.inMinigame = false
        State.isEquipping = false
        setState("Ready")

        debug("Rotation complete! Now at Spot " .. nextSpot)
    end
end

-- ==================== SAFE MODE ====================

local function emergencyReset()
    debug("EMERGENCY RESET")
    Rayfield:Notify({Title = "Warning", Content = "Stuck detected! Resetting...", Duration = 3})

    State.isCasting = false
    State.inMinigame = false
    State.isEquipping = false
    State.isPaused = false

    pcall(function()
        local char = LocalPlayer.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:UnequipTools()
            end
        end
    end)

    task.wait(1)

    State.rodEquipped = false
    equipRod()

    Stats.stuckResets = Stats.stuckResets + 1
    Stats.consecutiveFails = 0

    setState("Reset complete")
    debug("Reset complete!")
end

local function startSafeMode()
    task.spawn(function()
        while true do
            task.wait(5)

            if not getgenv().AutoFishSettings.SafeMode then
                continue
            end

            if not getgenv().AutoFishSettings.Enabled then
                continue
            end

            local timeSinceStateChange = tick() - Stats.lastStateChange
            if timeSinceStateChange > getgenv().AutoFishSettings.StuckTimeout then
                warn("STUCK DETECTED: No state change for " .. math.floor(timeSinceStateChange) .. "s")

                if getgenv().AutoFishSettings.AutoRestart then
                    emergencyReset()
                else
                    Rayfield:Notify({Title = "Warning", Content = "Stuck detected! Enable Auto Restart", Duration = 5})
                end
            end

            if Stats.consecutiveFails >= getgenv().AutoFishSettings.MaxConsecutiveFails then
                warn("TOO MANY FAILS: " .. Stats.consecutiveFails .. " consecutive")

                if getgenv().AutoFishSettings.AutoRestart then
                    emergencyReset()
                else
                    Rayfield:Notify({Title = "Warning", Content = "Too many fails! Enable Auto Restart", Duration = 5})
                end
            end

            if getgenv().AutoFishSettings.Enabled then
                if not State.inMinigame and not State.isEquipping then
                    if not isRodEquipped() then
                        warn("ROD MISSING!")
                        State.rodEquipped = false
                        equipRod()
                    end
                end
            end
        end
    end)
end

-- ==================== CASTING ====================

local function canCast()
    if State.isPaused then return false end
    if State.isCasting then return false end
    if State.inMinigame then return false end
    if State.isEquipping then return false end

    -- v8.1: 1.5s -> 0.4s anti-spam cooldown
    local timeSinceCast = tick() - State.lastCastTime
    if timeSinceCast < 0.4 then return false end

    local char = LocalPlayer.Character
    if not char then return false end

    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return false end

    if humanoid.Health <= 0 then return false end
    if humanoid.MoveDirection.Magnitude > 0.01 then return false end
    if humanoid:GetState() == Enum.HumanoidStateType.Swimming then return false end

    return true
end

local function castRod()
    debug("=== CAST ATTEMPT ===")
    debug("States: casting=" .. tostring(State.isCasting) .. " minigame=" .. tostring(State.inMinigame) .. " equipping=" .. tostring(State.isEquipping))

    setState("Preparing cast")

    if not canCast() then
        debug("Can't cast")
        return false
    end

    if not State.rodEquipped or not isRodEquipped() then
        debug("Rod not equipped")
        setState("Rod not equipped")
        return false
    end

    local rod = getRod()
    if not rod then
        State.rodEquipped = false
        debug("No rod")
        setState("Rod missing")
        return false
    end

    debug("Using rod:", rod.Name)

    local castRemote = rod:FindFirstChild("Cast")
    local toolReady = rod:FindFirstChild("ToolReady")

    if not castRemote then
        debug("No Cast remote")
        return false
    end

    State.isCasting = true
    State.lastCastTime = tick()
    setState("Casting")
    debug("Casting...")

    if toolReady then
        pcall(function()
            toolReady:FireServer(tick())
        end)
        task.wait(0.1) -- v8.1: 0.25 -> 0.1
    end

    local VirtualInputManager = game:GetService("VirtualInputManager")
    local UserInputService = game:GetService("UserInputService")
    local mousePos = UserInputService:GetMouseLocation()

    local success = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 0)

        local holdTime = randomDelay(
            getgenv().AutoFishSettings.HoldTimeMin,
            getgenv().AutoFishSettings.HoldTimeMax
        )
        task.wait(holdTime)

        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 0)
    end)

    if not success then
        State.isCasting = false
        debug("Hold failed")
        setState("Cast failed")
        return false
    end

    task.wait(0.5)

    debug("Checking for bait...")
    local baitExists = false
    pcall(function()
        baitExists = workspace.Temp:FindFirstChild("FishingBait") ~= nil
    end)

    if baitExists then
        Stats.casts = Stats.casts + 1
        debug("Bait found! Cast #" .. Stats.casts)
        setState("Casted (#" .. Stats.casts .. ")")
        return true
    else
        State.isCasting = false
        debug("No bait")
        setState("No bait detected")
        return false
    end
end

-- ==================== MINIGAME ====================

local function waitForFishingUI()
    local timeout = 0
    while timeout < 50 do
        local fishingUI = LocalPlayer.PlayerGui:FindFirstChild("FishingUI")
        if fishingUI and fishingUI.Enabled then
            return fishingUI
        end
        task.wait(0.1)
        timeout = timeout + 1
    end
    return nil
end

local function simulateMinigameInteraction(fishingUI)
    pcall(function()
        local frame = fishingUI:FindFirstChild("FishingFrame")
        if not frame then
            frame = fishingUI:FindFirstChildWhichIsA("Frame", true)
        end

        if frame then
            local clicks = math.random(3, 5)

            for i = 1, clicks do
                task.wait(randomDelay(0.2, 0.5))

                for _, button in pairs(frame:GetDescendants()) do
                    if button:IsA("TextButton") or button:IsA("ImageButton") then
                        pcall(function()
                            for _, conn in pairs(getconnections(button.MouseButton1Click)) do
                                conn:Fire()
                            end
                            for _, conn in pairs(getconnections(button.Activated)) do
                                conn:Fire()
                            end
                        end)
                    end
                end
            end
        end
    end)
end

local MinigameConnection = nil

function setupMinigame()
    setState("Setting up minigame")

    if MinigameConnection then
        MinigameConnection:Disconnect()
        MinigameConnection = nil
        debug("Disconnected old minigame listener")
    end

    local attempts = 0
    while attempts < 10 do
        local rod = getRod()
        if rod then
            local startMinigame = rod:FindFirstChild("StartMinigame")
            if startMinigame then

                MinigameConnection = startMinigame.OnClientEvent:Connect(function(baitInstance, fishData, spotLuck)
                    State.inMinigame = true
                    State.isCasting = false
                    setState("Minigame: " .. fishData.FishName)

                    debug("Fish hooked:", fishData.FishName, fishData.Weight .. "kg")

                    if not getgenv().AutoFishSettings.Enabled then
                        debug("Auto-fish disabled")
                        return
                    end

                    if not getgenv().AutoFishSettings.AutoComplete then
                        debug("Auto-complete disabled")
                        return
                    end

                    task.spawn(function()
                        local mainDelay = randomDelay(
                            getgenv().AutoFishSettings.MinigameDelayMin,
                            getgenv().AutoFishSettings.MinigameDelayMax
                        )

                        if mainDelay > 2 then
                            setState("Waiting for UI...")
                            local fishingUI = waitForFishingUI()

                            if fishingUI then
                                debug("UI detected")
                                local uiWait = randomDelay(0.3, 0.6)
                                task.wait(uiWait)

                                setState("Clicking UI")
                                simulateMinigameInteraction(fishingUI)
                                task.wait(randomDelay(0.2, 0.4))
                            end
                        else
                            debug("Instant mode - skipping UI interaction")
                        end

                        if mainDelay > 0.5 then
                            setState("Waiting " .. string.format("%.1f", mainDelay) .. "s")
                            debug("Main delay:", mainDelay .. "s")
                            task.wait(mainDelay)
                        else
                            debug("Ultra instant mode - minimal delay")
                            task.wait(0.1)
                        end

                        setState("Claiming")
                        debug("Claiming now")

                        local claimSuccess = false

                        pcall(function()
                            local gameEvents = ReplicatedStorage:FindFirstChild("GameRemoteEvents")
                            if gameEvents then
                                local rewardEvent = gameEvents:FindFirstChild("CreateFishRewardInfoEvent")
                                if rewardEvent then
                                    debug("CreateFishRewardInfoEvent")
                                    rewardEvent:FireServer(fishData)
                                    task.wait(0.1)
                                end
                            end
                        end)

                        pcall(function()
                            local currentRod = getRod()
                            if currentRod then
                                local catchRemote = currentRod:FindFirstChild("Catch")
                                if catchRemote then
                                    debug("Catch")
                                    catchRemote:FireServer(true)

                                    Stats.fish = Stats.fish + 1
                                    claimSuccess = true
                                    setState("Caught #" .. Stats.fish)
                                    debug("Success!")

                                    -- v8.2: Direct unequip + re-equip in handler
                                    if getgenv().AutoFishSettings.UnequipAfterCatch then
                                        task.wait(getgenv().AutoFishSettings.UnequipDelay)
                                        unequipRod()
                                        task.wait(getgenv().AutoFishSettings.ReequipDelay)
                                        equipRod() -- v8.2: LANGSUNG equip di sini!
                                    end
                                else
                                    debug("ERROR: Catch remote not found!")
                                end
                            else
                                debug("ERROR: Rod not found!")
                            end
                        end)

                        if not claimSuccess then
                            debug("Claim failed!")
                            Stats.failed = Stats.failed + 1
                            Stats.consecutiveFails = Stats.consecutiveFails + 1
                        else
                            Stats.consecutiveFails = 0
                            checkSpotRotation()
                        end

                        task.wait(0.05) -- v8.2: 0.15 -> 0.05 post-claim

                        State.inMinigame = false
                        State.isCasting = false
                        State.isEquipping = false
                        State.isPaused = false

                        setState("Ready")
                        debug("All states reset, ready for next cast")

                        randomPause()
                    end)
                end)

                setState("Minigame ready")
                return true
            end
        end

        task.wait(1)
        attempts = attempts + 1
    end

    return false
end

-- ==================== MAIN LOOP ====================

local function startAutoFish()
    task.spawn(function()
        while true do
            task.wait(0.1) -- v8.2: 0.2 -> 0.1 faster loop pickup

            if not getgenv().AutoFishSettings.Enabled then
                continue
            end

            -- v8.2: Rod missing fallback (bukan primary, handler udah handle)
            if not State.rodEquipped or not isRodEquipped() then
                if not State.isEquipping and not State.inMinigame then
                    setState("Need rod")
                    equipRod()
                end
                task.wait(0.3) -- v8.2: 1.0 -> 0.3 fallback wait
                continue
            end

            if State.isCasting or State.inMinigame or State.isPaused or State.isEquipping then
                continue
            end

            local success = castRod()

            if success then
                local cooldown = randomDelay(
                    getgenv().AutoFishSettings.CastDelayMin,
                    getgenv().AutoFishSettings.CastDelayMax
                )
                task.wait(cooldown)
            else
                task.wait(0.5) -- v8.2: 1.0 -> 0.5 failed cast retry
            end
        end
    end)
end

-- Monitor rod changes
local LastRodName = nil

local function monitorRodChanges()
    task.spawn(function()
        while true do
            task.wait(2)

            if not getgenv().AutoFishSettings.Enabled then
                continue
            end

            local rod = getRod()
            if rod then
                local currentRodName = rod.Name

                if LastRodName and LastRodName ~= currentRodName then
                    warn("ROD CHANGED: " .. LastRodName .. " -> " .. currentRodName)
                    Rayfield:Notify({Title = "Rod Change", Content = "Rod changed! Re-setting up...", Duration = 3})

                    task.wait(0.5)
                    setupMinigame()

                    debug("New rod ready: " .. currentRodName)
                    Rayfield:Notify({Title = "Rod Ready", Content = currentRodName .. " ready!", Duration = 2})
                end

                LastRodName = currentRodName
            end
        end
    end)
end

-- ==================== PRESETS ====================

local Presets = {
    Legit = {
        name = "LEGIT (Safest)",
        CastPowerMin = 0.80,
        CastPowerMax = 0.95,
        CastDelayMin = 3,
        CastDelayMax = 5,
        HoldTimeMin = 0.85,
        HoldTimeMax = 1.15,
        MinigameDelayMin = 5,
        MinigameDelayMax = 8,
        UnequipAfterCatch = true,
        UnequipDelay = 0.3,
        ReequipDelay = 0.6,
        RandomPause = true,
        PauseChance = 10,
        PauseDelayMin = 4,
        PauseDelayMax = 9,
    },
    SemiLegit = {
        name = "SEMI-LEGIT (Balanced)",
        CastPowerMin = 0.88,
        CastPowerMax = 0.98,
        CastDelayMin = 0.1,
        CastDelayMax = 2,
        HoldTimeMin = 0.10,
        HoldTimeMax = 1.10,
        MinigameDelayMin = 1,
        MinigameDelayMax = 3,
        UnequipAfterCatch = true,
        UnequipDelay = 0.2,
        ReequipDelay = 0.4,
        RandomPause = true,
        PauseChance = 7,
        PauseDelayMin = 3,
        PauseDelayMax = 7,
    },
    Blatant = {
        name = "BLATANT (Fastest)",
        CastPowerMin = 0.95,
        CastPowerMax = 0.99,
        CastDelayMin = 0.1,
        CastDelayMax = 0.5,
        HoldTimeMin = 0.1,
        HoldTimeMax = 0.2,
        MinigameDelayMin = 0.1,
        MinigameDelayMax = 0.5,
        UnequipAfterCatch = true,
        UnequipDelay = 0.1,
        ReequipDelay = 0.2,
        RandomPause = false,
        PauseChance = 0,
        PauseDelayMin = 0,
        PauseDelayMax = 0,
    }
}

-- UI Element References (for presets to update)
local UIElements = {}

local function applyPreset(presetData)
    for key, value in pairs(presetData) do
        if key ~= "name" then
            getgenv().AutoFishSettings[key] = value
        end
    end

    for key, value in pairs(presetData) do
        if key ~= "name" and UIElements[key] then
            pcall(function()
                UIElements[key]:Set(value)
            end)
        end
    end

    Rayfield:Notify({Title = "Preset", Content = "Applied: " .. presetData.name, Duration = 3})
end

-- ==================== RAYFIELD UI ====================

local Window = Rayfield:CreateWindow({
    Name = "Auto Fishing v8.2 | Fast Loop",
    LoadingTitle = "Auto Fishing v8.2",
    LoadingSubtitle = "Direct Re-equip + Fast Loop",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "AutoFishv8",
        FileName = "config"
    },
    KeySystem = false,
})

-- ========== TAB: Main ==========
local MainTab = Window:CreateTab("Main", 4483362458)
local StatsTab = Window:CreateTab("Statistics", 4483362458)
local SettingsTab = Window:CreateTab("Settings", 4483362458)

-- ========== SECTION: Controls ==========
local ControlSection = MainTab:CreateSection("Controls")

UIElements.AutoFish = MainTab:CreateToggle({
    Name = "Enable Auto Fishing",
    CurrentValue = false,
    Flag = "AutoFish",
    Callback = function(Value)
        getgenv().AutoFishSettings.Enabled = Value

        if Value then
            Rayfield:Notify({Title = "Auto Fish", Content = "Starting...", Duration = 2})

            task.spawn(function()
                task.wait(0.5)

                if getgenv().AutoFishSettings.SafeSpotEnabled then
                    debug("TP to safe spot...")
                    teleportToSpot(CurrentSpotIndex)
                    task.wait(1.5)
                end

                debug("Checking rod...")
                if not isRodEquipped() then
                    debug("Equipping rod...")
                    local equipSuccess = equipRod()
                    if equipSuccess then
                        Rayfield:Notify({Title = "Rod", Content = "Rod equipped!", Duration = 2})
                        task.wait(1)

                        debug("Re-setting up minigame...")
                        setupMinigame()
                        task.wait(0.5)

                        Rayfield:Notify({Title = "Ready", Content = "Ready to fish!", Duration = 2})
                    else
                        Rayfield:Notify({Title = "Error", Content = "Failed to equip rod!", Duration = 3})
                        warn("Failed to equip rod on start")
                    end
                else
                    Rayfield:Notify({Title = "Rod", Content = "Rod already equipped", Duration = 2})
                    setupMinigame()
                    task.wait(0.5)
                end

                State.isCasting = false
                State.inMinigame = false
                State.isEquipping = false
                State.isPaused = false
                Stats.spotCastsAtCurrentSpot = 0
                setState("Ready to cast")

                debug("All setup complete, starting fishing...")
            end)
        else
            Rayfield:Notify({Title = "Auto Fish", Content = "Stopped", Duration = 2})

            if CharacterLocked then
                unlockCharacter()
            end
        end
    end,
})

UIElements.UseAnyRod = MainTab:CreateToggle({
    Name = "Auto-Detect Any Rod",
    CurrentValue = true,
    Flag = "UseAnyRod",
    Callback = function(Value)
        getgenv().AutoFishSettings.UseAnyRod = Value
    end,
})

UIElements.SpecificRodName = MainTab:CreateInput({
    Name = "Specific Rod Name (Optional)",
    PlaceholderText = "e.g. Mythical Rod",
    RemoveTextAfterFocusLost = false,
    Callback = function(Value)
        getgenv().AutoFishSettings.SpecificRodName = Value
        if Value ~= "" then
            getgenv().AutoFishSettings.UseAnyRod = false
            UIElements.UseAnyRod:Set(false)
        end
    end,
})

MainTab:CreateButton({
    Name = "Equip Rod Now",
    Callback = function()
        equipRod()
    end,
})

MainTab:CreateButton({
    Name = "Re-Setup Rod",
    Callback = function()
        setupMinigame()
        Rayfield:Notify({Title = "Rod", Content = "Rod re-setup complete!", Duration = 2})
    end,
})

MainTab:CreateButton({
    Name = "Force Cast Now",
    Callback = function()
        State.isCasting = false
        State.inMinigame = false
        State.isEquipping = false
        State.isPaused = false

        castRod()
        Rayfield:Notify({Title = "Cast", Content = "Forced cast attempt", Duration = 2})
    end,
})

-- ========== SECTION: Auto Sell ==========
local SellSection = MainTab:CreateSection("Auto Sell")

UIElements.AutoSell = MainTab:CreateToggle({
    Name = "Auto Sell Fish",
    CurrentValue = false,
    Flag = "AutoSell",
    Callback = function(Value)
        getgenv().AutoFishSettings.AutoSell = Value
        if Value then
            Rayfield:Notify({Title = "Sell", Content = "Auto Sell Enabled!", Duration = 2})
        end
    end,
})

UIElements.SellInterval = MainTab:CreateSlider({
    Name = "Sell Every (seconds)",
    Range = {10, 300},
    Increment = 1,
    Suffix = "s",
    CurrentValue = 60,
    Flag = "SellInterval",
    Callback = function(Value)
        getgenv().AutoFishSettings.SellInterval = Value
    end,
})

MainTab:CreateButton({
    Name = "Sell All Now",
    Callback = function()
        sellAllFish()
    end,
})

-- ========== SECTION: Presets ==========
local PresetSection = MainTab:CreateSection("Presets")

MainTab:CreateButton({
    Name = "LEGIT (Safest)",
    Callback = function()
        applyPreset(Presets.Legit)
    end,
})

MainTab:CreateButton({
    Name = "SEMI-LEGIT (Balanced)",
    Callback = function()
        applyPreset(Presets.SemiLegit)
    end,
})

MainTab:CreateButton({
    Name = "BLATANT (Fastest)",
    Callback = function()
        applyPreset(Presets.Blatant)
    end,
})

-- ========== SECTION: Cast Settings ==========
local CastSection = MainTab:CreateSection("Cast")

UIElements.CastPowerMin = MainTab:CreateSlider({
    Name = "Min Power",
    Range = {0, 1},
    Increment = 0.01,
    Suffix = "",
    CurrentValue = 0.50,
    Flag = "CastPowerMin",
    Callback = function(Value)
        getgenv().AutoFishSettings.CastPowerMin = Value
    end,
})

UIElements.CastPowerMax = MainTab:CreateSlider({
    Name = "Max Power",
    Range = {0, 1},
    Increment = 0.01,
    Suffix = "",
    CurrentValue = 0.50,
    Flag = "CastPowerMax",
    Callback = function(Value)
        getgenv().AutoFishSettings.CastPowerMax = Value
    end,
})

UIElements.CastDelayMin = MainTab:CreateSlider({
    Name = "Min Delay",
    Range = {0, 10},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 0.1,
    Flag = "CastDelayMin",
    Callback = function(Value)
        getgenv().AutoFishSettings.CastDelayMin = Value
    end,
})

UIElements.CastDelayMax = MainTab:CreateSlider({
    Name = "Max Delay",
    Range = {0, 10},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 0.1,
    Flag = "CastDelayMax",
    Callback = function(Value)
        getgenv().AutoFishSettings.CastDelayMax = Value
    end,
})

UIElements.HoldTimeMin = MainTab:CreateSlider({
    Name = "Min Hold",
    Range = {0, 3},
    Increment = 0.01,
    Suffix = "s",
    CurrentValue = 0.20,
    Flag = "HoldTimeMin",
    Callback = function(Value)
        getgenv().AutoFishSettings.HoldTimeMin = Value
    end,
})

UIElements.HoldTimeMax = MainTab:CreateSlider({
    Name = "Max Hold",
    Range = {0, 3},
    Increment = 0.01,
    Suffix = "s",
    CurrentValue = 0.25,
    Flag = "HoldTimeMax",
    Callback = function(Value)
        getgenv().AutoFishSettings.HoldTimeMax = Value
    end,
})

-- ========== SECTION: Minigame ==========
local MinigameSection = MainTab:CreateSection("Minigame")

UIElements.AutoComplete = MainTab:CreateToggle({
    Name = "Auto Complete",
    CurrentValue = true,
    Flag = "AutoComplete",
    Callback = function(Value)
        getgenv().AutoFishSettings.AutoComplete = Value
    end,
})

UIElements.MinigameDelayMin = MainTab:CreateSlider({
    Name = "Min Delay",
    Range = {0, 15},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 2.1,
    Flag = "MinigameDelayMin",
    Callback = function(Value)
        getgenv().AutoFishSettings.MinigameDelayMin = Value
    end,
})

UIElements.MinigameDelayMax = MainTab:CreateSlider({
    Name = "Max Delay",
    Range = {0, 15},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 2.3,
    Flag = "MinigameDelayMax",
    Callback = function(Value)
        getgenv().AutoFishSettings.MinigameDelayMax = Value
    end,
})

-- ========== SECTION: Teleport & Spot Rotation ==========
local TeleportSection = MainTab:CreateSection("Teleport & Spot Rotation")

UIElements.SafeSpotEnabled = MainTab:CreateToggle({
    Name = "Use Safe Fishing Spot",
    CurrentValue = false,
    Flag = "SafeSpotEnabled",
    Callback = function(Value)
        getgenv().AutoFishSettings.SafeSpotEnabled = Value
        if Value then
            Rayfield:Notify({Title = "Safe Spot", Content = "Safe spot enabled!", Duration = 3})
        else
            if #FishingPlatforms > 0 then
                removeAllPlatforms()
            end
        end
    end,
})

UIElements.CreatePlatform = MainTab:CreateToggle({
    Name = "Create Platforms",
    CurrentValue = true,
    Flag = "CreatePlatform",
    Callback = function(Value)
        getgenv().AutoFishSettings.CreatePlatform = Value
    end,
})

UIElements.LockCharacter = MainTab:CreateToggle({
    Name = "Lock Character",
    CurrentValue = true,
    Flag = "LockCharacter",
    Callback = function(Value)
        getgenv().AutoFishSettings.LockCharacter = Value
        if not Value and CharacterLocked then
            unlockCharacter()
        end
    end,
})

MainTab:CreateButton({
    Name = "TP to Current Spot",
    Callback = function()
        teleportToSpot(CurrentSpotIndex)
    end,
})

MainTab:CreateButton({
    Name = "Unlock Character",
    Callback = function()
        unlockCharacter()
    end,
})

-- ========== SECTION: Spot Rotation (Anti Luck Decay) ==========
local SpotRotSection = MainTab:CreateSection("Spot Rotation (Anti Luck Decay)")

UIElements.SpotRotationEnabled = MainTab:CreateToggle({
    Name = "Enable Spot Rotation",
    CurrentValue = true,
    Flag = "SpotRotationEnabled",
    Callback = function(Value)
        getgenv().AutoFishSettings.SpotRotationEnabled = Value
    end,
})

UIElements.SpotRotationInterval = MainTab:CreateSlider({
    Name = "Catches per Spot",
    Range = {1, 50},
    Increment = 1,
    Suffix = " catches",
    CurrentValue = 5,
    Flag = "SpotRotationInterval",
    Callback = function(Value)
        getgenv().AutoFishSettings.SpotRotationInterval = Value
    end,
})

UIElements.SpotOffset = MainTab:CreateSlider({
    Name = "Spot Distance",
    Range = {10, 200},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 40,
    Flag = "SpotOffset",
    Callback = function(Value)
        getgenv().AutoFishSettings.SpotOffset = Value
    end,
})

MainTab:CreateButton({
    Name = "Create 3 Platforms",
    Callback = function()
        createAllPlatforms()
    end,
})

MainTab:CreateButton({
    Name = "Force Next Spot",
    Callback = function()
        Stats.spotCastsAtCurrentSpot = 0
        local nextSpot = (CurrentSpotIndex % 3) + 1

        State.isPaused = true
        unequipRod()
        task.wait(0.3)
        teleportToSpot(nextSpot)
        task.wait(1)
        equipRod()
        task.wait(0.5)
        setupMinigame()
        task.wait(0.5)
        State.isPaused = false
        State.isCasting = false
        State.inMinigame = false
        State.isEquipping = false
        setState("Ready")
    end,
})

MainTab:CreateButton({
    Name = "Remove All Platforms",
    Callback = function()
        removeAllPlatforms()
        Rayfield:Notify({Title = "Platforms", Content = "All platforms removed", Duration = 2})
    end,
})

-- ========== SECTION: Advanced ==========
local AdvancedSection = MainTab:CreateSection("Advanced")

UIElements.UnequipAfterCatch = MainTab:CreateToggle({
    Name = "Unequip After Catch",
    CurrentValue = true,
    Flag = "UnequipAfterCatch",
    Callback = function(Value)
        getgenv().AutoFishSettings.UnequipAfterCatch = Value
    end,
})

UIElements.UnequipDelay = MainTab:CreateSlider({
    Name = "Unequip Delay",
    Range = {0, 2},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 0.1,
    Flag = "UnequipDelay",
    Callback = function(Value)
        getgenv().AutoFishSettings.UnequipDelay = Value
    end,
})

UIElements.ReequipDelay = MainTab:CreateSlider({
    Name = "Re-equip Delay",
    Range = {0, 2},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 0.1,
    Flag = "ReequipDelay",
    Callback = function(Value)
        getgenv().AutoFishSettings.ReequipDelay = Value
    end,
})

UIElements.RandomPause = MainTab:CreateToggle({
    Name = "Random Pauses",
    CurrentValue = true,
    Flag = "RandomPause",
    Callback = function(Value)
        getgenv().AutoFishSettings.RandomPause = Value
    end,
})

UIElements.PauseChance = MainTab:CreateSlider({
    Name = "Pause %",
    Range = {0, 50},
    Increment = 1,
    Suffix = "%",
    CurrentValue = 7,
    Flag = "PauseChance",
    Callback = function(Value)
        getgenv().AutoFishSettings.PauseChance = Value
    end,
})

UIElements.Debug = MainTab:CreateToggle({
    Name = "Debug",
    CurrentValue = false,
    Flag = "Debug",
    Callback = function(Value)
        getgenv().AutoFishSettings.Debug = Value
    end,
})

-- ========== SECTION: Safe Mode ==========
local SafeSection = MainTab:CreateSection("Safe Mode")

UIElements.SafeMode = MainTab:CreateToggle({
    Name = "Enable Safe Mode",
    CurrentValue = true,
    Flag = "SafeMode",
    Callback = function(Value)
        getgenv().AutoFishSettings.SafeMode = Value
    end,
})

UIElements.AutoRestart = MainTab:CreateToggle({
    Name = "Auto Restart",
    CurrentValue = true,
    Flag = "AutoRestart",
    Callback = function(Value)
        getgenv().AutoFishSettings.AutoRestart = Value
    end,
})

UIElements.StuckTimeout = MainTab:CreateSlider({
    Name = "Stuck Timeout",
    Range = {5, 120},
    Increment = 1,
    Suffix = "s",
    CurrentValue = 30,
    Flag = "StuckTimeout",
    Callback = function(Value)
        getgenv().AutoFishSettings.StuckTimeout = Value
    end,
})

UIElements.MaxConsecutiveFails = MainTab:CreateSlider({
    Name = "Max Fails",
    Range = {1, 20},
    Increment = 1,
    Suffix = "",
    CurrentValue = 5,
    Flag = "MaxConsecutiveFails",
    Callback = function(Value)
        getgenv().AutoFishSettings.MaxConsecutiveFails = Value
    end,
})

-- ========== TAB: Statistics ==========
local StatusSection = StatsTab:CreateSection("Status")

local StatusLabel = StatsTab:CreateLabel("Status: Stopped")
local StateLabel = StatsTab:CreateLabel("State: Script initialized")
local RodLabel = StatsTab:CreateLabel("Rod: Not Equipped")
local SpotLabel = StatsTab:CreateLabel("Spot: 1/3 (0/5 catches)")

local StatsSection = StatsTab:CreateSection("Statistics")

local FishLabel = StatsTab:CreateLabel("Fish Caught: 0")
local CastsLabel = StatsTab:CreateLabel("Total Casts: 0")
local FailedLabel = StatsTab:CreateLabel("Failed: 0")
local SellsLabel = StatsTab:CreateLabel("Sells: 0")
local PausesLabel = StatsTab:CreateLabel("Pauses: 0")
local ResetsLabel = StatsTab:CreateLabel("Stuck Resets: 0")
local RotationsLabel = StatsTab:CreateLabel("Spot Rotations: 0")
local UptimeLabel = StatsTab:CreateLabel("Uptime: 0m")
local RateLabel = StatsTab:CreateLabel("Fish/Hour: 0")

-- Stats updater
task.spawn(function()
    while true do
        task.wait(1)

        pcall(function()
            local status = getgenv().AutoFishSettings.Enabled and "Running" or "Stopped"
            local uptime = math.floor((tick() - Stats.startTime) / 60)
            local rate = 0
            if (tick() - Stats.startTime) > 0 then
                rate = math.floor(Stats.fish / ((tick() - Stats.startTime) / 3600))
            end

            StatusLabel:Set("Status: " .. status)
            StateLabel:Set("State: " .. State.currentState)
            RodLabel:Set("Rod: " .. State.currentRodName)
            SpotLabel:Set("Spot: " .. CurrentSpotIndex .. "/3 (" .. Stats.spotCastsAtCurrentSpot .. "/" .. getgenv().AutoFishSettings.SpotRotationInterval .. " catches)")

            FishLabel:Set("Fish Caught: " .. Stats.fish)
            CastsLabel:Set("Total Casts: " .. Stats.casts)
            FailedLabel:Set("Failed: " .. Stats.failed)
            SellsLabel:Set("Sells: " .. Stats.sells)
            PausesLabel:Set("Pauses: " .. Stats.pauses)
            ResetsLabel:Set("Stuck Resets: " .. Stats.stuckResets)
            RotationsLabel:Set("Spot Rotations: " .. Stats.spotRotations)
            UptimeLabel:Set("Uptime: " .. uptime .. "m")
            RateLabel:Set("Fish/Hour: " .. rate)
        end)
    end
end)

-- ========== TAB: Settings ==========
local UISettingsSection = SettingsTab:CreateSection("UI Settings")

SettingsTab:CreateButton({
    Name = "Destroy UI",
    Callback = function()
        removeAllPlatforms()
        unlockCharacter()
        Rayfield:Destroy()
    end,
})

-- ==================== START ALL SYSTEMS ====================

startAutoFish()
startAutoSell()
startSafeMode()
monitorRodChanges()

print("=== AUTO FISHING v8.2 RAYFIELD LOADED ===")
print("=== Direct Re-equip + Fast Loop ===")
Rayfield:Notify({Title = "Auto Fishing v8.2", Content = "Loaded! Direct re-equip + fast loop.", Duration = 3})
