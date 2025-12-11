local args = _E and _E.ARGS or {}
local uis = game:GetService("UserInputService")
local lp = game.Players.LocalPlayer
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local Players = game.Players
local TextChatService = game:GetService("TextChatService")

-- ================ 配置參數 ================
local Config = {
    -- ESP設置
    ESP = {
        Enabled = false,
        ShowBox = true,
        ShowHealth = true,
        ShowName = true,
        ShowDistance = true,
        ShowTool = true,
        ShowTracer = true,
        ShowSkeleton = true,
        ShowFOV = true,
        ChamsEnabled = false,
        TeamCheck = false,
        MaxDistance = 1000,
        TracerAimableColor = Color3.fromRGB(255, 0, 0),
        TracerUnaimableColor = Color3.fromRGB(0, 255, 0),
        SkeletonAimableColor = Color3.fromRGB(255, 0, 0),
        SkeletonUnaimableColor = Color3.fromRGB(0, 255, 0),
        BoxColor = Color3.fromRGB(255, 255, 255),
        BoxTransparency = 0.5,
        ChamsFillColor = Color3.fromRGB(255, 0, 0),
        ChamsTransparency = 0.5,
        FOVColor = Color3.fromRGB(255, 255, 255),
        NameColor = Color3.fromRGB(255, 255, 255),
        DistanceColor = Color3.fromRGB(128, 0, 255),
        ToolColor = Color3.fromRGB(255, 255, 0),
        HealthOutlineColor = Color3.fromRGB(255,255,255)
    },
    -- 自瞄設置
    Aimbot = {
        Enabled = false,
        AimPart = "Head",
        Smooth = 0.9,
        FOV = 350,
        TargetCacheTime = 0.2,
        LastTarget = nil,
        LastTargetTime = 0
    },
    -- 移動設置（穿牆+飛天 雙開）
    Move = {
        Speed = 100,
        Enabled = false
    },
    AutoJump = {
        Enabled = false,
        Connection = nil
    },
    FirstPersonFOV = {
        Enabled = false,
        DefaultValue = 200,
        OriginalFOV = Camera.FieldOfView
    },
    Noclip = {
        Connection = nil
    },
    AutoRotate = {
        Enabled = false,
        RotateSpeed = 1800,
        RotateConnection = nil
    },
    -- 自動發消息配置
    AutoMsg = {
        IsEnabled = false,
        SendInterval = 3,
        IntervalStep = 0.5,
        MinInterval = 0.5,
        MaxInterval = 10
    }
}

-- ================ 全局變量 ================
local Drawings = {}
local Highlights = {}
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 2
FOVCircle.NumSides = 80
FOVCircle.Filled = false
FOVCircle.Color = Config.ESP.FOVColor
FOVCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
FOVCircle.Visible = Config.ESP.ShowFOV and Config.Aimbot.Enabled

local LocalCharacter = lp.Character or lp.CharacterAdded:Wait()
local LocalRoot = LocalCharacter:WaitForChild("HumanoidRootPart")
local LocalHumanoid = LocalCharacter:WaitForChild("Humanoid")
local FlyGyro = nil
local NoclipMoveConn = nil

-- ================ 核心工具函數 ================
local function RefreshFOVCircle()
    FOVCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    FOVCircle.Radius = Config.Aimbot.FOV
    FOVCircle.Color = Config.ESP.FOVColor
    FOVCircle.Visible = Config.ESP.ShowFOV and Config.Aimbot.Enabled
end

local function Cleanup(plr)
    if plr then
        local comp = Drawings[plr]
        if comp then
            pcall(function() comp.Box:Remove() end)
            pcall(function() comp.Tracer:Remove() end)
            pcall(function() comp.NameLabel:Remove() end)
            pcall(function() comp.DistanceLabel:Remove() end)
            pcall(function() comp.HealthBar.Outline:Remove() end)
            pcall(function() comp.HealthBar.Fill:Remove() end)
            pcall(function() comp.ToolLabel:Remove() end)
            for _, line in pairs(comp.Skeleton) do pcall(function() line:Remove() end) end
            Drawings[plr] = nil
        end
        if Highlights[plr] then
            pcall(function() Highlights[plr]:Destroy() end)
            Highlights[plr] = nil
        end
        return
    end
    for p in pairs(Drawings) do Cleanup(p) end
    if FlyGyro then FlyGyro:Destroy() end
    FlyGyro = nil
    if Config.Noclip.Connection then Config.Noclip.Connection:Disconnect() end
    Config.Noclip.Connection = nil
    if NoclipMoveConn then NoclipMoveConn:Disconnect() end
    NoclipMoveConn = nil
    if Config.AutoJump.Connection then Config.AutoJump.Connection:Disconnect() end
    Config.AutoJump.Connection = nil
    if Config.FirstPersonFOV.Enabled then Camera.FieldOfView = Config.FirstPersonFOV.OriginalFOV end
    Config.FirstPersonFOV.Enabled = false
    if Config.AutoRotate.RotateConnection then Config.AutoRotate.RotateConnection:Disconnect() end
    Config.AutoRotate.RotateConnection = nil
