-- ESP Module
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer
local LocalCharacter = LocalPlayer and LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local LocalHumanoidRootPart = LocalCharacter:WaitForChild("HumanoidRootPart")

local ESP = {}
ESP.__index = ESP

-- 配置顏色與功能開關
local Config = {
    ShowESP = true,
    ShowBox = true,
    ShowHealth = true,
    ShowTracer = true,
    ShowSkeleton = true,
    ShowTool = true,
    ShowName = true,     -- <--- 新增：角色名稱開關
    ShowDistance = true, -- <--- 新增：距離開關
    BoxColor = Color3.fromRGB(255,255,255),
    TracerColor = Color3.fromRGB(255,255,255),
    SkeletonColor = Color3.fromRGB(255,255,255),
    MenuColor = Color3.fromRGB(28, 14, 46) 
}

-- 新增主題顏色配置，以匹配圖片風格
local AccentColor = Color3.fromRGB(223, 27, 85) 
local OutlineColor = Color3.fromRGB(56, 42, 80) 
local FontColor = Color3.fromRGB(255, 255, 255) 

function ESP.new()
    local self = setmetatable({}, ESP)
    self.espCache = {}
    return self
end

function ESP:createDrawing(type, properties)
    local drawing = Drawing.new(type)
    for prop, val in pairs(properties) do
        drawing[prop] = val
    end
    return drawing
end

function ESP:createComponents()
    return {
        Box = self:createDrawing("Square",{Thickness=1,Transparency=1,Color=Config.BoxColor,Filled=false}),
        Tracer = self:createDrawing("Line",{Thickness=1,Transparency=1,Color=Config.TracerColor}),
        DistanceLabel = self:createDrawing("Text",{Size=18,Center=true,Outline=true,Color=Color3.fromRGB(255,255,255),OutlineColor=Color3.fromRGB(0,0,0)}),
        NameLabel = self:createDrawing("Text",{Size=18,Center=true,Outline=true,Color=Color3.fromRGB(255,255,255),OutlineColor=Color3.fromRGB(0,0,0)}),
        HealthBar = {
            Outline = self:createDrawing("Square",{Thickness=1,Transparency=1,Color=Color3.fromRGB(0,0,0),Filled=false}),
            Health = self:createDrawing("Square",{Thickness=1,Transparency=1,Color=Color3.fromRGB(0,255,0),Filled=true})
        },
        ItemLabel = self:createDrawing("Text",{Size=18,Center=true,Outline=true,Color=Color3.fromRGB(255,255,255),OutlineColor=Color3.fromRGB(0,0,0)}),
        SkeletonLines = {}
    }
end

