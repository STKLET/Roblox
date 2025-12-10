-- 手機/PC 通用 飛天+ESP+自瞄 終極修復版
-- 修復：自瞄速度顯示2位小數 + 死亡復活FOV圈穩定 + 全功能對齊
local args = _E and _E.ARGS or {}
local uis = game:GetService("UserInputService")
local lp = game.Players.LocalPlayer
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")

-- ================ 飛天變量 ================
local SPEED = args[1] or 127
local MAX_TORQUE_RP = args[3] or 1e4
local MAX_THRUST = args[5] or 5e5
local MAX_TORQUE_BG = args[6] or 3e4

local fly_enabled = false
local anchor_enabled = false
local up_flag = false
local down_flag = false
local parent, humanoid
local fly_bg, fly_rp, fly_pt, flyModel

-- ================ ESP+自瞄 設定表（終極版）============
local ESP_Settings = {
    Enabled = false,
    TeamCheck = false,
    ShowTeam = false,

    -- 獨立繪製開關
    ShowBox = true,
    ShowHealth = true,
    ShowTracer = true,
    ShowSkeleton = true,
    ShowTool = true,
    ShowName = true,
    ShowDistance = true,
    ChamsEnabled = false,
    MaxDistance = 1000,

    -- 配色
    BoxColor = Color3.fromRGB(255,255,255),
    BoxTransparency = 0.5,
    TracerColor = Color3.fromRGB(128,0,255),
    SkeletonColor = Color3.fromRGB(0,255,0),
    ChamsFillColor = Color3.fromRGB(255,0,0),
    ChamsTransparency = 0.5,

    -- 自瞄核心設定
    AimbotEnabled = false,
    AimPart = "Head",
    Smooth = 0.40,
    UseFOV = true,
    FOV = 80,
    FOVColor = Color3.fromRGB(255,0,0),
    HoldMode = false,
}

-- ================ ESP繪製物件 ================
local Drawings = {}
local Highlights = {}
-- FOV圓圈全局實例，避免復活後被銷毀
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 2
FOVCircle.NumSides = 80
FOVCircle.Filled = false
FOVCircle.Color = ESP_Settings.FOVColor
FOVCircle.Radius = ESP_Settings.FOV
FOVCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
FOVCircle.Visible = ESP_Settings.AimbotEnabled and ESP_Settings.UseFOV