end

-- 完全還原原代碼的IsPlayerAimable函數，無誤改
local function IsPlayerAimable(plr)
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return false end
    if Config.ESP.TeamCheck and plr.Team == lp.Team then return false end

    local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
    if not onScreen then return false end

    local centerPos = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local fovDist = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
    if fovDist > Config.Aimbot.FOV then return false end

    local realDist = (LocalRoot.Position - root.Position).Magnitude
    if realDist > Config.ESP.MaxDistance then return false end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalCharacter, char}
    rayParams.IgnoreWater = true
    local hitResult = workspace:Raycast(Camera.CFrame.Position, (root.Position - Camera.CFrame.Position), rayParams)
    return hitResult == nil
end

-- ================ 功能實現函數 ================
-- 自動跳
local function ToggleAutoJump(state)
    Config.AutoJump.Enabled = state
    if Config.AutoJump.Connection then Config.AutoJump.Connection:Disconnect() end
    Config.AutoJump.Connection = nil
    if state then
        if LocalHumanoid.FloorMaterial ~= Enum.Material.Air then
            LocalHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        Config.AutoJump.Connection = LocalHumanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
            if LocalHumanoid.FloorMaterial ~= Enum.Material.Air then
                LocalHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
end

-- FOV視距
local function ToggleFirstPersonFOV(state)
    Config.FirstPersonFOV.Enabled = state
    if state then
        Config.FirstPersonFOV.OriginalFOV = Camera.FieldOfView
        Camera.FieldOfView = Config.FirstPersonFOV.DefaultValue
        if NoclipMoveConn then NoclipMoveConn:Disconnect() end
        NoclipMoveConn = RunService.RenderStepped:Connect(function()
            if Config.FirstPersonFOV.Enabled then Camera.FieldOfView = Config.FirstPersonFOV.DefaultValue end
        end)
    else
        Camera.FieldOfView = Config.FirstPersonFOV.OriginalFOV
        if NoclipMoveConn then NoclipMoveConn:Disconnect() end
        NoclipMoveConn = nil
    end
end

-- 穿牆飛天
local function InitFly()
    FlyGyro = Instance.new("BodyGyro")
    FlyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    FlyGyro.P = 5000
    FlyGyro.Parent = LocalRoot
end

