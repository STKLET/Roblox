-- 手機/PC 通用 Roblox 飛天+ESP+自瞄 優化穩定版
-- 核心功能：可被自瞄→紅色射線/骨骼；不可被自瞄→綠色射線/骨骼 | 已移除長按自瞄
-- 新增功能：自動跳(落地即跳) + 第一人稱FOV視距開關(默認200) + 穿牆=飛天雙開 | 修復飛天視角跟隨 + 角色自動360旋轉開關
local args = _E and _E.ARGS or {}
local uis = game:GetService("UserInputService")
local lp = game.Players.LocalPlayer
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local Players = game.Players

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
        -- 射線/骨骼顏色（可被自瞄=紅，不可=綠）
        TracerAimableColor = Color3.fromRGB(255, 0, 0),
        TracerUnaimableColor = Color3.fromRGB(0, 255, 0),
        SkeletonAimableColor = Color3.fromRGB(255, 0, 0),
        SkeletonUnaimableColor = Color3.fromRGB(0, 255, 0),
        -- 其他樣式
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
    -- 自瞄設置（已移除HoldMode相關配置）
    Aimbot = {
        Enabled = false,
        AimPart = "Head",
        Smooth = 0.9,
        FOV = 350,
        TargetCacheTime = 0.2,
        LastTarget = nil,
        LastTargetTime = 0
    },
    -- 移動設置（穿牆=飛天 雙開）
    Move = {
        Speed = 127,
        Enabled = false -- 控制穿牆+飛天雙開關
    },
    -- 新增功能配置
    AutoJump = {
        Enabled = false,
        Connection = nil -- 存儲事件連接，用於關閉
    },
    FirstPersonFOV = {
        Enabled = false,
        DefaultValue = 200,
        OriginalFOV = Camera.FieldOfView
    },
    Noclip = {
        Connection = nil -- 穿牆碰撞事件連接
    },
    -- 新增：自動旋轉配置
    AutoRotate = {
        Enabled = false,
        RotateSpeed = 1800, -- 旋轉速度，可在GUI調節
        RotateConnection = nil -- 旋轉事件連接
    }
}

-- ================ 全局變量 ================
local Drawings = {}
local Highlights = {}
-- FOV圈（保持空心）
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
-- 飛天變量
local FlyGyro = nil
-- 穿牆移動相關
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
    -- 清理飛天相關
    if FlyGyro then FlyGyro:Destroy() end
    FlyGyro = nil
    -- 清理穿牆相關
    if Config.Noclip.Connection then
        Config.Noclip.Connection:Disconnect()
        Config.Noclip.Connection = nil
    end
    if NoclipMoveConn then
        NoclipMoveConn:Disconnect()
        NoclipMoveConn = nil
    end
    -- 清理自動跳相關
    if Config.AutoJump.Connection then
        Config.AutoJump.Connection:Disconnect()
        Config.AutoJump.Connection = nil
    end
    -- 恢復原始FOV
    if Config.FirstPersonFOV.Enabled then
        Camera.FieldOfView = Config.FirstPersonFOV.OriginalFOV
        Config.FirstPersonFOV.Enabled = false
    end
    -- 新增：清理自動旋轉
    if Config.AutoRotate.RotateConnection then
        Config.AutoRotate.RotateConnection:Disconnect()
        Config.AutoRotate.RotateConnection = nil
    end
end

-- 判斷敵人是否可被自瞄（基於自瞄邏輯）
local function IsPlayerAimable(plr)
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return false end
    -- 核心修復：這裡的TeamCheck判斷要和自瞄一致，避免ESP和自瞄判定脫節
    if Config.ESP.TeamCheck and plr.Team == lp.Team then return false end

    -- 1. 視野內檢測
    local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
    if not onScreen then return false end

    -- 2. FOV範圍檢測
    local centerPos = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local fovDist = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
    if fovDist > Config.Aimbot.FOV then return false end

    -- 3. 距離檢測
    local realDist = (LocalRoot.Position - root.Position).Magnitude
    if realDist > Config.ESP.MaxDistance then return false end

    -- 4. 掩體檢測
    local targetPart = char:FindFirstChild(Config.Aimbot.AimPart) or root
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalCharacter, char}
    rayParams.IgnoreWater = true
    local hitResult = workspace:Raycast(Camera.CFrame.Position, (targetPart.Position - Camera.CFrame.Position), rayParams)
    return hitResult == nil -- 無掩體=可被自瞄
