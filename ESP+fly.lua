--[[
    WA 通用透視 + 自瞄 完整修復版（手機專用）
    自瞄優化：更快 + 優先鎖定真實距離最近且在FOV內的目標
]]
loadstring(game:HttpGet("https://raw.githubusercontent.com/STKLET/Roblox/main/Roblox飛天.lua"))()


local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- 自動更新本地角色
local LocalCharacter = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local LocalRoot = LocalCharacter:WaitForChild("HumanoidRootPart")
LocalPlayer.CharacterAdded:Connect(function(c)
    LocalCharacter = c
    LocalRoot = c:WaitForChild("HumanoidRootPart")
end)

-- ==================== 設定表 ====================
local Settings = {
    Enabled = false,
    TeamCheck = false,
    ShowTeam = false,

    ShowBox = true,
    ShowHealth = true,
    ShowTracer = true,
    ShowSkeleton = true,
    ShowTool = true,
    ShowName = true,
    ShowDistance = true,
    ChamsEnabled = false,

    BoxColor = Color3.fromRGB(255,255,255),
    TracerColor = Color3.fromRGB(255,255,255),
    SkeletonColor = Color3.fromRGB(255,255,255),
    ChamsFillColor = Color3.fromRGB(255,0,0),

    MaxDistance = 1000,

    -- 自瞄（已優化）
    AimbotEnabled = false,
    AimPart = "Head",
    Smooth = 0.35,        
    UseFOV = true,
    FOV = 80,
    FOVColor = Color3.fromRGB(255,0,0),
    HoldMode = false,
}

-- ==================== 繪製物件 ====================
local Drawings = {}
local Highlights = {}
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 2
FOVCircle.NumSides = 80
FOVCircle.Filled = false
FOVCircle.Visible = false

-- ==================== 骨骼連接表 ====================
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

-- ==================== 建立 ESP ====================
local function CreateESP(plr)
    if plr == LocalPlayer then return end

    local comp = {
        Box = Drawing.new("Square"),
        Tracer = Drawing.new("Line"),
        NameLabel = Drawing.new("Text"),
        DistanceLabel = Drawing.new("Text"),
        HealthBar = {Outline = Drawing.new("Square"), Fill = Drawing.new("Square")},
        ToolLabel = Drawing.new("Text"),
        Skeleton = {}
    }

    comp.Box.Thickness = 1; comp.Box.Filled = false; comp.Box.Transparency = 1
    comp.Tracer.Thickness = 1; comp.Tracer.Transparency = 1
    comp.NameLabel.Size = 18; comp.NameLabel.Center = true; comp.NameLabel.Outline = true
    comp.DistanceLabel.Size = 18; comp.DistanceLabel.Center = true; comp.DistanceLabel.Outline = true
    comp.ToolLabel.Size = 18; comp.ToolLabel.Center = true; comp.ToolLabel.Outline = true
    comp.HealthBar.Outline.Thickness = 1; comp.HealthBar.Outline.Filled = false
    comp.HealthBar.Fill.Thickness = 1; comp.HealthBar.Fill.Filled = true

    local hl = Instance.new("Highlight")
    hl.FillColor = Settings.ChamsFillColor
    hl.OutlineColor = Color3.fromRGB(255,255,255)
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    hl.Enabled = false
    Highlights[plr] = hl

    Drawings[plr] = comp
end

