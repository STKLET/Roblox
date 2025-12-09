--[==[HELP]==
-- 手機/PC 通用飛天腳本（基於原版修改）
-- 原版PC鍵盤控制已替換為跨平台GUI + Roblox內建搖桿
-- 手機：點擊GUI按鈕開關，按住Up/Down飛升降，搖桿控制前後左右
-- PC：同上，WASD控制前後左右
-- GUI位於右上角，可拖拽
-- 支援原參數（透過args傳入）
]==] --

local args = _E and _E.ARGS or {}
local FLYK = Enum.KeyCode.H  -- 保留但未用，可選
local uis = game:GetService("UserInputService")
local lp = game.Players.LocalPlayer
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera

local SPEED = args[1] or 127
local REL_TO_CHAR = args[2] or false
local MAX_TORQUE_RP = args[3] or 1e4
local THRUST_P = args[4] or 1e5
local MAX_THRUST = args[5] or 5e5
local MAX_TORQUE_BG = args[6] or 3e4
local THRUST_D = args[7] or math.huge
local TURN_D = args[8] or 2e2
local ROOT_PART = args[9]

local flying = false
local enabled = false
local move_dir = Vector3.new()
local humanoid
local parent
local ms = lp:GetMouse()  -- PC用
local up_flag = false
local down_flag = false
local anchor_enabled = false

-- 清理舊實例
if _G.fly_evts then
    for _, e in pairs(_G.fly_evts) do e:Disconnect() end
end
if _G.fly_bg then _G.fly_bg:Destroy() end
if _G.fly_rp then _G.fly_rp:Destroy() end
if _G.flyModel then _G.flyModel:Destroy() end
if args[1] == false then return end

-- 創建隱藏目標模型（修復原版bug）
local function createFlyTarget()
    _G.flyModel = Instance.new("Model")
    _G.flyModel.Name = "FlyTarget"
    _G.flyModel.Parent = workspace
    _G.fly_pt = Instance.new("Part")
    _G.fly_pt.Name = "Target"
    _G.fly_pt.Parent = _G.flyModel
    _G.fly_pt.Anchored = true
    _G.fly_pt.CanCollide = false
    _G.fly_pt.Size = Vector3.new(0.1, 0.1, 0.1)
    _G.fly_pt.Transparency = 1
    _G.flyModel.PrimaryPart = _G.fly_pt
end

-- 初始化飛天物件
local function init()
    if ROOT_PART then
        parent = ROOT_PART
        local model = parent:FindFirstAncestorOfClass("Model")
        if model then humanoid = model:FindFirstChildOfClass("Humanoid") end
    else
        local ch = lp.Character
        if ch then
            humanoid = ch:FindFirstChildOfClass("Humanoid")
            parent = ch:FindFirstChild("HumanoidRootPart")
        end
    end
    if not parent then return end

    -- 清理舊物件
    if _G.fly_bg then _G.fly_bg:Destroy() end
    if _G.fly_rp then _G.fly_rp:Destroy() end
    if _G.flyModel then _G.flyModel:Destroy() end

    createFlyTarget()

    local rp_h = MAX_TORQUE_RP
    _G.fly_bg = Instance.new("BodyGyro", parent)
    _G.fly_bg.P = 3e4
    _G.fly_bg.MaxTorque = Vector3.new()

    _G.fly_rp = Instance.new("RocketPropulsion", parent)
    _G.fly_rp.MaxTorque = Vector3.new(rp_h, rp_h, rp_h)
    _G.fly_rp.CartoonFactor = 1
    _G.fly_rp.Target = _G.fly_pt
    _G.fly_rp.MaxSpeed = SPEED
    _G.fly_rp.MaxThrust = MAX_THRUST
    _G.fly_rp.ThrustP = THRUST_P
    _G.fly_rp.ThrustD = THRUST_D
    _G.fly_rp.TurnP = THRUST_P
    _G.fly_rp.TurnD = TURN_D

    enabled = false
end

-- 計算飛行方向（PC用mouse，mobile用螢幕中心）
local function fly_dir()
    local front
    if REL_TO_CHAR then
        front = parent.CFrame.LookVector
    else
        local cam = workspace.CurrentCamera
        local mx, my
        if uis.TouchEnabled then
            mx = cam.ViewportSize.X / 2
            my = cam.ViewportSize.Y / 2
        else
            mx = ms.X
            my = ms.Y
        end
        front = cam:ScreenPointToRay(mx, my).Direction
    end
    return CFrame.new(Vector3.new(), front) * move_dir
end