-- 骨骼連接表
local SkeletonConnections = {
    R15 = {
        {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
        {"LowerTorso","LeftUpperLeg"},{"LowerTorso","RightUpperLeg"},
        {"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
        {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
        {"UpperTorso","LeftUpperArm"},{"UpperTorso","RightUpperArm"},
        {"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
        {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"}
    },
    R6 = {
        {"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},
        {"Torso","Left Leg"},{"Torso","Right Leg"}
    }
}

-- 本地角色更新 + 復活監聽
local LocalCharacter = lp.Character or lp.CharacterAdded:Wait()
local LocalRoot = LocalCharacter:WaitForChild("HumanoidRootPart")
lp.CharacterAdded:Connect(function(c)
    LocalCharacter = c
    LocalRoot = c:WaitForChild("HumanoidRootPart")
    -- 角色復活後立即重建飛天對象（如果開啟）
    task.wait(0.5)
    if fly_enabled then
        initFly()
    end
    -- 角色復活後強制刷新FOV圓圈屬性
    RefreshFOVCircle()
end)

-- ================ FOV圓圈強制刷新函數（核心修復）============
local function RefreshFOVCircle()
    FOVCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    FOVCircle.Radius = ESP_Settings.FOV
    FOVCircle.Color = ESP_Settings.FOVColor
    FOVCircle.Visible = ESP_Settings.AimbotEnabled and ESP_Settings.UseFOV
end

-- ================ 清理舊物件 ================
local function Cleanup()
    -- 清理飛天物件
    if fly_bg then pcall(function() fly_bg:Destroy() end) end
    if fly_rp then pcall(function() fly_rp:Destroy() end) end
    if fly_pt then pcall(function() fly_pt:Destroy() end) end
    if flyModel then pcall(function() flyModel:Destroy() end) end

    -- 清理ESP繪製物件（保留FOV圓圈）
    for plr, comp in pairs(Drawings) do
        if comp then
            pcall(function() comp.Box:Remove() end)
            pcall(function() comp.Tracer:Remove() end)
            pcall(function() comp.NameLabel:Remove() end)
            pcall(function() comp.DistanceLabel:Remove() end)
            pcall(function() comp.HealthBar.Outline:Remove() end)
            pcall(function() comp.HealthBar.Fill:Remove() end)
            pcall(function() comp.ToolLabel:Remove() end)
            for _, line in pairs(comp.Skeleton) do
                pcall(function() line:Remove() end)
            end
        end
    end
    for plr, hl in pairs(Highlights) do
        pcall(function() hl:Destroy() end)
    end
    Drawings = {}
    Highlights = {}
end

-- ================ 飛天核心函數 ================
local function createFlyTarget()
    flyModel = Instance.new("Model")
    flyModel.Name = "FlyTarget"
    flyModel.Parent = workspace
    fly_pt = Instance.new("Part")
    fly_pt.Size = Vector3.new(0.1,0.1,0.1)
    fly_pt.Transparency = 1
    fly_pt.Anchored = true
    fly_pt.CanCollide = false
    fly_pt.Parent = flyModel
end

local function initFly()
    local ch = lp.Character or lp.CharacterAdded:Wait()
    parent = ch:WaitForChild("HumanoidRootPart")
    humanoid = ch:FindFirstChild("Humanoid")

    if fly_bg then fly_bg:Destroy() end
    if fly_rp then fly_rp:Destroy() end
    if flyModel then flyModel:Destroy() end

    createFlyTarget()

    fly_bg = Instance.new("BodyGyro", parent)
    fly_bg.P = 30000
    fly_bg.MaxTorque = Vector3.new(0,0,0)

    fly_rp = Instance.new("RocketPropulsion", parent)
    fly_rp.MaxSpeed = SPEED
    fly_rp.MaxThrust = MAX_THRUST
    fly_rp.ThrustP = 100000
    fly_rp.TurnP = 100000
    fly_rp.Target = fly_pt
    fly_rp.CartoonFactor = 1
end

-- ================ ESP核心函數 ================
local function CreateESP(plr)
    if plr == lp or Drawings[plr] then return end

    local comp = {
        Box = Drawing.new("Square"),
        Tracer = Drawing.new("Line"),
        NameLabel = Drawing.new("Text"),
        DistanceLabel = Drawing.new("Text"),
        HealthBar = {Outline = Drawing.new("Square"), Fill = Drawing.new("Square")},
        ToolLabel = Drawing.new("Text"),
        Skeleton = {}
    }

    -- 應用配色設定
    comp.Box.Thickness = 1; comp.Box.Filled = true; comp.Box.Transparency = ESP_Settings.BoxTransparency
    comp.Box.Color = ESP_Settings.BoxColor
    comp.Tracer.Thickness = 1; comp.Tracer.Transparency = 1; comp.Tracer.Color = ESP_Settings.TracerColor
    comp.NameLabel.Size = 18; comp.NameLabel.Center = true; comp.NameLabel.Outline = true; comp.NameLabel.Color = Color3.fromRGB(255,255,255)
    comp.DistanceLabel.Size = 18; comp.DistanceLabel.Center = true; comp.DistanceLabel.Outline = true; comp.DistanceLabel.Color = Color3.fromRGB(173,216,230)
    comp.ToolLabel.Size = 18; comp.ToolLabel.Center = true; comp.ToolLabel.Outline = true; comp.ToolLabel.Color = Color3.fromRGB(255,255,255)
    comp.HealthBar.Outline.Thickness = 1; comp.HealthBar.Outline.Filled = false
    comp.HealthBar.Fill.Thickness = 1; comp.HealthBar.Fill.Filled = true

    local hl = Instance.new("Highlight")
    hl.FillColor = ESP_Settings.ChamsFillColor
    hl.OutlineColor = Color3.fromRGB(255,255,255)
    hl.FillTransparency = ESP_Settings.ChamsTransparency
    hl.OutlineTransparency = 0
    hl.Enabled = false
    Highlights[plr] = hl

    Drawings[plr] = comp
end

local function UpdateESP(plr)
    local comp = Drawings[plr]
    if not comp then return end

    if not ESP_Settings.Enabled or not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") or not plr.Character:FindFirstChild("Humanoid") or plr.Character.Humanoid.Health <= 0 then
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

    local char = plr.Character
    local root = char.HumanoidRootPart
    local hum = char.Humanoid
    local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)
    local distance = (LocalRoot.Position - root.Position).Magnitude

    if ESP_Settings.TeamCheck and plr.Team == lp.Team and not ESP_Settings.ShowTeam then
        comp.Box.Visible = false; comp.Tracer.Visible = false; comp.NameLabel.Visible = false
        comp.DistanceLabel.Visible = false; comp.HealthBar.Outline.Visible = false; comp.HealthBar.Fill.Visible = false
        comp.ToolLabel.Visible = false; for _, line in pairs(comp.Skeleton) do line.Visible = false end
        if Highlights[plr] then Highlights[plr].Enabled = false end
        return
    end

    if not onScreen or distance > ESP_Settings.MaxDistance then
        comp.Box.Visible = false; comp.Tracer.Visible = false; comp.NameLabel.Visible = false
        comp.DistanceLabel.Visible = false; comp.HealthBar.Outline.Visible = false; comp.HealthBar.Fill.Visible = false
        comp.ToolLabel.Visible = false; for _, line in pairs(comp.Skeleton) do line.Visible = false end
        if Highlights[plr] then Highlights[plr].Enabled = false end
        return
    end

    -- 計算方框大小
    local topPos = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
    local bottomPos = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
    local boxHeight = math.abs(topPos.Y - bottomPos.Y)
    local boxWidth = boxHeight / 2

    -- 獨立開關控制繪製
    comp.Box.Visible = ESP_Settings.ShowBox
    if comp.Box.Visible then
        comp.Box.Size = Vector2.new(boxWidth, boxHeight)
        comp.Box.Position = Vector2.new(rootPos.X - boxWidth/2, rootPos.Y - boxHeight/2)
    end

    comp.Tracer.Visible = ESP_Settings.ShowTracer
    if comp.Tracer.Visible then
        comp.Tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
        comp.Tracer.To = Vector2.new(rootPos.X, rootPos.Y + boxHeight/2)
    end

    comp.NameLabel.Visible = ESP_Settings.ShowName
    if comp.NameLabel.Visible then
        comp.NameLabel.Text = "[" .. plr.Name .. "]"
        comp.NameLabel.Position = Vector2.new(rootPos.X, rootPos.Y - boxHeight/2 - 15)
    end

    comp.DistanceLabel.Visible = ESP_Settings.ShowDistance
    if comp.DistanceLabel.Visible then
        comp.DistanceLabel.Text = "[" .. math.floor(distance) .. "M]"
        comp.DistanceLabel.Position = Vector2.new(rootPos.X, rootPos.Y + boxHeight/2 + 15)
    end

    comp.HealthBar.Outline.Visible = ESP_Settings.ShowHealth
    comp.HealthBar.Fill.Visible = ESP_Settings.ShowHealth
    if comp.HealthBar.Outline.Visible then
        local hbHeight = boxHeight
        local hbWidth = 5
        local hf = hum.Health / hum.MaxHealth
        comp.HealthBar.Outline.Size = Vector2.new(hbWidth, hbHeight)
        comp.HealthBar.Outline.Position = Vector2.new(comp.Box.Position.X - hbWidth - 2, comp.Box.Position.Y)
        comp.HealthBar.Fill.Size = Vector2.new(hbWidth - 2, hbHeight * hf)
        comp.HealthBar.Fill.Position = Vector2.new(comp.HealthBar.Outline.Position.X + 1, comp.HealthBar.Outline.Position.Y + hbHeight * (1 - hf))
        comp.HealthBar.Fill.Color = Color3.fromRGB(255 * (1 - hf), 255 * hf, 0)
    end

    comp.ToolLabel.Visible = ESP_Settings.ShowTool
    if comp.ToolLabel.Visible then
        local tool = plr.Backpack:FindFirstChildOfClass("Tool") or char:FindFirstChildOfClass("Tool")
        comp.ToolLabel.Text = tool and "[持有: " .. tool.Name .. "]" or "[持有: 無]"
        comp.ToolLabel.Position = Vector2.new(rootPos.X, rootPos.Y + boxHeight/2 + 35)
    end

    if ESP_Settings.ShowSkeleton then
        local conns = SkeletonConnections[hum.RigType.Name] or {}
        for i, c in ipairs(conns) do
            local a = char:FindFirstChild(c[1])
            local b = char:FindFirstChild(c[2])
            if a and b then
                local line = comp.Skeleton[c[1].."-"..c[2]] or Drawing.new("Line")
                local aPos, aOn = Camera:WorldToViewportPoint(a.Position)
                local bPos, bOn = Camera:WorldToViewportPoint(b.Position)
                if aOn and bOn then
                    line.From = Vector2.new(aPos.X, aPos.Y)
                    line.To = Vector2.new(bPos.X, bPos.Y)
                    line.Color = ESP_Settings.SkeletonColor
                    line.Thickness = 1
                    line.Transparency = 1
                    line.Visible = true
                else
                    line.Visible = false
                end
                comp.Skeleton[c[1].."-"..c[2]] = line
            end
        end
    else
        for _, line in pairs(comp.Skeleton) do line.Visible = false end
    end

    if ESP_Settings.ChamsEnabled then
        Highlights[plr].Parent = char
        Highlights[plr].FillColor = ESP_Settings.ChamsFillColor
        Highlights[plr].Enabled = true
    else
        Highlights[plr].Enabled = false
    end
end

local function RemoveESP(plr)
    local comp = Drawings[plr]
    if comp then
        pcall(function() comp.Box:Remove() end)
        pcall(function() comp.Tracer:Remove() end)
        pcall(function() comp.NameLabel:Remove() end)
        pcall(function() comp.DistanceLabel:Remove() end)
        pcall(function() comp.HealthBar.Outline:Remove() end)
        pcall(function() comp.HealthBar.Fill:Remove() end)
        pcall(function() comp.ToolLabel:Remove() end)
        for _, line in pairs(comp.Skeleton) do
            pcall(function() line:Remove() end)
        end
        Drawings[plr] = nil
    end
    if Highlights[plr] then
        pcall(function() hl:Destroy() end)
        Highlights[plr] = nil
    end
end

-- ================ 自瞄核心函數 ================
local Touching = false
uis.TouchStarted:Connect(function() Touching = true end)
uis.TouchEnded:Connect(function() Touching = false end)

-- ================ 統一滑塊開關（固定尺寸+對齊）============
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
    end)

    return toggleFrame
end

-- ================ 統一加減數值調節器（2位小數+FOV穩定）============
local function CreatePlusMinusAdjuster(parent, text, defaultValue, minVal, maxVal, step, isSmooth, posX, posY, callback)
    local currentVal = defaultValue
    local width, height = 150, 25

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
    -- 格式化：自瞄速度顯示2位小數，FOV顯示整數
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
        -- FOV數值變更時刷新
        if not isSmooth then
            RefreshFOVCircle()
        end
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

-- ================ 統一 GUI 構建（嚴格對齊）============
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UniversalUltimateFixedMenu"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game:GetService("CoreGui")

-- 懸浮球 (40x40)
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
FloatBtn.Draggable = true
local FloatCorner = Instance.new("UICorner", FloatBtn)
FloatCorner.CornerRadius = UDim.new(1,0)
local FloatStroke = Instance.new("UIStroke", FloatBtn)
FloatStroke.Color = Color3.fromRGB(100,100,100)
FloatStroke.Thickness = 1

-- 橫向主選單 (680x200) - 緊湊對齊版
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0,680,0,200)
MainFrame.Position = UDim2.new(0.5,-340,1,-225)
MainFrame.BackgroundColor3 = Color3.fromRGB(25,25,25)
MainFrame.Visible = false
MainFrame.Active = true
MainFrame.Draggable = true
local MainCorner = Instance.new("UICorner", MainFrame)
MainCorner.CornerRadius = UDim.new(0,8)
local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Color3.fromRGB(80,80,80)
MainStroke.Thickness = 1

-- 標題
local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1,0,0,30)
Title.BackgroundTransparency = 1
Title.Text = "ESP&Fly-by-BanBan"
Title.TextColor3 = Color3.new(1,1,1)
Title.TextScaled = true
Title.Font = Enum.Font.GothamBold
Title.Position = UDim2.new(0,0,0,5)

-- ================ 第一排：飛天功能（嚴格對齊）============
CreateSliderToggle(MainFrame, "飛天", false, 10, 40, function(v)
    fly_enabled = v
    if v then
        initFly()
    else
        if fly_bg then fly_bg.MaxTorque = Vector3.new() end
        if fly_rp then fly_rp.MaxTorque = Vector3.new() end
    end
end)

CreateSliderToggle(MainFrame, "錨定", false, 120, 40, function(v)
    anchor_enabled = v
end)

CreatePlusMinusAdjuster(MainFrame, "飛速", SPEED, 10, 500, 10, false, 230, 40, function(val)
    SPEED = val
    if fly_rp then fly_rp.MaxSpeed = SPEED end
end)

local UpBtn = Instance.new("TextButton", MainFrame)
UpBtn.Size = UDim2.new(0,40,0,25)
UpBtn.Position = UDim2.new(0,390,0,40)
UpBtn.BackgroundColor3 = Color3.fromRGB(0,150,255)
UpBtn.Text = "↑"
UpBtn.TextColor3 = Color3.new(1,1,1)
UpBtn.TextScaled = true
UpBtn.Font = Enum.Font.GothamBold
local UpCorner = Instance.new("UICorner", UpBtn)
UpCorner.CornerRadius = UDim.new(0,6)

local DownBtn = Instance.new("TextButton", MainFrame)
DownBtn.Size = UDim2.new(0,40,0,25)
DownBtn.Position = UDim2.new(0,440,0,40)
DownBtn.BackgroundColor3 = Color3.fromRGB(150,0,255)
DownBtn.Text = "↓"
DownBtn.TextColor3 = Color3.new(1,1,1)
DownBtn.TextScaled = true
DownBtn.Font = Enum.Font.GothamBold
local DownCorner = Instance.new("UICorner", DownBtn)
DownCorner.CornerRadius = UDim.new(0,6)

UpBtn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then up_flag = true end end)
UpBtn.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then up_flag = false end end)
DownBtn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then down_flag = true end end)
DownBtn.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then down_flag = false end end)

