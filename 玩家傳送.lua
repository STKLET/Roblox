-- 双模式独立传送脚本（残血优先+单一锁定）
-- 核心配置：统一参数
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")

-- 全局配置（统一参数）
local LOCK_RANGE = 300       -- 最大锁定范围
local TP_HEIGHT = 0          -- 传送高度（与目标持平）
local TP_DISTANCE = 6        -- 传送距离（目标身后6单位）
local COOLDOWN = 0.1         -- 传送间隔（0.1秒）
local LOCK_LOWEST = false    -- 残血优先模式开关
local LOCK_SINGLE = false    -- 单一目标模式开关
local currentLowestTarget = nil
local currentSingleTarget = nil
local lastTpTime = 0

-- GUI容器（手机端左侧布局，适配触屏）
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DualTeleportGui"
screenGui.Parent = game:GetService("CoreGui")

-- ========== 1. 残血优先模式按钮 ==========
local lowestBtn = Instance.new("TextButton")
lowestBtn.Size = UDim2.new(0, 150, 0, 45)
lowestBtn.Position = UDim2.new(0, 15, 0.3, 0)
lowestBtn.BackgroundColor3 = Color3.fromRGB(220, 0, 0)
lowestBtn.Text = "开启残血优先"
lowestBtn.TextColor3 = Color3.new(1,1,1)
lowestBtn.TextSize = 13
lowestBtn.Font = Enum.Font.SourceSans
lowestBtn.Parent = screenGui
Instance.new("UICorner", lowestBtn).CornerRadius = UDim.new(0, 12)

-- ========== 2. 单一目标模式按钮 ==========
local singleBtn = Instance.new("TextButton")
singleBtn.Size = UDim2.new(0, 150, 0, 45)
singleBtn.Position = UDim2.new(0, 15, 0.4, 0)
singleBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
singleBtn.Text = "开启单一锁定"
singleBtn.TextColor3 = Color3.new(1,1,1)
singleBtn.TextSize = 13
singleBtn.Font = Enum.Font.SourceSans
singleBtn.Parent = screenGui
Instance.new("UICorner", singleBtn).CornerRadius = UDim.new(0, 12)

-- ========== 3. 玩家列表按钮 ==========
local listBtn = Instance.new("TextButton")
listBtn.Size = UDim2.new(0, 150, 0, 35)
listBtn.Position = UDim2.new(0, 15, 0.5, 0)
listBtn.BackgroundColor3 = Color3.fromRGB(80, 160, 80)
listBtn.Text = "展开玩家列表"
listBtn.TextColor3 = Color3.new(1,1,1)
listBtn.TextSize = 11
listBtn.Font = Enum.Font.SourceSans
listBtn.Parent = screenGui
listBtn.Visible = false -- 仅单一模式开启后显示
Instance.new("UICorner", listBtn).CornerRadius = UDim.new(0, 10)

-- ========== 4. 玩家列表滚动容器（修复滚动问题） ==========
local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(0, 150, 0, 140)
listFrame.Position = UDim2.new(0, 15, 0.56, 0)
listFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
listFrame.ScrollBarThickness = 6
listFrame.Visible = false
listFrame.Parent = screenGui
-- 关键修复：允许垂直滚动 + 自动适配画布大小
listFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y -- 自动根据内容调整高度
Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 10)

-- 列表自动排版
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
listLayout.Parent = listFrame

-- ========== 5. 状态显示标签 ==========
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 150, 0, 30)
statusLabel.Position = UDim2.new(0, 15, 0.22, 0)
statusLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
statusLabel.Text = "当前模式: 无"
statusLabel.TextColor3 = Color3.new(1,1,1)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.SourceSans
statusLabel.Parent = screenGui
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 8)

-- ========== 核心函数：寻找血量最低玩家 ==========
local function FindLowestHealthEnemy()
    local lowestHealth = math.huge
    local targetEnemy = nil
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= lp and plr.Character then
            local enemyRoot = plr.Character:FindFirstChild("HumanoidRootPart")
            local enemyHum = plr.Character:FindFirstChild("Humanoid")
            if enemyRoot and enemyHum and enemyHum.Health > 0 then
                local dist = (root.Position - enemyRoot.Position).Magnitude
                if dist <= LOCK_RANGE and enemyHum.Health < lowestHealth then
                    lowestHealth = enemyHum.Health
                    targetEnemy = plr.Character
                end
            end
        end
    end
    return targetEnemy
end