-- ==================== 更新 ESP ====================
local function UpdateESP(plr)
    local comp = Drawings[plr]
    if not comp then return end

    if not Settings.Enabled or not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") or not plr.Character:FindFirstChild("Humanoid") or plr.Character.Humanoid.Health <= 0 then
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

    if Settings.TeamCheck and plr.Team == LocalPlayer.Team and not Settings.ShowTeam then
        comp.Box.Visible = false; comp.Tracer.Visible = false; comp.NameLabel.Visible = false
        comp.DistanceLabel.Visible = false; comp.HealthBar.Outline.Visible = false; comp.HealthBar.Fill.Visible = false
        comp.ToolLabel.Visible = false; for _, line in pairs(comp.Skeleton) do line.Visible = false end
        if Highlights[plr] then Highlights[plr].Enabled = false end
        return
    end

    if not onScreen or distance > Settings.MaxDistance then
        comp.Box.Visible = false; comp.Tracer.Visible = false; comp.NameLabel.Visible = false
        comp.DistanceLabel.Visible = false; comp.HealthBar.Outline.Visible = false; comp.HealthBar.Fill.Visible = false
        comp.ToolLabel.Visible = false; for _, line in pairs(comp.Skeleton) do line.Visible = false end
        if Highlights[plr] then Highlights[plr].Enabled = false end
        return
    end

    -- 計算方框大小（你原本的，沒動）
    local topPos = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
    local bottomPos = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
    local boxHeight = math.abs(topPos.Y - bottomPos.Y)
    local boxWidth = boxHeight / 2

    if Settings.ShowBox then
        comp.Box.Size = Vector2.new(boxWidth, boxHeight)
        comp.Box.Position = Vector2.new(rootPos.X - boxWidth/2, rootPos.Y - boxHeight/2)
        comp.Box.Color = Settings.BoxColor
        comp.Box.Visible = true
    else
        comp.Box.Visible = false
    end

    if Settings.ShowTracer then
        comp.Tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
        comp.Tracer.To = Vector2.new(rootPos.X, rootPos.Y + boxHeight/2)
        comp.Tracer.Color = Settings.TracerColor
        comp.Tracer.Visible = true
    else
        comp.Tracer.Visible = false
    end

    if Settings.ShowName then
        comp.NameLabel.Text = "[" .. plr.Name .. "]"
        comp.NameLabel.Position = Vector2.new(rootPos.X, rootPos.Y - boxHeight/2 - 15)
        comp.NameLabel.Visible = true
    else
        comp.NameLabel.Visible = false
    end

    if Settings.ShowDistance then
        comp.DistanceLabel.Text = "[" .. math.floor(distance) .. "M]"
        comp.DistanceLabel.Position = Vector2.new(rootPos.X, rootPos.Y + boxHeight/2 + 15)
        comp.DistanceLabel.Visible = true
    else
        comp.DistanceLabel.Visible = false
    end

    if Settings.ShowHealth then
        local hbHeight = boxHeight
        local hbWidth = 5
        local hf = hum.Health / hum.MaxHealth
        comp.HealthBar.Outline.Size = Vector2.new(hbWidth, hbHeight)
        comp.HealthBar.Outline.Position = Vector2.new(comp.Box.Position.X - hbWidth - 2, comp.Box.Position.Y)
        comp.HealthBar.Outline.Visible = true
        comp.HealthBar.Fill.Size = Vector2.new(hbWidth - 2, hbHeight * hf)
        comp.HealthBar.Fill.Position = Vector2.new(comp.HealthBar.Outline.Position.X + 1, comp.HealthBar.Outline.Position.Y + hbHeight * (1 - hf))
        comp.HealthBar.Fill.Color = Color3.fromRGB(255 * (1 - hf), 255 * hf, 0)
        comp.HealthBar.Fill.Visible = true
    else
        comp.HealthBar.Outline.Visible = false
        comp.HealthBar.Fill.Visible = false
    end

    if Settings.ShowTool then
        local tool = plr.Backpack:FindFirstChildOfClass("Tool") or char:FindFirstChildOfClass("Tool")
        comp.ToolLabel.Text = tool and "[持有: " .. tool.Name .. "]" or "[持有: 無]"
        comp.ToolLabel.Position = Vector2.new(rootPos.X, rootPos.Y + boxHeight/2 + 35)
        comp.ToolLabel.Visible = true
    else
        comp.ToolLabel.Visible = false
    end

    if Settings.ShowSkeleton then
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
                    line.Color = Settings.SkeletonColor
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

    if Settings.ChamsEnabled then
        Highlights[plr].Parent = char
        Highlights[plr].FillColor = Settings.ChamsFillColor
        Highlights[plr].Enabled = true
    else
        Highlights[plr].Enabled = false
    end
end

-- ==================== 移除 ESP ====================
local function RemoveESP(plr)
    local comp = Drawings[plr]
    if comp then
        comp.Box:Remove()
        comp.Tracer:Remove()
        comp.NameLabel:Remove()
        comp.DistanceLabel:Remove()
        comp.HealthBar.Outline:Remove()
        comp.HealthBar.Fill:Remove()
        comp.ToolLabel:Remove()
        for _, line in pairs(comp.Skeleton) do line:Remove() end
        Drawings[plr] = nil
    end
    if Highlights[plr] then Highlights[plr]:Destroy(); Highlights[plr] = nil end