-- ================ 第二排：ESP開關（6個開關等距對齊）============
CreateSliderToggle(MainFrame, "ESP總開啟", false, 10, 75, function(v)
    ESP_Settings.Enabled = v
    if v then
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= lp then CreateESP(plr) end
        end
    else
        for plr in pairs(Drawings) do RemoveESP(plr) end
    end
end)

CreateSliderToggle(MainFrame, "方框", true, 120, 75, function(v) ESP_Settings.ShowBox = v end)
CreateSliderToggle(MainFrame, "射線", true, 230, 75, function(v) ESP_Settings.ShowTracer = v end)
CreateSliderToggle(MainFrame, "骨骼", true, 340, 75, function(v) ESP_Settings.ShowSkeleton = v end)
CreateSliderToggle(MainFrame, "高亮", false, 450, 75, function(v) ESP_Settings.ChamsEnabled = v end)
CreateSliderToggle(MainFrame, "血條", true, 560, 75, function(v) ESP_Settings.ShowHealth = v end)

-- ================ 第三排：繪製細項（5個開關等距對齊）============
CreateSliderToggle(MainFrame, "名稱", true, 10, 110, function(v) ESP_Settings.ShowName = v end)
CreateSliderToggle(MainFrame, "距離", true, 155, 110, function(v) ESP_Settings.ShowDistance = v end)
CreateSliderToggle(MainFrame, "手持", true, 300, 110, function(v) ESP_Settings.ShowTool = v end)
CreateSliderToggle(MainFrame, "隊友隱藏", false, 445, 110, function(v)
    ESP_Settings.TeamCheck = v
end)
CreateSliderToggle(MainFrame, "顯示FOV", true, 590, 110, function(v)
    ESP_Settings.UseFOV = v
    RefreshFOVCircle()
end)