local bodyConnections = {
    R15 = {{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"LowerTorso","LeftUpperLeg"},{"LowerTorso","RightUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},{"UpperTorso","LeftUpperArm"},{"UpperTorso","RightUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"}},
    R6 = {{"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"}}
}

function ESP:updateComponents(components, character, player)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChild("Humanoid")
    if hrp and humanoid then
        local hrpPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
        
        -- 名稱與距離的基本可見性（受 ShowESP 總開關影響）
        components.NameLabel.Visible = onScreen and Config.ShowESP and Config.ShowName
        components.DistanceLabel.Visible = onScreen and Config.ShowESP and Config.ShowDistance

        if onScreen then
            local screenWidth, screenHeight = Camera.ViewportSize.X, Camera.ViewportSize.Y
            local factor = 1 / (hrpPos.Z * math.tan(math.rad(Camera.FieldOfView*0.5)) * 2) * 100
            local width, height = math.floor(screenHeight/25*factor), math.floor(screenWidth/27*factor)
            local distance = math.floor((LocalHumanoidRootPart.Position - hrp.Position).magnitude)

            -- Box
            if Config.ShowBox and Config.ShowESP then
                components.Box.Size = Vector2.new(width,height)
                components.Box.Position = Vector2.new(hrpPos.X-width/2,hrpPos.Y-height/2)
                components.Box.Color = Config.BoxColor
                components.Box.Visible = true
            else
                components.Box.Visible = false
            end

            -- Tracer
            if Config.ShowTracer and Config.ShowESP then
                components.Tracer.From = Vector2.new(screenWidth/2,screenHeight)
                components.Tracer.To = Vector2.new(hrpPos.X,hrpPos.Y+height/2)
                components.Tracer.Color = Config.TracerColor
                components.Tracer.Visible = true
            else
                components.Tracer.Visible = false
            end

            -- Name & Distance（各自獨立開關控制）
            if Config.ShowName and Config.ShowESP then
                components.NameLabel.Text = "["..player.Name.."]"
                components.NameLabel.Position = Vector2.new(hrpPos.X,hrpPos.Y-height/2-15)
                components.NameLabel.Visible = true
            else
                components.NameLabel.Visible = false
            end

            if Config.ShowDistance and Config.ShowESP then
                components.DistanceLabel.Text = "["..distance.."M]"
                components.DistanceLabel.Position = Vector2.new(hrpPos.X,hrpPos.Y+height/2+15)
                components.DistanceLabel.Visible = true
            else
                components.DistanceLabel.Visible = false
            end

            -- Health
            if Config.ShowHealth and Config.ShowESP then
                local hbHeight,hbWidth = height,5
                local hf = humanoid.Health/humanoid.MaxHealth
                components.HealthBar.Outline.Size = Vector2.new(hbWidth,hbHeight)
                components.HealthBar.Outline.Position = Vector2.new(components.Box.Position.X-hbWidth-2,components.Box.Position.Y)
                components.HealthBar.Outline.Visible = true
                components.HealthBar.Health.Size = Vector2.new(hbWidth-2,hbHeight*hf)
                components.HealthBar.Health.Position = Vector2.new(components.HealthBar.Outline.Position.X+1,components.HealthBar.Outline.Position.Y+hbHeight*(1-hf))
                components.HealthBar.Health.Visible = true
            else
                components.HealthBar.Outline.Visible = false
                components.HealthBar.Health.Visible = false
            end

            -- Tool
            if Config.ShowTool and Config.ShowESP then
                local backpack = player.Backpack
                local tool = backpack:FindFirstChildOfClass("Tool") or character:FindFirstChildOfClass("Tool")
                if tool then
                    components.ItemLabel.Text = "[持有: "..tool.Name.."]"
                else
                    components.ItemLabel.Text = "[持有: 無]"
                end
                components.ItemLabel.Position = Vector2.new(hrpPos.X,hrpPos.Y+height/2+35)
                components.ItemLabel.Visible = true
            else
                components.ItemLabel.Visible = false
            end

            -- Skeleton
            if Config.ShowSkeleton and Config.ShowESP then
                local conns = bodyConnections[humanoid.RigType.Name] or {}
                for _,c in ipairs(conns) do
                    local a,b = character:FindFirstChild(c[1]),character:FindFirstChild(c[2])
                    if a and b then
                        local line = components.SkeletonLines[c[1].."-"..c[2]] or ESP:createDrawing("Line",{Thickness=1,Color=Config.SkeletonColor})
                        local posA,onA = Camera:WorldToViewportPoint(a.Position)
                        local posB,onB = Camera:WorldToViewportPoint(b.Position)
                        if onA and onB then
                            line.From = Vector2.new(posA.X,posA.Y)
                            line.To = Vector2.new(posB.X,posB.Y)
                            line.Color = Config.SkeletonColor
                            line.Visible = true
                            components.SkeletonLines[c[1].."-"..c[2]] = line
                        else
                            line.Visible = false
                        end
                    end
                end
            else
                for _,line in pairs(components.SkeletonLines) do line.Visible=false end 
            end
        else
            self:hideComponents(components)
        end
    else
        self:hideComponents(components)
    end
end

function ESP:hideComponents(components)
    components.Box.Visible = false
    components.Tracer.Visible = false
    components.DistanceLabel.Visible = false
    components.NameLabel.Visible = false
    components.HealthBar.Outline.Visible = false
    components.HealthBar.Health.Visible = false
    components.ItemLabel.Visible = false
    for _,line in pairs(components.SkeletonLines) do line.Visible=false end
end

function ESP:removeEsp(player)
    local comps = self.espCache[player]
    if comps then
        comps.Box:Remove()
        comps.Tracer:Remove()
        comps.DistanceLabel:Remove()
        comps.NameLabel:Remove()
        comps.HealthBar.Outline:Remove()
        comps.HealthBar.Health:Remove()
        comps.ItemLabel:Remove()
        for _,line in pairs(comps.SkeletonLines) do line:Remove() end
        self.espCache[player]=nil
    end
end

local espInstance = ESP.new()
RunService.RenderStepped:Connect(function()
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer then
            local char = p.Character
            if char then
                if not espInstance.espCache[p] then
                    espInstance.espCache[p] = espInstance:createComponents()
                end
                espInstance:updateComponents(espInstance.espCache[p],char,p)
            else
                if espInstance.espCache[p] then espInstance:hideComponents(espInstance.espCache[p]) end
            end
        end
    end
end)
Players.PlayerRemoving:Connect(function(p) espInstance:removeEsp(p) end)

-- GUI
local ScreenGui = Instance.new("ScreenGui",game:GetService("CoreGui"))
ScreenGui.ResetOnSpawn = false

-- 懸浮球
local FloatButton = Instance.new("TextButton", ScreenGui)
FloatButton.Size = UDim2.new(0,60,0,60)
FloatButton.Position = UDim2.new(0,20,0,100)
FloatButton.BackgroundColor3 = Color3.fromRGB(0,0,0)
FloatButton.BackgroundTransparency = 0.5
FloatButton.Text = "ESP"
FloatButton.TextColor3 = Color3.fromRGB(255,255,255)
FloatButton.TextScaled = true
FloatButton.ZIndex = 10
FloatButton.Active = true
FloatButton.Draggable = true
FloatButton.Font = Enum.Font.RobotoMono 

-- 菜單
local MenuFrame = Instance.new("Frame", ScreenGui)
MenuFrame.Size = UDim2.new(0,350,0,520) -- 稍微增加高度容納兩個新開關
MenuFrame.Position = UDim2.new(0,100,0,100)
MenuFrame.BackgroundColor3 = Config.MenuColor
MenuFrame.Visible = false
MenuFrame.Active = true
MenuFrame.Draggable = true

-- 菜單標題
local TitleFrame = Instance.new("Frame", MenuFrame)
TitleFrame.Size = UDim2.new(1, 0, 0, 40)
TitleFrame.Position = UDim2.new(0, 0, 0, 0)
TitleFrame.BackgroundColor3 = Config.MenuColor
TitleFrame.BorderSizePixel = 0 

local TitleLabel = Instance.new("TextLabel", TitleFrame)
TitleLabel.Text = "  👁️  ESP"
TitleLabel.Size = UDim2.new(1, 0, 1, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.TextColor3 = FontColor
TitleLabel.TextScaled = true
TitleLabel.Font = Enum.Font.RobotoMono
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

FloatButton.MouseButton1Click:Connect(function()
    MenuFrame.Visible = not MenuFrame.Visible
end)

-- CSS風格開關函數
local function CreateToggle(parent,text,initial,pos,callback)
    local Label = Instance.new("TextLabel",parent)
    Label.Text = text
    Label.Size = UDim2.new(0,200,0,30) 
    Label.Position = pos
    Label.BackgroundTransparency = 1
    Label.TextColor3 = FontColor
    Label.TextScaled = true
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Font = Enum.Font.RobotoMono 

    local SwitchFrame = Instance.new("Frame", parent)
    SwitchFrame.Size = UDim2.new(0, 50, 0, 30)
    SwitchFrame.Position = UDim2.new(1, -60, 0, pos.Y.Offset) 
    SwitchFrame.BackgroundColor3 = initial and AccentColor or OutlineColor 
    SwitchFrame.BorderSizePixel = 0
    SwitchFrame.ClipsDescendants = true 

    local SwitchCircle = Instance.new("Frame", SwitchFrame)
    SwitchCircle.Size = UDim2.new(0, 22, 0, 22)
    SwitchCircle.BackgroundColor3 = FontColor 
    SwitchCircle.BorderSizePixel = 0
    SwitchCircle.ZIndex = 2 
    
    local offPos = UDim2.new(0, 4, 0.5, -11) 
    local onPos = UDim2.new(1, -26, 0.5, -11) 
    SwitchCircle.Position = initial and onPos or offPos
    
    local state = initial

    local function updateSwitch()
        SwitchFrame.BackgroundColor3 = state and AccentColor or OutlineColor
        SwitchCircle:TweenPosition(
            state and onPos or offPos,
            "Out",
            "Linear",
            0.15,
            true
        )
    end

    local Button = Instance.new("TextButton", SwitchFrame) 
    Button.Size = UDim2.new(1,0,1,0)
    Button.BackgroundTransparency = 1
    Button.Text = ""

    Button.MouseButton1Click:Connect(function()
        state = not state
        updateSwitch()
        callback(state)
    end)
    
    updateSwitch()
end

-- 調色盤
local function CreateColorPicker(parent,text,pos,defaultColor,callback)
    local Label = Instance.new("TextLabel",parent)
    Label.Text = text
    Label.Size = UDim2.new(0,200,0,30)
    Label.Position = pos
    Label.BackgroundTransparency = 1
    Label.TextColor3 = FontColor
    Label.TextScaled = true
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Font = Enum.Font.RobotoMono 

    local ColorButton = Instance.new("TextButton",parent)
    ColorButton.Size = UDim2.new(0,30,0,30) 
    ColorButton.Position = UDim2.new(1, -60, 0, pos.Y.Offset) 
    ColorButton.BackgroundColor3 = defaultColor
    ColorButton.BorderSizePixel = 2 
    ColorButton.BorderColor3 = OutlineColor 
    ColorButton.Text = ""
    ColorButton.Font = Enum.Font.RobotoMono 
    
    ColorButton.MouseButton1Click:Connect(function()
        local r = math.random(0,255)
        local g = math.random(0,255)
        local b = math.random(0,255)
        local c = Color3.fromRGB(r,g,b)
        ColorButton.BackgroundColor3 = c
        callback(c)
    end)
end

--------------------------------------------------------------------------------
-- 所有開關（新增「顯示名稱」與「顯示距離」兩個開關）
CreateToggle(MenuFrame,"方框 (Box)",Config.ShowBox,UDim2.new(0,10,0,50),function(v) Config.ShowBox=v end)
CreateToggle(MenuFrame,"血條 (Health)",Config.ShowHealth,UDim2.new(0,10,0,90),function(v) Config.ShowHealth=v end)
CreateToggle(MenuFrame,"射線 (Tracer)",Config.ShowTracer,UDim2.new(0,10,0,130),function(v) Config.ShowTracer=v end)
CreateToggle(MenuFrame,"骨骼 (Skeleton)",Config.ShowSkeleton,UDim2.new(0,10,0,170),function(v) Config.ShowSkeleton=v end)
CreateToggle(MenuFrame,"手持道具 (Tool)",Config.ShowTool,UDim2.new(0,10,0,210),function(v) Config.ShowTool=v end)
CreateToggle(MenuFrame,"顯示名稱 (Name)",Config.ShowName,UDim2.new(0,10,0,250),function(v) Config.ShowName=v end)     -- 新增
CreateToggle(MenuFrame,"顯示距離 (Distance)",Config.ShowDistance,UDim2.new(0,10,0,290),function(v) Config.ShowDistance=v end) -- 新增

-- 調色盤
CreateColorPicker(MenuFrame,"方框顏色 (Box)",UDim2.new(0,10,0,340),Config.BoxColor,function(c) Config.BoxColor=c end)
CreateColorPicker(MenuFrame,"射線顏色 (Tracer)",UDim2.new(0,10,0,380),Config.TracerColor,function(c) Config.TracerColor=c end)
CreateColorPicker(MenuFrame,"骨骼顏色 (Skeleton)",UDim2.new(0,10,0,420),Config.SkeletonColor,function(c) Config.SkeletonColor=c end)
CreateColorPicker(MenuFrame,"菜單顏色 (Menu)",UDim2.new(0,10,0,460),Config.MenuColor,function(c) Config.MenuColor=c;MenuFrame.BackgroundColor3=c end)