local function ToggleNoclipFly(state)
    Config.Move.Enabled = state
    if Config.Noclip.Connection then Config.Noclip.Connection:Disconnect() end
    Config.Noclip.Connection = nil
    if NoclipMoveConn then NoclipMoveConn:Disconnect() end
    NoclipMoveConn = nil
    if FlyGyro then FlyGyro:Destroy() end
    FlyGyro = nil

    if state then
        Config.Noclip.Connection = RunService.Heartbeat:Connect(function()
            if not LocalCharacter then return end
            for _, part in pairs(LocalCharacter:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end)
        InitFly()
        NoclipMoveConn = RunService.RenderStepped:Connect(function()
            if not LocalRoot or not FlyGyro then return end
            FlyGyro.CFrame = Camera.CFrame
            local moveVector = require(lp.PlayerScripts.PlayerModule.ControlModule):GetMoveVector()
            local cameraRelativeMovement = Camera.CFrame:VectorToWorldSpace(Vector3.new(moveVector.X, 0, moveVector.Z))
            local yMovement = Camera.CFrame.UpVector * moveVector.Y
            local finalMove = (cameraRelativeMovement + yMovement).Unit
            LocalRoot.Velocity = finalMove * Config.Move.Speed
        end)
    else
        if LocalCharacter then
            for _, part in pairs(LocalCharacter:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
        if LocalRoot then LocalRoot.Velocity = Vector3.new(0,0,0) end
    end
end

-- 自動旋轉
local function SetupAutoRotate(character)
    local hrp = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.AutoRotate = false
    Camera.CameraType = Enum.CameraType.Track

    if Config.AutoRotate.RotateConnection then Config.AutoRotate.RotateConnection:Disconnect() end
    if Config.AutoRotate.Enabled then
        Config.AutoRotate.RotateConnection = RunService.RenderStepped:Connect(function(deltaTime)
            local rotateAngle = math.rad(Config.AutoRotate.RotateSpeed * deltaTime)
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, rotateAngle, 0)
        end)
    end
end

local function ToggleAutoRotate(state)
    Config.AutoRotate.Enabled = state
    if LocalCharacter then SetupAutoRotate(LocalCharacter) end
    lp.CharacterAdded:Connect(SetupAutoRotate)
end

-- 自動發消息
local function SendAutoMessage(content)
    if not content or content == "" then return end
    local generalChannel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
    if generalChannel then generalChannel:SendAsync(content) end
end

local function AutoMsgLoop(inputBox)
    while Config.AutoMsg.IsEnabled do
        SendAutoMessage(inputBox.Text)
        task.wait(Config.AutoMsg.SendInterval)
    end
end

-- ================ ESP創建與更新 ================
local function CreateESP(plr)
    if plr == lp or Drawings[plr] then return end
    local comp = {
        Box = Drawing.new("Square"),
        Tracer = Drawing.new("Line"),
        NameLabel = Drawing.new("Text"),
        DistanceLabel = Drawing.new("Text"),
        HealthBar = { Outline = Drawing.new("Square"), Fill = Drawing.new("Square") },
        ToolLabel = Drawing.new("Text"),
        Skeleton = {}
    }
    comp.Box.Filled = true
    comp.Box.Transparency = Config.ESP.BoxTransparency
    comp.Box.Color = Config.ESP.BoxColor
    comp.Tracer.Thickness = 1
    comp.NameLabel.Size = 18
    comp.NameLabel.Center = true
    comp.NameLabel.Outline = true
    comp.NameLabel.Color = Config.ESP.NameColor
    comp.DistanceLabel.Size = 16
    comp.DistanceLabel.Center = true
    comp.DistanceLabel.Outline = true
    comp.DistanceLabel.Color = Config.ESP.DistanceColor
    comp.HealthBar.Outline.Thickness = 1
    comp.HealthBar.Outline.Filled = false
    comp.HealthBar.Outline.Color = Config.ESP.HealthOutlineColor
    comp.HealthBar.Fill.Thickness = 1
    comp.HealthBar.Fill.Filled = true
    comp.ToolLabel.Size = 16
    comp.ToolLabel.Center = true
    comp.ToolLabel.Outline = true
    comp.ToolLabel.Color = Config.ESP.ToolColor

    local hl = Instance.new("Highlight")
    hl.FillColor = Config.ESP.ChamsFillColor
    hl.OutlineColor = Color3.fromRGB(255,255,255)
    hl.FillTransparency = Config.ESP.ChamsTransparency
    hl.OutlineTransparency = 0
    hl.Enabled = false
    hl.Parent = plr.Character
    Highlights[plr] = hl
    Drawings[plr] = comp
end

local function UpdateESP(plr)
    local comp = Drawings[plr]
    if not comp or not Config.ESP.Enabled then
        Cleanup(plr)
        return
    end
    local char = plr.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hum or not root or hum.Health <= 0 then
        comp.Box.Visible = false
        comp.Tracer.Visible = false
        comp.NameLabel.Visible = false
        comp.DistanceLabel.Visible = false
        comp.HealthBar.Outline.Visible = false
        comp.HealthBar.Fill.Visible = false
        comp.ToolLabel.Visible = false
        for _, line in pairs(comp.Skeleton) do line.Visible = false end
        if Highlights[plr] then Highlights[plr].Enabled = false end
        return
    end
    if Config.ESP.TeamCheck and plr.Team == lp.Team then
        comp.Box.Visible = false
        comp.Tracer.Visible = false
        comp.NameLabel.Visible = false
        comp.DistanceLabel.Visible = false
        comp.HealthBar.Outline.Visible = false
        comp.HealthBar.Fill.Visible = false
        comp.ToolLabel.Visible = false
        for _, line in pairs(comp.Skeleton) do line.Visible = false end
        if Highlights[plr] then Highlights[plr].Enabled = false end
        return
    end

    local isAimable = IsPlayerAimable(plr)
    local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)
    local distance = math.floor((LocalRoot.Position - root.Position).Magnitude)
    local healthPercent = hum.Health / hum.MaxHealth
    local topPos = Camera:WorldToViewportPoint((root.CFrame + Vector3.new(0, 3, 0)).Position)
    local bottomPos = Camera:WorldToViewportPoint((root.CFrame - Vector3.new(0, 1, 0)).Position)
    local boxHeight = math.abs(topPos.Y - bottomPos.Y)
    local boxWidth = boxHeight / 2.5
    local boxX = rootPos.X - boxWidth / 2
    local boxY = rootPos.Y - boxHeight / 2

    -- 方框
    comp.Box.Visible = Config.ESP.ShowBox and onScreen
    if comp.Box.Visible then
        comp.Box.Size = Vector2.new(boxWidth, boxHeight)
        comp.Box.Position = Vector2.new(boxX, boxY)
        comp.Box.Color = Config.ESP.BoxColor
        comp.Box.Transparency = Config.ESP.BoxTransparency
    end

    -- 血條
    local healthWidth = 5
    local healthHeight = boxHeight
    local healthX = boxX - healthWidth - 5
    local healthY = boxY
    comp.HealthBar.Outline.Visible = Config.ESP.ShowHealth and onScreen
    comp.HealthBar.Fill.Visible = Config.ESP.ShowHealth and onScreen
    if comp.HealthBar.Outline.Visible then
        comp.HealthBar.Outline.Position = Vector2.new(healthX, healthY)
        comp.HealthBar.Outline.Size = Vector2.new(healthWidth, healthHeight)
        local fillHeight = healthHeight * healthPercent
        local fillY = healthY + (healthHeight - fillHeight)
        comp.HealthBar.Fill.Position = Vector2.new(healthX, fillY)
        comp.HealthBar.Fill.Size = Vector2.new(healthWidth, fillHeight)
        comp.HealthBar.Fill.Color = healthPercent > 0.5 and Color3.fromRGB(0,255,0) or (healthPercent > 0.2 and Color3.fromRGB(255,255,0) or Color3.fromRGB(255,0,0))
    end

    -- 名稱
    local nameY = boxY - 20
    comp.NameLabel.Visible = Config.ESP.ShowName and onScreen
    if comp.NameLabel.Visible then
        comp.NameLabel.Text = "[" .. plr.Name .. "]"
        comp.NameLabel.Position = Vector2.new(rootPos.X, nameY)
    end

    -- 距離
    local distanceY = boxY + boxHeight + 5
    comp.DistanceLabel.Visible = Config.ESP.ShowDistance and onScreen
    if comp.DistanceLabel.Visible then
        comp.DistanceLabel.Text = "距離: " .. distance .. "M"
        comp.DistanceLabel.Position = Vector2.new(rootPos.X, distanceY)
    end

    -- 武器
    local toolY = distanceY + 18
    comp.ToolLabel.Visible = Config.ESP.ShowTool and onScreen
    if comp.ToolLabel.Visible then
        local tool = plr.Backpack:FindFirstChildOfClass("Tool") or char:FindFirstChildOfClass("Tool")
        comp.ToolLabel.Text = tool and "武器: " .. tool.Name or "無武器"
        comp.ToolLabel.Position = Vector2.new(rootPos.X, toolY)
    end

    -- 射線
    comp.Tracer.Visible = Config.ESP.ShowTracer and onScreen
    if comp.Tracer.Visible then
        comp.Tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
        comp.Tracer.To = Vector2.new(rootPos.X, rootPos.Y)
        comp.Tracer.Color = isAimable and Config.ESP.TracerAimableColor or Config.ESP.TracerUnaimableColor
    end

    -- 骨骼
    local SkeletonConnections = {
        R15 = {{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"LowerTorso","LeftUpperLeg"},{"LowerTorso","RightUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},{"UpperTorso","LeftUpperArm"},{"UpperTorso","RightUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"}},
        R6 = {{"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"}}
    }
    local conns = SkeletonConnections[hum.RigType.Name] or {}
    for _, line in pairs(comp.Skeleton) do line.Visible = false end
    if Config.ESP.ShowSkeleton and onScreen then
        for _, conn in ipairs(conns) do
            local a = char:FindFirstChild(conn[1])
            local b = char:FindFirstChild(conn[2])
            local lineKey = conn[1] .. "-" .. conn[2]
            local line = comp.Skeleton[lineKey]
            if not line then
                line = Drawing.new("Line")
                line.Thickness = 1
                line.ZIndex = 5
                comp.Skeleton[lineKey] = line
            end
            if a and b then
                local aPos = Camera:WorldToViewportPoint(a.Position)
                local bPos = Camera:WorldToViewportPoint(b.Position)
                line.From = Vector2.new(aPos.X, aPos.Y)
                line.To = Vector2.new(bPos.X, bPos.Y)
                line.Visible = true
                line.Color = isAimable and Config.ESP.SkeletonAimableColor or Config.ESP.SkeletonUnaimableColor
            else
                line.Visible = false
            end
        end
    end

    -- 高亮
    if Highlights[plr] then
        Highlights[plr].Enabled = Config.ESP.ChamsEnabled and onScreen
    end
end

-- ================ 自瞄核心 ================
local function FindBestTarget()
    local closestPart = nil
    local closestDist = math.huge
    local centerPos = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    if Config.Aimbot.LastTarget and Config.Aimbot.LastTarget.Parent then
        local targetPlr = Players:GetPlayerFromCharacter(Config.Aimbot.LastTarget.Parent)
        if targetPlr and Config.ESP.TeamCheck and targetPlr.Team == lp.Team then
            Config.Aimbot.LastTarget = nil
        else
            local hum = Config.Aimbot.LastTarget.Parent:FindFirstChild("Humanoid")
            local root = Config.Aimbot.LastTarget.Parent:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and root then
                local targetPart = Config.Aimbot.LastTarget.Parent:FindFirstChild(Config.Aimbot.AimPart) or Config.Aimbot.LastTarget
                local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                local fovDist = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
                local realDist = (LocalRoot.Position - targetPart.Position).Magnitude
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                rayParams.FilterDescendantsInstances = {LocalCharacter, Config.Aimbot.LastTarget.Parent}
                local hitResult = workspace:Raycast(Camera.CFrame.Position, (targetPart.Position - Camera.CFrame.Position), rayParams)
                if onScreen and not hitResult and fovDist <= Config.Aimbot.FOV and realDist <= Config.ESP.MaxDistance then
                    return targetPart
                end
            end
        end
    end
    for _, plr in pairs(Players:GetPlayers()) do
        if plr == lp then continue end
        if Config.ESP.TeamCheck and plr.Team == lp.Team then continue end
        local char = plr.Character
        local hum = char and char:FindFirstChild("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not hum or not root or hum.Health <= 0 then continue end
        local targetPart = char:FindFirstChild(Config.Aimbot.AimPart) or root
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        local fovDist = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
        local realDist = (LocalRoot.Position - targetPart.Position).Magnitude
        if not onScreen or fovDist > Config.Aimbot.FOV or realDist > Config.ESP.MaxDistance then continue end
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
        rayParams.FilterDescendantsInstances = {LocalCharacter, char}
        local hitResult = workspace:Raycast(Camera.CFrame.Position, (targetPart.Position - Camera.CFrame.Position), rayParams)
        if hitResult then continue end
        if realDist < closestDist then
            closestDist = realDist
            closestPart = targetPart
        end
    end
    Config.Aimbot.LastTarget = closestPart
    Config.Aimbot.LastTargetTime = tick()
    return closestPart
end

-- ================ GUI工具函數 ================
local function CreateSliderToggle(parent, text, default, posX, posY, callback)
    local width, height = 100, 25
    local toggleFrame = Instance.new("Frame", parent)
    toggleFrame.Size = UDim2.new(0, width, 0, height)
    toggleFrame.Position = UDim2.new(0, posX, 0, posY)
    toggleFrame.BackgroundColor3 = Color3.fromRGB(50,50,50)
    local corner = Instance.new("UICorner", toggleFrame)
    corner.CornerRadius = UDim.new(0, height/2)
    local toggleBtn = Instance.new("TextButton", toggleFrame)
    toggleBtn.Size = UDim2.new(0.45,0,0.9,0)
    toggleBtn.Position = UDim2.new(default and 0.55 or 0.05,0,0.05,0)
    toggleBtn.BackgroundColor3 = default and Color3.fromRGB(0,180,0) or Color3.fromRGB(100,100,100)
    toggleBtn.Text = ""
    local btnCorner = Instance.new("UICorner", toggleBtn)
    btnCorner.CornerRadius = UDim.new(0, (height*0.9)/2)
    local label = Instance.new("TextLabel", toggleFrame)
    label.Size = UDim2.new(1,0,1,0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.new(1,1,1)
    label.TextSize = height*0.6
    label.Font = Enum.Font.Gotham
    label.ZIndex = 2
    local state = default
    toggleBtn.MouseButton1Click:Connect(function()
        state = not state
        toggleBtn.Position = UDim2.new(state and 0.55 or 0.05,0,0.05,0)
        toggleBtn.BackgroundColor3 = state and Color3.fromRGB(0,180,0) or Color3.fromRGB(100,100,100)
        callback(state)
        if text == "隊友隱藏" then Config.Aimbot.LastTarget = nil end
    end)
    return toggleFrame
end

local function CreatePlusMinusAdjuster(parent, text, defaultValue, step, isSmooth, minVal, maxVal, posX, posY, callback)
    local width, height = 150, 25
    local currentVal = defaultValue
    local adjustFrame = Instance.new("Frame", parent)
    adjustFrame.Size = UDim2.new(0, width, 0, height)
    adjustFrame.Position = UDim2.new(0, posX, 0, posY)
    adjustFrame.BackgroundColor3 = Color3.fromRGB(40,40,40)
    local corner = Instance.new("UICorner", adjustFrame)
    corner.CornerRadius = UDim.new(0,6)
    local label = Instance.new("TextLabel", adjustFrame)
    label.Size = UDim2.new(0.4,0,1,0)
    label.Position = UDim2.new(0.3,0,0,0)
    label.BackgroundTransparency = 1
    local displayVal = isSmooth and string.format("%.2f", currentVal) or tostring(math.floor(currentVal))
    label.Text = text..":"..displayVal
    label.TextColor3 = Color3.fromRGB(0,200,255)
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    local minusBtn = Instance.new("TextButton", adjustFrame)
    minusBtn.Size = UDim2.new(0.3,0,1,0)
    minusBtn.Position = UDim2.new(0,0,0,0)
    minusBtn.BackgroundColor3 = Color3.fromRGB(150,0,0)
    minusBtn.Text = "-"
    minusBtn.TextColor3 = Color3.new(1,1,1)
    minusBtn.TextSize = 14
    minusBtn.Font = Enum.Font.GothamBold
    local minusCorner = Instance.new("UICorner", minusBtn)
    minusCorner.CornerRadius = UDim.new(0,4)
    local plusBtn = Instance.new("TextButton", adjustFrame)
    plusBtn.Size = UDim2.new(0.3,0,1,0)
    plusBtn.Position = UDim2.new(0.7,0,0,0)
    plusBtn.BackgroundColor3 = Color3.fromRGB(0,150,0)
    plusBtn.Text = "+"
    plusBtn.TextColor3 = Color3.new(1,1,1)
    plusBtn.TextSize = 14
    plusBtn.Font = Enum.Font.GothamBold
    local plusCorner = Instance.new("UICorner", plusBtn)
    plusCorner.CornerRadius = UDim.new(0,4)
    local function UpdateLabel()
        local displayVal = isSmooth and string.format("%.2f", currentVal) or tostring(math.floor(currentVal))
        label.Text = text..":"..displayVal
        callback(currentVal)
        if not isSmooth then RefreshFOVCircle() end
    end
    minusBtn.MouseButton1Click:Connect(function()
        if currentVal - step >= minVal then
            currentVal -= step
            UpdateLabel()
        end
    end)
    plusBtn.MouseButton1Click:Connect(function()
        if currentVal + step <= maxVal then
            currentVal += step
            UpdateLabel()
        end
    end)
end

-- ================ GUI創建 ================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UniversalAimbotESP"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game:GetService("CoreGui")

local FloatBtn = Instance.new("TextButton", ScreenGui)
FloatBtn.Size = UDim2.new(0,40,0,40)
FloatBtn.Position = UDim2.new(0,20,1,-55)
FloatBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
FloatBtn.BackgroundTransparency = 0.3
FloatBtn.Text = "主"
FloatBtn.TextColor3 = Color3.new(1,1,1)
FloatBtn.TextScaled = true
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
local FloatCorner = Instance.new("UICorner", FloatBtn)
FloatCorner.CornerRadius = UDim.new(1,0)
local FloatStroke = Instance.new("UIStroke", FloatBtn)
FloatStroke.Color = Color3.fromRGB(100,100,100)
FloatStroke.Thickness = 1

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0,700,0,360)
MainFrame.Position = UDim2.new(0.5,-350,1,-380)
MainFrame.BackgroundColor3 = Color3.fromRGB(25,25,25)
MainFrame.Visible = false
MainFrame.Active = true
MainFrame.Draggable = true
local MainCorner = Instance.new("UICorner", MainFrame)
MainCorner.CornerRadius = UDim.new(0,8)
local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Color3.fromRGB(80,80,80)
MainStroke.Thickness = 1
local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1,0,0,30)
Title.BackgroundTransparency = 1
Title.Text = "Roblox ESP/Aimbot/Fly"
Title.TextColor3 = Color3.new(1,1,1)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.Position = UDim2.new(0,0,0,5)
Title.TextXAlignment = Enum.TextXAlignment.Center

-- 基礎功能控件
CreatePlusMinusAdjuster(MainFrame, "移動速度", Config.Move.Speed, 10, false, 90, 500, 10, 40, function(val) Config.Move.Speed = val end)
CreateSliderToggle(MainFrame, "ESP總開啟", false, 10, 75, function(v)
    Config.ESP.Enabled = v
    if v then for _, plr in pairs(Players:GetPlayers()) do if plr ~= lp then CreateESP(plr) end end else Cleanup() end
end)
CreateSliderToggle(MainFrame, "方框", true, 120, 75, function(v) Config.ESP.ShowBox = v end)
CreateSliderToggle(MainFrame, "射線", true, 230, 75, function(v) Config.ESP.ShowTracer = v end)
CreateSliderToggle(MainFrame, "骨骼", true, 340, 75, function(v) Config.ESP.ShowSkeleton = v end)
CreateSliderToggle(MainFrame, "高亮", false, 450, 75, function(v) Config.ESP.ChamsEnabled = v end)
CreateSliderToggle(MainFrame, "血條", true, 560, 75, function(v) Config.ESP.ShowHealth = v end)
CreateSliderToggle(MainFrame, "名稱", true, 10, 110, function(v) Config.ESP.ShowName = v end)
CreateSliderToggle(MainFrame, "距離", true, 155, 110, function(v) Config.ESP.ShowDistance = v end)
CreateSliderToggle(MainFrame, "武器", true, 300, 110, function(v) Config.ESP.ShowTool = v end)
CreateSliderToggle(MainFrame, "隊友隱藏", false, 445, 110, function(v) Config.ESP.TeamCheck = v end)
CreateSliderToggle(MainFrame, "顯示FOV", true, 590, 110, function(v) Config.ESP.ShowFOV = v end)
CreateSliderToggle(MainFrame, "自瞄總開啟", false, 10, 145, function(v) Config.Aimbot.Enabled = v end)

local AimPartBtn = Instance.new("TextButton", MainFrame)
AimPartBtn.Size = UDim2.new(0,100,0,25)
AimPartBtn.Position = UDim2.new(0,120,0,145)
AimPartBtn.BackgroundColor3 = Color3.fromRGB(100,100,255)
AimPartBtn.Text = "鎖頭"
AimPartBtn.TextColor3 = Color3.new(1,1,1)
AimPartBtn.TextSize = 14
AimPartBtn.Font = Enum.Font.Gotham
local AimCorner = Instance.new("UICorner", AimPartBtn)
AimCorner.CornerRadius = UDim.new(0,6)
AimPartBtn.MouseButton1Click:Connect(function()
    Config.Aimbot.AimPart = Config.Aimbot.AimPart == "Head" and "UpperTorso" or "Head"
    AimPartBtn.Text = Config.Aimbot.AimPart == "Head" and "鎖頭" or "鎖身"
end)

CreatePlusMinusAdjuster(MainFrame, "自瞄平滑", Config.Aimbot.Smooth, 0.05, true, 0.05, 1.0, 230, 145, function(val) Config.Aimbot.Smooth = val end)
CreatePlusMinusAdjuster(MainFrame, "FOV大小", Config.Aimbot.FOV, 10, false, 20, 360, 390, 145, function(val) Config.Aimbot.FOV = val end)
CreateSliderToggle(MainFrame, "自動跳", false, 10, 180, ToggleAutoJump)
CreateSliderToggle(MainFrame, "第一人稱FOV", false, 120, 180, ToggleFirstPersonFOV)
CreateSliderToggle(MainFrame, "穿牆/飛天", false, 230, 180, ToggleNoclipFly)
CreateSliderToggle(MainFrame, "自動旋轉", false, 340, 180, ToggleAutoRotate)
CreatePlusMinusAdjuster(MainFrame, "旋轉速度", Config.AutoRotate.RotateSpeed, 100, false, 300, 3600, 450, 180, function(val)
    Config.AutoRotate.RotateSpeed = val
    if Config.AutoRotate.Enabled and LocalCharacter then SetupAutoRotate(LocalCharacter) end
end)

-- 自動發消息控件
local Separator = Instance.new("Frame", MainFrame)
Separator.Size = UDim2.new(0, 680, 0, 1)
Separator.Position = UDim2.new(0, 10, 0, 210)
Separator.BackgroundColor3 = Color3.fromRGB(100,100,100)

local MsgInput = Instance.new("TextBox", MainFrame)
MsgInput.Size = UDim2.new(0, 400, 0, 25)
MsgInput.Position = UDim2.new(0, 10, 0, 220)
MsgInput.BackgroundColor3 = Color3.fromRGB(50,50,50)
MsgInput.TextColor3 = Color3.fromRGB(255,255,255)
MsgInput.PlaceholderText = "輸入要自動發送的內容..."
MsgInput.Text = "自動發送測試消息"
MsgInput.ClearTextOnFocus = false
MsgInput.Font = Enum.Font.Gotham
MsgInput.TextSize = 14
local InputCorner = Instance.new("UICorner", MsgInput)
InputCorner.CornerRadius = UDim.new(0,4)

local IntervalLabel = Instance.new("TextLabel", MainFrame)
IntervalLabel.Size = UDim2.new(0, 80, 0, 25)
IntervalLabel.Position = UDim2.new(0, 420, 0, 220)
IntervalLabel.BackgroundColor3 = Color3.fromRGB(40,40,40)
IntervalLabel.Text = "間隔: " .. Config.AutoMsg.SendInterval .. "s"
IntervalLabel.TextColor3 = Color3.fromRGB(0,200,255)
IntervalLabel.TextSize = 12
IntervalLabel.Font = Enum.Font.GothamBold
IntervalLabel.TextXAlignment = Enum.TextXAlignment.Center
local LabelCorner = Instance.new("UICorner", IntervalLabel)
LabelCorner.CornerRadius = UDim.new(0,4)

local MinusBtn = Instance.new("TextButton", MainFrame)
MinusBtn.Size = UDim2.new(0, 30, 0, 25)
MinusBtn.Position = UDim2.new(0, 510, 0, 220)
MinusBtn.BackgroundColor3 = Color3.fromRGB(150,0,0)
MinusBtn.Text = "-"
MinusBtn.TextColor3 = Color3.new(1,1,1)
MinusBtn.TextSize = 16
MinusBtn.Font = Enum.Font.GothamBold
local MinusCorner = Instance.new("UICorner", MinusBtn)
MinusCorner.CornerRadius = UDim.new(0,4)

local PlusBtn = Instance.new("TextButton", MainFrame)
PlusBtn.Size = UDim2.new(0, 30, 0, 25)
PlusBtn.Position = UDim2.new(0, 550, 0, 220)
PlusBtn.BackgroundColor3 = Color3.fromRGB(0,150,0)
PlusBtn.Text = "+"
PlusBtn.TextColor3 = Color3.new(1,1,1)
PlusBtn.TextSize = 16
PlusBtn.Font = Enum.Font.GothamBold
local PlusCorner = Instance.new("UICorner", PlusBtn)
PlusCorner.CornerRadius = UDim.new(0,4)

local ToggleMsgBtn = Instance.new("TextButton", MainFrame)
ToggleMsgBtn.Size = UDim2.new(0, 120, 0, 25)
ToggleMsgBtn.Position = UDim2.new(0, 590, 0, 220)
ToggleMsgBtn.BackgroundColor3 = Color3.fromRGB(200,0,0)
ToggleMsgBtn.Text = "開啟自動發送"
ToggleMsgBtn.TextColor3 = Color3.new(1,1,1)
ToggleMsgBtn.TextSize = 12
ToggleMsgBtn.Font = Enum.Font.Gotham
local ToggleMsgCorner = Instance.new("UICorner", ToggleMsgBtn)
ToggleMsgCorner.CornerRadius = UDim.new(0,4)

local function UpdateIntervalLabel()
    IntervalLabel.Text = "間隔: " .. string.format("%.1f", Config.AutoMsg.SendInterval) .. "s"
end

MinusBtn.MouseButton1Click:Connect(function()
    if Config.AutoMsg.SendInterval - Config.AutoMsg.IntervalStep >= Config.AutoMsg.MinInterval then
        Config.AutoMsg.SendInterval -= Config.AutoMsg.IntervalStep
        UpdateIntervalLabel()
    end
end)

PlusBtn.MouseButton1Click:Connect(function()
    if Config.AutoMsg.SendInterval + Config.AutoMsg.IntervalStep <= Config.AutoMsg.MaxInterval then
        Config.AutoMsg.SendInterval += Config.AutoMsg.IntervalStep
        UpdateIntervalLabel()
    end
end)

ToggleMsgBtn.MouseButton1Click:Connect(function()
    Config.AutoMsg.IsEnabled = not Config.AutoMsg.IsEnabled
    if Config.AutoMsg.IsEnabled then
        ToggleMsgBtn.BackgroundColor3 = Color3.fromRGB(0,180,0)
        ToggleMsgBtn.Text = "關閉自動發送"
        task.spawn(AutoMsgLoop, MsgInput)
    else
        ToggleMsgBtn.BackgroundColor3 = Color3.fromRGB(200,0,0)
        ToggleMsgBtn.Text = "開啟自動發送"
    end
end)

-- 懸浮按鈕切換面板
FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ================ 主循環與事件監聽 ================
RunService.Heartbeat:Connect(function()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= lp then
            if not Drawings[plr] and Config.ESP.Enabled then CreateESP(plr) end
            pcall(function() UpdateESP(plr) end)
        end
    end
end)

RunService.RenderStepped:Connect(function()
    RefreshFOVCircle()
    if not Config.Aimbot.Enabled then return end
    local targetPart = FindBestTarget()
    if targetPart then
        local targetCF = CFrame.lookAt(Camera.CFrame.Position, targetPart.Position)
        Camera.CFrame = Camera.CFrame:Lerp(targetCF, Config.Aimbot.Smooth)
    end
end)

Players.PlayerRemoving:Connect(Cleanup)
lp.CharacterRemoving:Connect(function()
    Cleanup()
    LocalCharacter = nil
    LocalRoot = nil
    LocalHumanoid = nil
end)

lp.CharacterAdded:Connect(function(char)
    LocalCharacter = char
    LocalRoot = char:WaitForChild("HumanoidRootPart")
    LocalHumanoid = char:WaitForChild("Humanoid")
    if Config.Move.Enabled then ToggleNoclipFly(true) end
    if Config.AutoJump.Enabled then ToggleAutoJump(true) end
    if Config.FirstPersonFOV.Enabled then ToggleFirstPersonFOV(true) end
    if Config.AutoRotate.Enabled then SetupAutoRotate(char) end
end)

uis.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.F12 then
        Cleanup()
        pcall(function() FOVCircle:Remove() end)
        ScreenGui:Destroy()
        print("腳本已安全卸載")
    end
end)

Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        if Config.ESP.Enabled then CreateESP(plr) end
    end)
end)