-- ================ 第四排：自瞄功能（嚴格對齊+核心修復）============
CreateSliderToggle(MainFrame, "自瞄總開啟", false, 10, 145, function(v)
    ESP_Settings.AimbotEnabled = v
    RefreshFOVCircle()
end)

CreateSliderToggle(MainFrame, "長按自瞄", false, 120, 145, function(v) ESP_Settings.HoldMode = v end)

local AimPartBtn = Instance.new("TextButton", MainFrame)
AimPartBtn.Size = UDim2.new(0,100,0,25)
AimPartBtn.Position = UDim2.new(0,230,0,145)
AimPartBtn.BackgroundColor3 = Color3.fromRGB(100,100,255)
AimPartBtn.Text = "鎖頭"
AimPartBtn.TextColor3 = Color3.new(1,1,1)
AimPartBtn.TextSize = 14
AimPartBtn.Font = Enum.Font.Gotham
local AimCorner = Instance.new("UICorner", AimPartBtn)
AimCorner.CornerRadius = UDim.new(0,6)

AimPartBtn.MouseButton1Click:Connect(function()
    ESP_Settings.AimPart = ESP_Settings.AimPart == "Head" and "UpperTorso" or "Head"
    AimPartBtn.Text = ESP_Settings.AimPart == "Head" and "鎖頭" or "鎖身"
end)