end

-- ==================== 自瞄（已完全重寫，更快 + 優先真實距離最近）===================
local Touching = false
UserInputService.TouchStarted:Connect(function() Touching = true end)
UserInputService.TouchEnded:Connect(function() Touching = false end)

RunService.RenderStepped:Connect(function()
    FOVCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    FOVCircle.Radius = Settings.FOV
    FOVCircle.Color = Settings.FOVColor
    FOVCircle.Visible = Settings.AimbotEnabled and Settings.UseFOV

    if not Settings.AimbotEnabled or (Settings.HoldMode and not Touching) then return end

    local closestPart = nil
    local closestRealDistance = math.huge

    for _, plr in Players:GetPlayers() do
        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
            if Settings.TeamCheck and plr.Team == LocalPlayer.Team then continue end

            local part = plr.Character:FindFirstChild(Settings.AimPart) or plr.Character.HumanoidRootPart
            if part then
                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local fovDist = (Vector2.new(screenPos.X, screenPos.Y) - FOVCircle.Position).Magnitude
                    local realDist = (LocalRoot.Position - part.Position).Magnitude

                    if (not Settings.UseFOV or fovDist <= Settings.FOV) and realDist < closestRealDistance then
                        closestRealDistance = realDist
                        closestPart = part
                    end
                end
            end
        end
    end

    if closestPart then
        local target = CFrame.lookAt(Camera.CFrame.Position, closestPart.Position)
        Camera.CFrame = Camera.CFrame:Lerp(target, Settings.Smooth)
    end
end)

-- ==================== 主循環 ====================
RunService.RenderStepped:Connect(function()
    for _, plr in Players:GetPlayers() do
        if plr ~= LocalPlayer then
            if not Drawings[plr] then CreateESP(plr) end
            UpdateESP(plr)
        end
    end
end)

Players.PlayerAdded:Connect(CreateESP)
Players.PlayerRemoving:Connect(RemoveESP)
for _, plr in Players:GetPlayers() do if plr ~= LocalPlayer then CreateESP(plr) end end

-- ==================== Fluent GUI ====================
local Window = Fluent:CreateWindow({
    Title = "WA 通用透視 + 自瞄",
    SubTitle = "自瞄超快+鎖最近",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
        
})

local Tabs = {
    ESP = Window:AddTab({ Title = "透視功能", Icon = "eye" }),
    Aimbot = Window:AddTab({ Title = "自瞄功能", Icon = "target" }),
    Settings = Window:AddTab({ Title = "詳細設定", Icon = "settings" }),
    Config = Window:AddTab({ Title = "配置", Icon = "save" })
}

-- ESP Tab（完全沒動）
do
    local MainSection = Tabs.ESP:AddSection("主要開關")
    MainSection:AddToggle("Enabled", {Title = "啟用透視", Default = true}):OnChanged(function(v) Settings.Enabled = v end)
    MainSection:AddToggle("TeamCheck", {Title = "隊友檢查", Default = false}):OnChanged(function(v) Settings.TeamCheck = v end)
    MainSection:AddToggle("ShowTeam", {Title = "顯示隊友", Default = false}):OnChanged(function(v) Settings.ShowTeam = v end)
    MainSection:AddToggle("ChamsEnabled", {Title = "人物高亮", Default = false}):OnChanged(function(v) Settings.ChamsEnabled = v end)

    local ESPSection = Tabs.ESP:AddSection("ESP 項目")
    ESPSection:AddToggle("ShowBox", {Title = "方框", Default = true}):OnChanged(function(v) Settings.ShowBox = v end)
    ESPSection:AddToggle("ShowHealth", {Title = "血條", Default = true}):OnChanged(function(v) Settings.ShowHealth = v end)
    ESPSection:AddToggle("ShowTracer", {Title = "追蹤線", Default = true}):OnChanged(function(v) Settings.ShowTracer = v end)
    ESPSection:AddToggle("ShowSkeleton", {Title = "骨骼", Default = true}):OnChanged(function(v) Settings.ShowSkeleton = v end)
    ESPSection:AddToggle("ShowTool", {Title = "手持道具", Default = true}):OnChanged(function(v) Settings.ShowTool = v end)
    ESPSection:AddToggle("ShowName", {Title = "名稱", Default = true}):OnChanged(function(v) Settings.ShowName = v end)
    ESPSection:AddToggle("ShowDistance", {Title = "距離", Default = true}):OnChanged(function(v) Settings.ShowDistance = v end)