-- 創建手機/PC通用GUI
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FlyGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = game:GetService("CoreGui")

    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 220, 0, 280)
    mainFrame.Position = UDim2.new(1, -240, 0, 20)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "飛天控制"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = mainFrame

    local function createButton(text, pos, callback)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.9, 0, 0, 35)
        btn.Position = pos
        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextScaled = true
        btn.Font = Enum.Font.Gotham
        btn.Parent = mainFrame
        local btnCorner = Instance.new("UICorner", btn)
        btnCorner.CornerRadius = UDim.new(0, 8)
        btn.MouseButton1Click:Connect(callback)
        return btn
    end

    local function createHoldButton(dir)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.45, -5, 0, 35)
        btn.Position = UDim2.new(dir == "up" and 0.05 or 0.52, 0, 0, 220)
        btn.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
        btn.Text = dir == "up" and "上升" or "下降"
        btn.TextColor3 = Color3.new(1,1,1)
        btn.TextScaled = true
        btn.Font = Enum.Font.Gotham
        btn.Parent = mainFrame
        local btnCorner = Instance.new("UICorner", btn)
        btnCorner.CornerRadius = UDim.new(0, 8)

        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if dir == "up" then up_flag = true else down_flag = true end
            end
        end)
        btn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if dir == "up" then up_flag = false else down_flag = false end
            end
        end)
        return btn
    end

    -- Fly Toggle
    local flyBtn = createButton("飛天: 關閉", UDim2.new(0.05, 0, 0, 50), function()
        enabled = not enabled
        flyBtn.Text = enabled and "飛天: 開啟" or "飛天: 關閉"
        flyBtn.BackgroundColor3 = enabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(50, 50, 50)
        if enabled then
            if _G.fly_bg then _G.fly_bg.MaxTorque = Vector3.new(MAX_TORQUE_BG, 0, MAX_TORQUE_BG) end
            if _G.fly_rp then _G.fly_rp.MaxTorque = Vector3.new(MAX_TORQUE_RP, MAX_TORQUE_RP, MAX_TORQUE_RP) end
        else
            if _G.fly_bg then _G.fly_bg.MaxTorque = Vector3.new() end
            if _G.fly_rp then _G.fly_rp.MaxTorque = Vector3.new() end
        end
    end)

    -- Anchor Toggle
    local anchorBtn = createButton("錨定: 關閉", UDim2.new(0.05, 0, 0, 95), function()
        anchor_enabled = not anchor_enabled
        if parent then parent.Anchored = anchor_enabled end
        anchorBtn.Text = anchor_enabled and "錨定: 開啟" or "錨定: 關閉"
        anchorBtn.BackgroundColor3 = anchor_enabled and Color3.fromRGB(255, 165, 0) or Color3.fromRGB(50, 50, 50)
    end)

    -- Speed Label
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(0.6, 0, 0, 35)
    speedLabel.Position = UDim2.new(0.05, 0, 0, 140)
    speedLabel.BackgroundTransparency = 1
    speedLabel.Text = "速度: " .. SPEED
    speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    speedLabel.TextScaled = true
    speedLabel.Font = Enum.Font.Gotham
    speedLabel.Parent = mainFrame

    -- Speed +/-
    local speedUpBtn = Instance.new("TextButton")
    speedUpBtn.Size = UDim2.new(0.18, 0, 0, 35)
    speedUpBtn.Position = UDim2.new(0.68, 0, 0, 140)
    speedUpBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 127)
    speedUpBtn.Text = "+"
    speedUpBtn.TextScaled = true
    speedUpBtn.Parent = mainFrame
    local speedUpCorner = Instance.new("UICorner", speedUpBtn)
    speedUpCorner.CornerRadius = UDim.new(0, 8)

    local speedDownBtn = speedUpBtn:Clone()
    speedDownBtn.Text = "-"
    speedDownBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    speedDownBtn.Position = UDim2.new(0.88, 0, 0, 140)
    speedDownBtn.Parent = mainFrame
    local speedDownCorner = Instance.new("UICorner", speedDownBtn)
    speedDownCorner.CornerRadius = UDim.new(0, 8)

    speedUpBtn.MouseButton1Click:Connect(function()
        SPEED = SPEED * (3 / 2)
        if _G.fly_rp then _G.fly_rp.MaxSpeed = SPEED end
        speedLabel.Text = "速度: " .. math.floor(SPEED)
    end)
    speedDownBtn.MouseButton1Click:Connect(function()
        SPEED = SPEED / (3 / 2)
        SPEED = math.max(1, SPEED)  -- 最小速度
        if _G.fly_rp then _G.fly_rp.MaxSpeed = SPEED end
        speedLabel.Text = "速度: " .. math.floor(SPEED)
    end)

    -- Up/Down Buttons
    createHoldButton("up")
    createHoldButton("down")

    return screenGui
end

-- 主更新循環
_G.fly_evts = {
    lp.CharacterAdded:Connect(function()
        task.wait(1)  -- 等待角色載入
        init()
    end),
    RunService.RenderStepped:Connect(function()
        if not _G.fly_rp or not parent then return end

        -- 獲取移動向量（跨平台：PC WASD / Mobile 搖桿）
        local playerScripts = lp:WaitForChild("PlayerScripts")
        local playerModule = playerScripts:WaitForChild("PlayerModule")
        local controlModule = require(playerModule:WaitForChild("ControlModule"))
        local moveVector = controlModule:GetMoveVector()

        -- Vertical from buttons
        local y_input = 0
        if up_flag then y_input = 1
        elseif down_flag then y_input = -1 end

        move_dir = Vector3.new(moveVector.X, y_input, moveVector.Z)

        local do_fly = enabled and move_dir.Magnitude > 0
        if flying ~= do_fly then
            flying = do_fly
            if humanoid then humanoid.AutoRotate = not do_fly end
            if not do_fly then
                parent.Velocity = Vector3.new()
                _G.fly_rp:Abort()
                return
            end
            _G.fly_rp:Fire()
        end
        _G.fly_pt.Position = parent.Position + 4096 * fly_dir()
    end),
}

-- 初始化
createGUI()
init()

print("飛天腳本載入完成！右上角GUI控制（支援手機/PC）")