-- ========== 核心函数：刷新玩家列表 ==========
local function RefreshPlayerList()
    -- 清空原有列表按钮
    for _, child in pairs(listFrame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    -- 填充所有玩家（排除自己）
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= lp then
            local playerBtn = Instance.new("TextButton")
            playerBtn.Size = UDim2.new(0, 130, 0, 30)
            playerBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            playerBtn.Text = plr.Name
            playerBtn.TextColor3 = Color3.new(1,1,1)
            playerBtn.TextSize = 12
            playerBtn.Font = Enum.Font.SourceSans
            playerBtn.Parent = listFrame
            Instance.new("UICorner", playerBtn).CornerRadius = UDim.new(0, 6)
            -- 点击选择该玩家为单一目标
            playerBtn.MouseButton1Click:Connect(function()
                currentSingleTarget = plr
                statusLabel.Text = "锁定目标: "..plr.Name
                listFrame.Visible = false
                listBtn.Text = "展开玩家列表"
            end)
        end
    end
end

-- ========== 核心函数：执行传送 ==========
local function TeleportToTarget(targetChar)
    if not targetChar then return end
    local enemyRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local enemyHum = targetChar:FindFirstChild("Humanoid")
    if not enemyRoot or not enemyHum or enemyHum.Health <= 0 then
        return false
    end
    -- 计算传送位置：目标身后6单位，高度0
    local teleportCFrame = enemyRoot.CFrame - enemyRoot.CFrame.LookVector * TP_DISTANCE + Vector3.new(0, TP_HEIGHT, 0)
    root.CFrame = teleportCFrame
    return true
end

-- ========== 模式开关逻辑 ==========
-- 残血优先模式开关
lowestBtn.MouseButton1Click:Connect(function()
    if LOCK_SINGLE then return end -- 单一模式开启时无法切换
    LOCK_LOWEST = not LOCK_LOWEST
    lowestBtn.BackgroundColor3 = LOCK_LOWEST and Color3.fromRGB(0, 180, 0) or Color3.fromRGB(220, 0, 0)
    lowestBtn.Text = LOCK_LOWEST and "残血优先已开启" or "开启残血优先"
    statusLabel.Text = LOCK_LOWEST and "当前模式: 残血优先" or "当前模式: 无"
    -- 开启时立即寻找目标
    if LOCK_LOWEST then
        currentLowestTarget = FindLowestHealthEnemy()
        if currentLowestTarget then
            statusLabel.Text = "锁定残血: "..currentLowestTarget.Name
        else
            statusLabel.Text = "无有效残血目标"
        end
    end
end)

-- 单一目标模式开关
singleBtn.MouseButton1Click:Connect(function()
    LOCK_SINGLE = not LOCK_SINGLE
    singleBtn.BackgroundColor3 = LOCK_SINGLE and Color3.fromRGB(0, 150, 200) or Color3.fromRGB(0, 100, 200)
    singleBtn.Text = LOCK_SINGLE and "单一锁定已开启" or "开启单一锁定"
    listBtn.Visible = LOCK_SINGLE
    -- 切换模式时关闭残血优先
    if LOCK_SINGLE then
        LOCK_LOWEST = false
        lowestBtn.BackgroundColor3 = Color3.fromRGB(220, 0, 0)
        lowestBtn.Text = "开启残血优先"
        statusLabel.Text = "请展开列表选目标"
        currentLowestTarget = nil
    else
        listFrame.Visible = false
        listBtn.Text = "展开玩家列表"
        currentSingleTarget = nil
        statusLabel.Text = "当前模式: 无"
    end
end)

-- 玩家列表展开/收起逻辑
listBtn.MouseButton1Click:Connect(function()
    listFrame.Visible = not listFrame.Visible
    listBtn.Text = listFrame.Visible and "收起玩家列表" or "展开玩家列表"
    if listFrame.Visible then
        RefreshPlayerList()
    end
end)

-- ========== 持续循环执行传送 ==========
RunService.Heartbeat:Connect(function()
    -- 冷却判断
    if tick() - lastTpTime < COOLDOWN then return end
    lastTpTime = tick()

    -- 优先执行单一目标模式
    if LOCK_SINGLE and currentSingleTarget then
        local targetChar = currentSingleTarget.Character
        if targetChar then
            local success = TeleportToTarget(targetChar)
            if not success then
                statusLabel.Text = "目标失效，请重新选择"
            end
        else
            statusLabel.Text = "目标角色不存在"
        end
    -- 其次执行残血优先模式
    elseif LOCK_LOWEST then
        local newTarget = FindLowestHealthEnemy()
        -- 检测到更低血量目标则切换
        if newTarget and (not currentLowestTarget or newTarget.Humanoid.Health < currentLowestTarget.Humanoid.Health) then
            currentLowestTarget = newTarget
            statusLabel.Text = "锁定残血: "..currentLowestTarget.Name
        end
        if currentLowestTarget then
            local success = TeleportToTarget(currentLowestTarget)
            if not success then
                currentLowestTarget = FindLowestHealthEnemy()
                statusLabel.Text = currentLowestTarget and "切换目标: "..currentLowestTarget.Name or "无有效残血目标"
            end
        end
    end
end)

-- ========== 重生绑定逻辑 ==========
lp.CharacterAdded:Connect(function(newChar)
    char = newChar
    root = newChar:WaitForChild("HumanoidRootPart")
    -- 重生后保持模式状态
    if LOCK_LOWEST then
        currentLowestTarget = FindLowestHealthEnemy()
    end
end)

-- ========== 玩家进出服刷新列表 ==========
Players.PlayerAdded:Connect(function()
    if listFrame.Visible then
        RefreshPlayerList()
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    if listFrame.Visible then
        RefreshPlayerList()
    end
    -- 移除的是当前单一目标则清空
    if currentSingleTarget == plr then
        currentSingleTarget = nil
        statusLabel.Text = "目标已离开服务器"
    end
end)

print("双模式传送脚本（修复滚动）加载成功！")