end

-- Aimbot Tab（已優化選項）
do
    local AimbotSection = Tabs.Aimbot:AddSection("自瞄開關")
    AimbotSection:AddToggle("AimbotEnabled", {Title = "啟用自瞄", Default = false}):OnChanged(function(v) Settings.AimbotEnabled = v end)
    AimbotSection:AddToggle("HoldMode", {Title = "長按模式", Default = false}):OnChanged(function(v) Settings.HoldMode = v end)
    AimbotSection:AddToggle("UseFOV", {Title = "限制FOV範圍", Default = true}):OnChanged(function(v) Settings.UseFOV = v end)
    AimbotSection:AddToggle("AimHead", {Title = "鎖頭 (關閉鎖身)", Default = true}):OnChanged(function(v) Settings.AimPart = v and "Head" or "UpperTorso" end)

    local SliderSection = Tabs.Aimbot:AddSection("調整參數")
    SliderSection:AddDropdown("Smooth", {
        Title = "自瞄速度",
        Values = {0.04, 0.06, 0.08, 0.10, 0.12, 0.14, 0.16, 0.18, 0.20, 0.25, 0.30, 0.35},
        Default = 0.35
    }):OnChanged(function(v) Settings.Smooth = v end)

    SliderSection:AddDropdown("FOV", {
        Title = "FOV大小",
        Values = {50, 80, 100, 120, 150, 180, 220, 260, 300, 400, 500},
        Default = 80
    }):OnChanged(function(v) Settings.FOV = v end)
end

-- Settings Tab（顏色等沒變）
do
    local ColorsSection = Tabs.Settings:AddSection("顏色設定")
    ColorsSection:AddColorpicker("BoxColor", {Title = "方框顏色", Default = Color3.fromRGB(255,255,255)}):OnChanged(function(v) Settings.BoxColor = v end)
    ColorsSection:AddColorpicker("TracerColor", {Title = "追蹤線顏色", Default = Color3.fromRGB(255,255,255)}):OnChanged(function(v) Settings.TracerColor = v end)
    ColorsSection:AddColorpicker("SkeletonColor", {Title = "骨骼顏色", Default = Color3.fromRGB(255,255,255)}):OnChanged(function(v) Settings.SkeletonColor = v end)
    ColorsSection:AddColorpicker("ChamsFillColor", {Title = "高亮顏色", Default = Color3.fromRGB(255,0,0)}):OnChanged(function(v) Settings.ChamsFillColor = v end)
    ColorsSection:AddColorpicker("FOVColor", {Title = "FOV圈顏色", Default = Color3.fromRGB(255,0,0)}):OnChanged(function(v) Settings.FOVColor = v end)

    local GeneralSection = Tabs.Settings:AddSection("通用設定")
    GeneralSection:AddSlider("MaxDistance", {Title = "最大距離", Min=100, Max=5000, Default=1000, Rounding=0}):OnChanged(function(v) Settings.MaxDistance = v end)
end

-- Config Tab
do
    SaveManager:SetLibrary(Fluent)
    InterfaceManager:SetLibrary(Fluent)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({})
    InterfaceManager:SetFolder("WAUniversalESP")
    SaveManager:SetFolder("WAUniversalESP/configs")
    
    InterfaceManager:BuildInterfaceSection(Tabs.Config)
    SaveManager:BuildConfigSection(Tabs.Config)
    
    local UnloadSection = Tabs.Config:AddSection("卸載")
    UnloadSection:AddButton({
        Title = "卸載腳本",
        Description = "完全移除",
        Callback = function()
            for _, plr in Players:GetPlayers() do RemoveESP(plr) end
            FOVCircle:Remove()
            Window:Destroy()
        end
    })
end

Fluent:Notify({Title = "WA 透視+自瞄", Content = "載入成功！自瞄已升級：更快 + 鎖最近目標", Duration = 6})
Window:SelectTab(1)