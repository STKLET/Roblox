-- 手機/PC 通用飛天腳本（已修復 + 加入懸浮球）
local args = _E and _E.ARGS or {}
local uis = game:GetService("UserInputService")
local lp = game.Players.LocalPlayer
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera

local SPEED = args[1] or 127
local MAX_TORQUE_RP = args[3] or 1e4
local MAX_THRUST = args[5] or 5e5
local MAX_TORQUE_BG = args[6] or 3e4

local enabled = false
local anchor_enabled = false
local up_flag = false
local down_flag = false
local parent, humanoid
local fly_bg, fly_rp, fly_pt, flyModel

-- 清理舊物件
if _G.fly_evts then for _,e in pairs(_G.fly_evts) do e:Disconnect() end end
if _G.fly_bg then _G.fly_bg:Destroy() end
if _G.fly_rp then _G.fly_rp:Destroy() end
if _G.flyModel then _G.flyModel:Destroy() end

-- 創建隱藏目標
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

-- 初始化飛天
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

-- 主 GUI + 懸浮球
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FlyMenu"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game:GetService("CoreGui")

-- 懸浮球（左下角）
local FloatBtn = Instance.new("TextButton", ScreenGui)
FloatBtn.Size = UDim2.new(0,60,0,60)
FloatBtn.Position = UDim2.new(0,20,1,-80)
FloatBtn.BackgroundColor3 = Color3.fromRGB(0,0,0)
FloatBtn.BackgroundTransparency = 0.4
FloatBtn.Text = "飛"
FloatBtn.TextColor3 = Color3.new(1,1,1)
FloatBtn.TextScaled = true
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1,0)

-- 主選單
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0,240,0,300)
MainFrame.Position = UDim2.new(1,-260,0,20)
MainFrame.BackgroundColor3 = Color3.fromRGB(30,30,30)
MainFrame.Visible = false
MainFrame.Active = true
MainFrame.Draggable = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0,12)

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1,0,0,40)
Title.BackgroundTransparency = 1
Title.Text = "飛天控制"
Title.TextColor3 = Color3.new(1,1,1)
Title.TextScaled = true
Title.Font = Enum.Font.GothamBold

-- 開關函數（修復狀態同步）
local function CreateToggle(text, default, posY, callback)
    local btn = Instance.new("TextButton", MainFrame)
    btn.Size = UDim2.new(0.9,0,0,40)
    btn.Position = UDim2.new(0.05,0,0,posY)
    btn.BackgroundColor3 = default and Color3.fromRGB(0,200,0) or Color3.fromRGB(60,60,60)
    btn.Text = text .. (default and ": 開啟" or ": 關閉")
    btn.TextColor3 = Color3.new(1,1,1)
    btn.TextScaled = true
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)

    local state = default
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and Color3.fromRGB(0,200,0) or Color3.fromRGB(60,60,60)
        btn.Text = text .. (state and ": 開啟" or ": 關閉")
        callback(state)
    end)
    return btn
end

-- 飛天開關
local FlyToggle = CreateToggle("飛天", false, 50, function(v)
    enabled = v
    if v then
        initFly()
        fly_bg.MaxTorque = Vector3.new(MAX_TORQUE_BG,0,MAX_TORQUE_BG)
        fly_rp.MaxTorque = Vector3.new(MAX_TORQUE_RP,MAX_TORQUE_RP,MAX_TORQUE_RP)
    else
        if fly_bg then fly_bg.MaxTorque = Vector3.new() end
        if fly_rp then fly_rp.MaxTorque = Vector3.new() end
    end
end)

-- 錨定開關
CreateToggle("錨定", false, 100, function(v)
    anchor_enabled = v
end)

-- 速度顯示與調整
local SpeedLabel = Instance.new("TextLabel", MainFrame)
SpeedLabel.Size = UDim2.new(0.6,0,0,35)
SpeedLabel.Position = UDim2.new(0.05,0,0,150)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "速度: "..SPEED
SpeedLabel.TextColor3 = Color3.new(1,1,1)
SpeedLabel.TextScaled = true

local function UpdateSpeed()
    SpeedLabel.Text = "速度: "..math.floor(SPEED)
    if fly_rp then fly_rp.MaxSpeed = SPEED end
end

local PlusBtn = Instance.new("TextButton", MainFrame)
PlusBtn.Size = UDim2.new(0.18,0,0,35)
PlusBtn.Position = UDim2.new(0.68,0,0,150)
PlusBtn.BackgroundColor3 = Color3.fromRGB(0,255,127)
PlusBtn.Text = "+"
PlusBtn.TextScaled = true
PlusBtn.MouseButton1Click:Connect(function()
    SPEED = SPEED * 1.5
    UpdateSpeed()
end)

local MinusBtn = PlusBtn:Clone()
MinusBtn.Position = UDim2.new(0.88,0,0,150)
MinusBtn.BackgroundColor3 = Color3.fromRGB(255,100,100)
MinusBtn.Text = "-"
MinusBtn.MouseButton1Click:Connect(function()
    SPEED = math.max(50, SPEED / 1.5)
    UpdateSpeed()
end)

-- 上升/下降按鈕（按住）
local UpBtn = Instance.new("TextButton", MainFrame)
UpBtn.Size = UDim2.new(0.45,-5,0,40)
UpBtn.Position = UDim2.new(0.05,0,0,200)
UpBtn.BackgroundColor3 = Color3.fromRGB(0,170,255)
UpBtn.Text = "上升"
UpBtn.TextScaled = true
UpBtn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then up_flag = true end end)
UpBtn.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then up_flag = false end end)

local DownBtn = UpBtn:Clone()
DownBtn.Position = UDim2.new(0.55,0,0,200)
DownBtn.Text = "下降"
DownBtn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then down_flag = true end end)
DownBtn.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then down_flag = false end end)

-- 懸浮球開關選單
FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- 主循環
RunService.RenderStepped:Connect(function()
    if not enabled or not parent or not fly_rp then return end

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
end)

-- 重生續飛
lp.CharacterAdded:Connect(function()
    task.wait(1)
    if enabled then initFly() end
end)

print("飛天已載入！點左下角「飛」球開啟選單")