-- 自瞄速度：2位小數顯示
CreatePlusMinusAdjuster(MainFrame, "自瞄速度", 0.40, 0.01, 0.5, 0.01, true, 340, 145, function(val)
    ESP_Settings.Smooth = val
end)

-- FOV大小：調整後刷新
CreatePlusMinusAdjuster(MainFrame, "FOV大小", 80, 20, 500, 10, false, 500, 145, function(val)
    ESP_Settings.FOV = val
end)

-- ================ 懸浮球開關選單 ================
FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ================ 主循環（強化FOV穩定性）===============
RunService.RenderStepped:Connect(function()
    -- 每幀強制刷新FOV圓圈，杜絕任何消失情況
    RefreshFOVCircle()

    -- 飛天邏輯
    if fly_enabled and parent and fly_rp then
        local moveVector = require(lp.PlayerScripts.PlayerModule.ControlModule):GetMoveVector()
        local y_input = (up_flag and 1 or 0) + (down_flag and -1 or 0)
        local move_dir = Vector3.new(moveVector.X, y_input, moveVector.Z)

        if move_dir.Magnitude > 0.1 then
            fly_pt.Position = parent.Position + (Camera.CFrame * CFrame.new(move_dir * 9999)).Position
            fly_rp:Fire()
            fly_bg.CFrame = Camera.CFrame
        else
            fly_rp:Abort()
        end

        parent.Anchored = anchor_enabled
    end

    -- ESP更新邏輯
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= lp then
            if not Drawings[plr] and ESP_Settings.Enabled then
                CreateESP(plr)
            end
            UpdateESP(plr)
        end
    end

    -- 自瞄邏輯
    if not ESP_Settings.AimbotEnabled or (ESP_Settings.HoldMode and not Touching) then return end

    local closestPart = nil
    local closestRealDistance = math.huge

    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= lp and plr.Character and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
            if ESP_Settings.TeamCheck and plr.Team == lp.Team then continue end

            local part = plr.Character:FindFirstChild(ESP_Settings.AimPart) or plr.Character.HumanoidRootPart
            if part then
                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local fovDist = (Vector2.new(screenPos.X, screenPos.Y) - FOVCircle.Position).Magnitude
                    local realDist = (LocalRoot.Position - part.Position).Magnitude

                    if (not ESP_Settings.UseFOV or fovDist <= ESP_Settings.FOV) and realDist < closestRealDistance then
                        closestRealDistance = realDist
                        closestPart = part
                    end
                end
            end
        end
    end

    if closestPart then
        local target = CFrame.lookAt(Camera.CFrame.Position, closestPart.Position)
        Camera.CFrame = Camera.CFrame:Lerp(target, ESP_Settings.Smooth)
    end
end)

-- ================ 卸載函數 ================
game:GetService("Players").LocalPlayer.CharacterRemoving:Connect(Cleanup)
uis.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.F12 then
        Cleanup()
        -- 卸載時手動銷毀FOV圓圈
        pcall(function() FOVCircle:Remove() end)
        ScreenGui:Destroy()
        print("終極版全能控制已卸載")
    end
end)