end

-- ================ 新增功能實現 ================
-- 1. 自動跳（落地即跳，修復開關失效）
local function ToggleAutoJump(state)
    Config.AutoJump.Enabled = state
    -- 先斷開舊的事件連接
    if Config.AutoJump.Connection then
        Config.AutoJump.Connection:Disconnect()
        Config.AutoJump.Connection = nil
    end
    if state then
        -- 開啟時立即檢查是否在地面，在地面就跳一次
        if LocalHumanoid.FloorMaterial ~= Enum.Material.Air then
            LocalHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        -- 綁定地板檢測事件
        Config.AutoJump.Connection = LocalHumanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
            if LocalHumanoid.FloorMaterial ~= Enum.Material.Air then
                LocalHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
end

-- 2. 第一人稱FOV視距開關（修復無效問題，強制設置200）
local function ToggleFirstPersonFOV(state)
    Config.FirstPersonFOV.Enabled = state
    if state then
        Config.FirstPersonFOV.OriginalFOV = Camera.FieldOfView
        -- 強制設置FOV為200，確保生效
        Camera.FieldOfView = Config.FirstPersonFOV.DefaultValue
        -- 防止遊戲自動覆蓋，增加循環檢測
        if NoclipMoveConn then
            NoclipMoveConn:Disconnect()
            NoclipMoveConn = nil
        end
        NoclipMoveConn = RunService.RenderStepped:Connect(function()
            if Config.FirstPersonFOV.Enabled then
                Camera.FieldOfView = Config.FirstPersonFOV.DefaultValue
            end
        end)
    else
        Camera.FieldOfView = Config.FirstPersonFOV.OriginalFOV
        if NoclipMoveConn then
            NoclipMoveConn:Disconnect()
            NoclipMoveConn = nil
        end
    end
end

-- 3. 穿牆+飛天 雙開關（移除獨立飛天開關）
local function InitFly()
    -- 創建BodyGyro用於視角跟隨
    FlyGyro = Instance.new("BodyGyro")
    FlyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    FlyGyro.P = 5000
    FlyGyro.Parent = LocalRoot
end

local function ToggleNoclipFly(state)
    Config.Move.Enabled = state
    -- 先斷開舊的事件連接
    if Config.Noclip.Connection then
        Config.Noclip.Connection:Disconnect()
        Config.Noclip.Connection = nil
    end
    if NoclipMoveConn then
        NoclipMoveConn:Disconnect()
        NoclipMoveConn = nil
    end
    -- 清理舊飛天
    if FlyGyro then FlyGyro:Destroy() end
    FlyGyro = nil

    if state then
        -- 開啟穿牆：關閉碰撞
        Config.Noclip.Connection = RunService.Heartbeat:Connect(function()
            if not LocalCharacter then return end
            for _, part in pairs(LocalCharacter:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end)
        -- 開啟飛天：視角跟隨移動
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
        -- 關閉穿牆：恢復碰撞
        if LocalCharacter then
            for _, part in pairs(LocalCharacter:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
        -- 關閉飛天：清空速度
        if LocalRoot then
            LocalRoot.Velocity = Vector3.new(0, 0, 0)
        end
    end
end

-- 新增：4. 自動旋轉開關（支持死亡復活）
local function SetupAutoRotate(character)
    local hrp = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.AutoRotate = false
    Camera.CameraType = Enum.CameraType.Track

    -- 斷開舊連接避免重複
    if Config.AutoRotate.RotateConnection then
        Config.AutoRotate.RotateConnection:Disconnect()
    end

    if Config.AutoRotate.Enabled then
        Config.AutoRotate.RotateConnection = RunService.RenderStepped:Connect(function(deltaTime)
            local rotateAngle = math.rad(Config.AutoRotate.RotateSpeed * deltaTime)
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, rotateAngle, 0)
        end)
    end
end

local function ToggleAutoRotate(state)
    Config.AutoRotate.Enabled = state
    -- 當前角色生效
    if LocalCharacter then
        SetupAutoRotate(LocalCharacter)
    end
    -- 重生後自動生效
    lp.CharacterAdded:Connect(SetupAutoRotate)
end

-- ================ ESP功能實現 ================
local function CreateESP(plr)
    if plr == lp or Drawings[plr] then return end
    local comp = {
        Box = Drawing.new("Square"),
        Tracer = Drawing.new("Line"),
        NameLabel = Drawing.new("Text"),
        DistanceLabel = Drawing.new("Text"),
        HealthBar = {
            Outline = Drawing.new("Square"),
            Fill = Drawing.new("Square")
        },
        ToolLabel = Drawing.new("Text"),
        Skeleton = {}
    }
    -- 初始化樣式
    comp.Box.Filled = true
    comp.Box.Transparency = Config.ESP.BoxTransparency
    comp.Box.Color = Config.ESP.BoxColor
    comp.Tracer.Thickness = 1
    comp.Tracer.Transparency = 0.5
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
    -- 高亮元件 - 修復：創建時直接綁定Parent到角色
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
    -- 隊友過濾
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

    -- 核心：判斷是否可被自瞄
    local isAimable = IsPlayerAimable(plr)

    -- 基礎計算
    local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)
    local distance = math.floor((LocalRoot.Position - root.Position).Magnitude)
    local healthPercent = hum.Health / hum.MaxHealth
    -- 方框大小
    local topPos = Camera:WorldToViewportPoint((root.CFrame + Vector3.new(0, 3, 0)).Position)
    local bottomPos = Camera:WorldToViewportPoint((root.CFrame - Vector3.new(0, 1, 0)).Position)
    local boxHeight = math.abs(topPos.Y - bottomPos.Y)
    local boxWidth = boxHeight / 2.5
    local boxX = rootPos.X - boxWidth / 2
    local boxY = rootPos.Y - boxHeight / 2

    -- 1. 方框
    comp.Box.Visible = Config.ESP.ShowBox and onScreen
    if comp.Box.Visible then
        comp.Box.Size = Vector2.new(boxWidth, boxHeight)
        comp.Box.Position = Vector2.new(boxX, boxY)
        comp.Box.Color = Config.ESP.BoxColor
        comp.Box.Transparency = Config.ESP.BoxTransparency
    end

    -- 2. 血條
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

    -- 3. 名稱/距離/武器
    local nameY = boxY - 20
    comp.NameLabel.Visible = Config.ESP.ShowName and onScreen
    if comp.NameLabel.Visible then
        comp.NameLabel.Text = "[" .. plr.Name .. "]"
        comp.NameLabel.Position = Vector2.new(rootPos.X, nameY)
    end
    local distanceY = boxY + boxHeight + 5
    local toolY = distanceY + 18
    comp.DistanceLabel.Visible = Config.ESP.ShowDistance and onScreen
    if comp.DistanceLabel.Visible then
        comp.DistanceLabel.Text = "距離: " .. distance .. "M"
        comp.DistanceLabel.Position = Vector2.new(rootPos.X, distanceY)
    end
    comp.ToolLabel.Visible = Config.ESP.ShowTool and onScreen
    if comp.ToolLabel.Visible then
        local tool = plr.Backpack:FindFirstChildOfClass("Tool") or char:FindFirstChildOfClass("Tool")
        comp.ToolLabel.Text = tool and "武器: " .. tool.Name or "無武器"
        comp.ToolLabel.Position = Vector2.new(rootPos.X, toolY)
    end

    -- 核心：4. 射線顏色切換
    comp.Tracer.Visible = Config.ESP.ShowTracer and onScreen
    if comp.Tracer.Visible then
        comp.Tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
        comp.Tracer.To = Vector2.new(rootPos.X, rootPos.Y)
        comp.Tracer.Color = isAimable and Config.ESP.TracerAimableColor or Config.ESP.TracerUnaimableColor
    end

    -- 核心：5. 骨骼顏色切換 - 完全還原原始R15/R6骨骼連接邏輯
    local SkeletonConnections = {
        R15 = {{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"LowerTorso","LeftUpperLeg"},{"LowerTorso","RightUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},{"UpperTorso","LeftUpperArm"},{"UpperTorso","RightUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"}},
        R6 = {{"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"}}
    }
    local conns = SkeletonConnections[hum.RigType.Name] or {}
    -- 先清除舊的骨骼線條避免殘留
    for _, line in pairs(comp.Skeleton) do
        line.Visible = false
    end
    if Config.ESP.ShowSkeleton and onScreen then
        for _, conn in ipairs(conns) do
            local a = char:FindFirstChild(conn[1])
            local b = char:FindFirstChild(conn[2])
            local lineKey = conn[1] .. "-" .. conn[2]
            local line = comp.Skeleton[lineKey]
            if not line then
                line = Drawing.new("Line")
                line.Thickness = 1
                line.ZIndex = 5 -- 提高層級防止被遮擋
                comp.Skeleton[lineKey] = line
            end
            if a and b then
                local aPos = Camera:WorldToViewportPoint(a.Position)
                local bPos = Camera:WorldToViewportPoint(b.Position)
                line.From = Vector2.new(aPos.X, aPos.Y)
                line.To = Vector2.new(bPos.X, bPos.Y)
                line.Visible = true
                -- 骨骼顏色跟隨可瞄準狀態
                line.Color = isAimable and Config.ESP.SkeletonAimableColor or Config.ESP.SkeletonUnaimableColor
            else
                line.Visible = false
            end
        end
    else
        for _, line in pairs(comp.Skeleton) do line.Visible = false end
    end

    -- 6. 高亮 - 修復：無需重複設置Parent，直接控制Enabled
    if Highlights[plr] then
        Highlights[plr].Enabled = Config.ESP.ChamsEnabled and onScreen
    end
end

-- ================ 自瞄核心 - 關鍵修復 ================
local function FindBestTarget()
    local closestPart = nil
    local closestDist = math.huge
    local centerPos = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    -- 核心修復1：優先檢查緩存目標時，額外增加隊友過濾
    if Config.Aimbot.LastTarget and Config.Aimbot.LastTarget.Parent then
        local targetPlr = Players:GetPlayerFromCharacter(Config.Aimbot.LastTarget.Parent)
        -- 新增：如果開啟隊友隱藏且目標是隊友，直接清除緩存
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
    -- 遍歷玩家尋找目標
    for _, plr in pairs(Players:GetPlayers()) do
        if plr == lp then continue end
        -- 核心修復2：遍歷時優先過濾隊友，和ESP邏輯保持一致
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

-- ================ GUI創建工具函數 ================
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
        -- 核心修復3：切換隊友隱藏時，立即清除自瞄緩存目標
        if text == "隊友隱藏" then
            Config.Aimbot.LastTarget = nil
        end
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
    return adjustFrame
end

-- ================ 創建GUI ================
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
MainFrame.Size = UDim2.new(0,700,0,330) -- 加高面板容納新控件
MainFrame.Position = UDim2.new(0.5,-350,1,-350) -- 對應調整位置
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
Title.Text = "Roblox 全能輔助面板（最終優化版）"
Title.TextColor3 = Color3.new(1,1,1)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.Position = UDim2.new(0,0,0,5)
Title.TextXAlignment = Enum.TextXAlignment.Center

-- 移動速度調節（控制穿牆+飛天速度）
CreatePlusMinusAdjuster(MainFrame, "移動速度", Config.Move.Speed, 10, false, 120, 500, 10, 40, function(val)
    Config.Move.Speed = val
end)

-- ESP開關
CreateSliderToggle(MainFrame, "ESP總開啟", false, 10, 75, function(v)
    Config.ESP.Enabled = v
    if v then
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= lp then CreateESP(plr) end
        end
    else
        Cleanup()
    end
end)
CreateSliderToggle(MainFrame, "方框", true, 120, 75, function(v) Config.ESP.ShowBox = v end)
CreateSliderToggle(MainFrame, "射線", true, 230, 75, function(v) Config.ESP.ShowTracer = v end)
CreateSliderToggle(MainFrame, "骨骼", true, 340, 75, function(v) Config.ESP.ShowSkeleton = v end)
CreateSliderToggle(MainFrame, "高亮", false, 450, 75, function(v) Config.ESP.ChamsEnabled = v end)
CreateSliderToggle(MainFrame, "血條", true, 560, 75, function(v) Config.ESP.ShowHealth = v end)

-- ESP細項
CreateSliderToggle(MainFrame, "名稱", true, 10, 110, function(v) Config.ESP.ShowName = v end)
CreateSliderToggle(MainFrame, "距離", true, 155, 110, function(v) Config.ESP.ShowDistance = v end)
CreateSliderToggle(MainFrame, "武器", true, 300, 110, function(v) Config.ESP.ShowTool = v end)
CreateSliderToggle(MainFrame, "隊友隱藏", false, 445, 110, function(v)
    Config.ESP.TeamCheck = v
    -- 額外保險：切換隊友隱藏時再次清除緩存
    Config.Aimbot.LastTarget = nil
end)
CreateSliderToggle(MainFrame, "顯示FOV", true, 590, 110, function(v)
    Config.ESP.ShowFOV = v
    RefreshFOVCircle()
end)

-- 自瞄控制
CreateSliderToggle(MainFrame, "自瞄總開啟", false, 10, 145, function(v)
    Config.Aimbot.Enabled = v
    RefreshFOVCircle()
end)
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
CreatePlusMinusAdjuster(MainFrame, "自瞄平滑", Config.Aimbot.Smooth, 0.05, true, 0.05, 1.0, 230, 145, function(val)
    Config.Aimbot.Smooth = val
end)
CreatePlusMinusAdjuster(MainFrame, "FOV大小", Config.Aimbot.FOV, 10, false, 20, 360, 390, 145, function(val)
    Config.Aimbot.FOV = val
    RefreshFOVCircle()
end)

-- 新增功能開關（自動跳+第一人稱FOV+穿牆飛天雙開）
CreateSliderToggle(MainFrame, "自動跳", false, 10, 180, ToggleAutoJump)
CreateSliderToggle(MainFrame, "第一人稱FOV", false, 120, 180, ToggleFirstPersonFOV)
CreateSliderToggle(MainFrame, "穿牆+飛天", false, 230, 180, ToggleNoclipFly)

-- 新增：自動旋轉開關 + 速度調節
CreateSliderToggle(MainFrame, "自動旋轉", false, 340, 180, ToggleAutoRotate)
CreatePlusMinusAdjuster(MainFrame, "旋轉速度", Config.AutoRotate.RotateSpeed, 100, false, 300, 3600, 450, 180, function(val)
    Config.AutoRotate.RotateSpeed = val
    -- 實時更新速度
    if Config.AutoRotate.Enabled and LocalCharacter then
        SetupAutoRotate(LocalCharacter)
    end
end)

-- 懸浮按鈕切換面板
FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ================ 主循環 ================
RunService.Heartbeat:Connect(function()
    -- ESP更新
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= lp then
            if not Drawings[plr] and Config.ESP.Enabled then CreateESP(plr) end
            pcall(function() UpdateESP(plr) end)
        end
    end
end)

RunService.RenderStepped:Connect(function()
    RefreshFOVCircle()
    -- 自瞄邏輯
    if not Config.Aimbot.Enabled then return end
    local targetPart = FindBestTarget()
    if targetPart then
        local targetCF = CFrame.lookAt(Camera.CFrame.Position, targetPart.Position)
        Camera.CFrame = Camera.CFrame:Lerp(targetCF, Config.Aimbot.Smooth)
    end
end)

-- ================ 事件監聽 ================
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
    -- 角色重生後恢復各功能狀態
    if Config.Move.Enabled then
        ToggleNoclipFly(true)
    end
    if Config.AutoJump.Enabled then
        ToggleAutoJump(true)
    end
    if Config.FirstPersonFOV.Enabled then
        ToggleFirstPersonFOV(true)
    end
    -- 新增：重生後恢復自動旋轉
    if Config.AutoRotate.Enabled then
        SetupAutoRotate(char)
    end
end)
-- 卸載腳本
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

print("全能輔助面板載入成功！按F12卸載 | 點擊懸浮按鈕打開面板 | 新增自動旋轉功能 | 修復自瞄鎖隊友bug")