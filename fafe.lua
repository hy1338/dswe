--[[
    Roblox Visual Script - Acrylic Pure Edition
    Features:
      - Acrylic Pure 风格 UI (毛玻璃/亚克力透明质感)
      - Feature Interface 面板 (功能开关列表)
      - 3D 信息卡片 (BillboardGui)
      - 移动残影效果 (Afterimage Trail)
    
    放置位置: StarterPlayerScripts 或 StarterGui (LocalScript)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

---------------------------------------------------------------------------
-- 配置
---------------------------------------------------------------------------
local CONFIG = {
    -- 残影配置
    Afterimage = {
        Enabled = true,
        TrailLength = 12,          -- 残影数量
        FadeTime = 0.6,            -- 残影消散时间(秒)
        SpawnInterval = 0.04,      -- 残影生成间隔(秒)
        TransparencyMax = 0.85,    -- 最大透明度
        Color = Color3.fromRGB(120, 180, 255), -- 残影色调
    },

    -- 3D信息卡片配置
    InfoCard = {
        Enabled = true,
        ShowOnSelf = true,         -- 在自己角色上显示
        ShowOnOthers = true,       -- 在其他玩家角色上显示
        Distance = 50,             -- 最大显示距离
    },

    -- UI配置
    UI = {
        AccentColor = Color3.fromRGB(100, 160, 255),
        BackgroundColor = Color3.fromRGB(20, 22, 30),
        CardColor = Color3.fromRGB(30, 34, 48),
        TextColor = Color3.fromRGB(230, 235, 255),
        SubTextColor = Color3.fromRGB(160, 170, 200),
        BorderColor = Color3.fromRGB(60, 70, 100),
        SuccessColor = Color3.fromRGB(80, 220, 160),
        DangerColor = Color3.fromRGB(255, 90, 90),
        CornerRadius = UDim.new(0, 12),
        BlurSize = 24,
    },
}

---------------------------------------------------------------------------
-- Acrylic Pure 风格工具函数
---------------------------------------------------------------------------
local AcrylicPure = {}

function AcrylicPure.CreateBlur(name, size, parent)
    local blur = Instance.new("BlurEffect")
    blur.Name = name or "AcrylicBlur"
    blur.Size = size or CONFIG.UI.BlurSize
    blur.Enabled = true
    blur.Parent = parent or Lighting
    return blur
end

function AcrylicPure.ApplyAcrylicFrame(frame, opts)
    opts = opts or {}
    local bgColor = opts.BackgroundColor or CONFIG.UI.CardColor
    local bgTransparency = opts.Transparency or 0.15
    local cornerRadius = opts.CornerRadius or CONFIG.UI.CornerRadius
    local borderColor = opts.BorderColor or CONFIG.UI.BorderColor

    frame.BackgroundColor3 = bgColor
    frame.BackgroundTransparency = bgTransparency
    frame.BorderSizePixel = 0

    local corner = Instance.new("UICorner")
    corner.CornerRadius = cornerRadius
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = borderColor
    stroke.Thickness = 1
    stroke.Transparency = 0.4
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame

    return frame
end

function AcrylicPure.CreateGlow(parent, color, size)
    local glow = Instance.new("ImageLabel")
    glow.Name = "Glow"
    glow.Size = UDim2.fromOffset(size or 200, size or 200)
    glow.Position = UDim2.fromScale(0.5, 0.5)
    glow.AnchorPoint = Vector2.new(0.5, 0.5)
    glow.BackgroundTransparency = 1
    glow.Image = "rbxassetid://7669168585"
    glow.ImageColor3 = color or CONFIG.UI.AccentColor
    glow.ImageTransparency = 0.6
    glow.ScaleType = Enum.ScaleType.Slice
    glow.SliceCenter = Rect.new(40, 40, 360, 360)
    glow.ZIndex = 0
    glow.Parent = parent
    return glow
end

function AcrylicPure.CreateAccentLine(parent, position, size)
    local line = Instance.new("Frame")
    line.Name = "AccentLine"
    line.Size = size or UDim2.new(1, -24, 0, 1)
    line.Position = position or UDim2.new(0, 12, 0, 48)
    line.BackgroundColor3 = CONFIG.UI.AccentColor
    line.BackgroundTransparency = 0.3
    line.BorderSizePixel = 0
    line.Parent = parent

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, CONFIG.UI.AccentColor),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 120, 255)),
        ColorSequenceKeypoint.new(1, CONFIG.UI.AccentColor),
    })
    grad.Transparency = ColorSequence.new({
        ColorSequenceKeypoint.new(0, 0.7),
        ColorSequenceKeypoint.new(0.5, 0),
        ColorSequenceKeypoint.new(1, 0.7),
    })
    grad.Parent = line

    return line
end

---------------------------------------------------------------------------
-- Feature Interface 面板
---------------------------------------------------------------------------
local FeatureInterface = {}
FeatureInterface.Features = {}
FeatureInterface.Connections = {}

function FeatureInterface:Register(name, defaultState, callback)
    self.Features[name] = {
        State = defaultState,
        Callback = callback,
    }
end

function FeatureInterface:Set(name, state)
    local feature = self.Features[name]
    if feature then
        feature.State = state
        if feature.Callback then
            feature.Callback(state)
        end
    end
end

function FeatureInterface:Get(name)
    local feature = self.Features[name]
    return feature and feature.State
end

function FeatureInterface:Toggle(name)
    local feature = self.Features[name]
    if feature then
        self:Set(name, not feature.State)
        return not feature.State
    end
    return nil
end

---------------------------------------------------------------------------
-- 残影系统
---------------------------------------------------------------------------
local AfterimageSystem = {
    pool = {},
    active = {},
    lastSpawn = 0,
    connections = {},
}

function AfterimageSystem:CreateGhost(position, cframe)
    local ghost = Instance.new("Part")
    ghost.Name = "Afterimage"
    ghost.Size = Vector3.new(2, 2, 1)
    ghost.CFrame = cframe
    ghost.Anchored = true
    ghost.CanCollide = false
    ghost.CastShadow = false
    ghost.Material = Enum.Material.ForceField
    ghost.Color = CONFIG.Afterimage.Color
    ghost.Transparency = 0.3
    ghost.Shape = Enum.PartType.Block

    -- 残影网格效果
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = "rbxassetid://43137890"
    mesh.Scale = Vector3.new(2.5, 2.5, 2.5)
    mesh.Parent = ghost

    -- 发光效果
    local light = Instance.new("PointLight")
    light.Color = CONFIG.Afterimage.Color
    light.Brightness = 0.5
    light.Range = 6
    light.Parent = ghost

    ghost.Parent = workspace

    -- 淡出动画
    local tweenInfo = TweenInfo.new(
        CONFIG.Afterimage.FadeTime,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    local tween = TweenService:Create(ghost, tweenInfo, {
        Transparency = CONFIG.Afterimage.TransparencyMax,
        Size = Vector3.new(1.8, 1.8, 0.8),
    })
    tween:Play()

    local lightTween = TweenService:Create(light, tweenInfo, {
        Brightness = 0,
        Range = 0,
    })
    lightTween:Play()

    tween.Completed:Connect(function()
        ghost:Destroy()
    end)

    table.insert(self.active, ghost)
end

function AfterimageSystem:Update()
    if not CONFIG.Afterimage.Enabled then return end
    if not rootPart or not rootPart.Parent then return end

    local now = tick()
    local velocity = rootPart.AssemblyLinearVelocity
    local speed = velocity.Magnitude

    -- 只在移动时生成残影
    if speed > 4 and (now - self.lastSpawn) >= CONFIG.Afterimage.SpawnInterval then
        self:CreateGhost(rootPart.Position, rootPart.CFrame)
        self.lastSpawn = now

        -- 限制残影数量
        while #self.active > CONFIG.Afterimage.TrailLength do
            local old = table.remove(self.active, 1)
            if old and old.Parent then
                old:Destroy()
            end
        end
    end
end

function AfterimageSystem:Start()
    table.insert(self.connections,
        RunService.Heartbeat:Connect(function()
            self:Update()
        end)
    )
end

function AfterimageSystem:Stop()
    for _, conn in ipairs(self.connections) do
        conn:Disconnect()
    end
    self.connections = {}
    for _, ghost in ipairs(self.active) do
        if ghost and ghost.Parent then
            ghost:Destroy()
        end
    end
    self.active = {}
end

---------------------------------------------------------------------------
-- 3D 信息卡片系统
---------------------------------------------------------------------------
local InfoCardSystem = {
    cards = {},
    connections = {},
}

function InfoCardSystem:CreateCard(adornee, title, data)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "InfoCard3D"
    billboard.Adornee = adornee
    billboard.Size = UDim2.new(0, 220, 0, 140)
    billboard.StudsOffset = Vector3.new(0, 4, 0)
    billboard.AlwaysOnTop = false
    billboard.MaxDistance = CONFIG.InfoCard.Distance
    billboard.LightInfluence = 0
    billboard.ClipsDescendants = false

    -- 主卡片容器
    local card = Instance.new("Frame")
    card.Name = "Card"
    card.Size = UDim2.fromScale(1, 1)
    card.BackgroundTransparency = 1
    card.Parent = billboard

    -- 背景面板
    local bg = Instance.new("Frame")
    bg.Name = "Background"
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = CONFIG.UI.CardColor
    bg.BackgroundTransparency = 0.1
    bg.BorderSizePixel = 0
    bg.Parent = card

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 10)
    bgCorner.Parent = bg

    local bgStroke = Instance.new("UIStroke")
    bgStroke.Color = CONFIG.UI.BorderColor
    bgStroke.Thickness = 0.8
    bgStroke.Transparency = 0.3
    bgStroke.Parent = bg

    -- 顶部渐变条
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 3)
    topBar.BackgroundColor3 = CONFIG.UI.AccentColor
    topBar.BorderSizePixel = 0
    topBar.Parent = bg

    local topGrad = Instance.new("UIGradient")
    topGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, CONFIG.UI.AccentColor),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 120, 255)),
    })
    topGrad.Parent = topBar

    -- 标题
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -16, 0, 24)
    titleLabel.Position = UDim2.new(0, 8, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = CONFIG.UI.TextColor
    titleLabel.TextSize = 14
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = bg

    -- 分隔线
    local sep = Instance.new("Frame")
    sep.Name = "Separator"
    sep.Size = UDim2.new(1, -16, 0, 1)
    sep.Position = UDim2.new(0, 8, 0, 36)
    sep.BackgroundColor3 = CONFIG.UI.BorderColor
    sep.BackgroundTransparency = 0.5
    sep.BorderSizePixel = 0
    sep.Parent = bg

    -- 数据区域
    local dataFrame = Instance.new("Frame")
    dataFrame.Name = "DataFrame"
    dataFrame.Size = UDim2.new(1, -16, 1, -50)
    dataFrame.Position = UDim2.new(0, 8, 0, 42)
    dataFrame.BackgroundTransparency = 1
    dataFrame.Parent = bg

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 4)
    listLayout.Parent = dataFrame

    -- 填充数据
    for key, value in pairs(data) do
        local row = Instance.new("Frame")
        row.Name = "Row_" .. key
        row.Size = UDim2.new(1, 0, 0, 18)
        row.BackgroundTransparency = 1
        row.Parent = dataFrame

        local keyLabel = Instance.new("TextLabel")
        keyLabel.Size = UDim2.new(0.45, 0, 1, 0)
        keyLabel.BackgroundTransparency = 1
        keyLabel.Text = key
        keyLabel.TextColor3 = CONFIG.UI.SubTextColor
        keyLabel.TextSize = 11
        keyLabel.Font = Enum.Font.Gotham
        keyLabel.TextXAlignment = Enum.TextXAlignment.Left
        keyLabel.Parent = row

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Name = "Value"
        valueLabel.Size = UDim2.new(0.55, -4, 1, 0)
        valueLabel.Position = UDim2.new(0.45, 4, 0, 0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Text = tostring(value)
        valueLabel.TextColor3 = CONFIG.UI.TextColor
        valueLabel.TextSize = 11
        valueLabel.Font = Enum.Font.GothamMedium
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right
        valueLabel.Parent = row
    end

    -- 浮动动画
    local floatTween = TweenService:Create(billboard, TweenInfo.new(
        2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true
    ), {
        StudsOffset = Vector3.new(0, 4.3, 0)
    })
    floatTween:Play()

    billboard.Parent = adornee
    return billboard
end

function InfoCardSystem:CreatePlayerCard(targetPlayer)
    local targetChar = targetPlayer.Character
    if not targetChar then return end
    local head = targetChar:FindFirstChild("Head")
    if not head then return end

    local title = targetPlayer.DisplayName
    local data = {
        ["用户名"] = "@" .. targetPlayer.Name,
        ["生命值"] = "100",
        ["速度"] = "16",
        ["距离"] = "0",
    }

    local card = self:CreateCard(head, title, data)
    card.Name = "InfoCard_" .. targetPlayer.UserId

    -- 实时更新数据
    spawn(function()
        while card and card.Parent do
            local hrp = targetChar:FindFirstChild("HumanoidRootPart")
            local hum = targetChar:FindFirstChild("Humanoid")
            local myHrp = character:FindFirstChild("HumanoidRootPart")

            if hrp and hum and myHrp then
                local dist = math.floor((hrp.Position - myHrp.Position).Magnitude)
                local health = math.floor(hum.Health)
                local speed = math.floor(hum.WalkSpeed)

                local dataFrame = card:FindFirstChild("Card", true)
                    and card.Card:FindFirstChild("Background")
                    and card.Card.Background:FindFirstChild("DataFrame")

                if dataFrame then
                    local healthRow = dataFrame:FindFirstChild("Row_生命值")
                    if healthRow then
                        local val = healthRow:FindFirstChild("Value")
                        if val then val.Text = tostring(health) end
                    end
                    local speedRow = dataFrame:FindFirstChild("Row_速度")
                    if speedRow then
                        local val = speedRow:FindFirstChild("Value")
                        if val then val.Text = tostring(speed) end
                    end
                    local distRow = dataFrame:FindFirstChild("Row_距离")
                    if distRow then
                        local val = distRow:FindFirstChild("Value")
                        if val then val.Text = tostring(dist) end
                    end
                end
            end
            RunService.Heartbeat:Wait()
        end
    end)

    self.cards[targetPlayer.UserId] = card
    return card
end

function InfoCardSystem:Start()
    -- 为自己创建卡片
    if CONFIG.InfoCard.ShowOnSelf then
        self:CreatePlayerCard(player)
    end

    -- 为其他玩家创建卡片
    if CONFIG.InfoCard.ShowOnOthers then
        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if otherPlayer ~= player and otherPlayer.Character then
                self:CreatePlayerCard(otherPlayer)
            end
        end

        table.insert(self.connections,
            Players.PlayerAdded:Connect(function(newPlayer)
                newPlayer.CharacterAdded:Connect(function()
                    task.wait(1)
                    self:CreatePlayerCard(newPlayer)
                end)
            end)
        )
    end
end

function InfoCardSystem:Stop()
    for _, conn in ipairs(self.connections) do
        conn:Disconnect()
    end
    for _, card in pairs(self.cards) do
        if card and card.Parent then
            card:Destroy()
        end
    end
    self.cards = {}
    self.connections = {}
end

---------------------------------------------------------------------------
-- 主 UI 构建
---------------------------------------------------------------------------
local function BuildMainUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AcrylicPureUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true

    -- 全局模糊效果(仅用于UI)
    local uiBlur = Instance.new("BlurEffect")
    uiBlur.Name = "UIBlur"
    uiBlur.Size = 0
    uiBlur.Enabled = true
    uiBlur.Parent = Lighting

    -----------------------------------------------------------------------
    -- 侧边栏面板
    -----------------------------------------------------------------------
    local panel = Instance.new("Frame")
    panel.Name = "SidePanel"
    panel.Size = UDim2.new(0, 300, 0, 480)
    panel.Position = UDim2.new(0, 20, 0.5, -240)
    panel.BackgroundColor3 = CONFIG.UI.BackgroundColor
    panel.BackgroundTransparency = 0.08
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.Parent = screenGui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = CONFIG.UI.CornerRadius
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = CONFIG.UI.BorderColor
    panelStroke.Thickness = 1
    panelStroke.Transparency = 0.3
    panelStroke.Parent = panel

    -- 面板发光
    AcrylicPure.CreateGlow(panel, CONFIG.UI.AccentColor, 350)

    -- 顶部标题区域
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 56)
    header.BackgroundTransparency = 1
    header.Parent = panel

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.fromOffset(28, 28)
    icon.Position = UDim2.new(0, 16, 0.5, -14)
    icon.BackgroundTransparency = 1
    icon.Image = "rbxassetid://7734039701"
    icon.ImageColor3 = CONFIG.UI.AccentColor
    icon.Parent = header

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -60, 0, 20)
    title.Position = UDim2.new(0, 50, 0.5, -10)
    title.BackgroundTransparency = 1
    title.Text = "VISUAL HUB"
    title.TextColor3 = CONFIG.UI.TextColor
    title.TextSize = 16
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.Size = UDim2.new(1, -60, 0, 14)
    subtitle.Position = UDim2.new(0, 50, 0.5, 6)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "Acrylic Pure Edition"
    subtitle.TextColor3 = CONFIG.UI.SubTextColor
    subtitle.TextSize = 11
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = header

    -- 渐变分隔线
    AcrylicPure.CreateAccentLine(panel, UDim2.new(0, 12, 0, 56), UDim2.new(1, -24, 0, 1))

    -----------------------------------------------------------------------
    -- 功能列表区域
    -----------------------------------------------------------------------
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "FeatureList"
    scrollFrame.Size = UDim2.new(1, -16, 1, -80)
    scrollFrame.Position = UDim2.new(0, 8, 0, 68)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.ScrollBarThickness = 3
    scrollFrame.ScrollBarImageColor3 = CONFIG.UI.AccentColor
    scrollFrame.ScrollBarImageTransparency = 0.5
    scrollFrame.BorderSizePixel = 0
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollFrame.Parent = panel

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 6)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = scrollFrame

    local listPadding = Instance.new("UIPadding")
    listPadding.PaddingLeft = UDim.new(0, 4)
    listPadding.PaddingRight = UDim.new(0, 4)
    listPadding.PaddingTop = UDim.new(0, 4)
    listPadding.Parent = scrollFrame

    -----------------------------------------------------------------------
    -- 创建功能开关卡片
    -----------------------------------------------------------------------
    local function CreateFeatureCard(featureName, description, defaultState, order)
        local card = Instance.new("Frame")
        card.Name = "Feature_" .. featureName
        card.Size = UDim2.new(1, 0, 0, 52)
        card.BackgroundColor3 = CONFIG.UI.CardColor
        card.BackgroundTransparency = 0.2
        card.BorderSizePixel = 0
        card.LayoutOrder = order or 0
        card.Parent = scrollFrame

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, 8)
        cardCorner.Parent = card

        local cardStroke = Instance.new("UIStroke")
        cardStroke.Color = CONFIG.UI.BorderColor
        cardStroke.Thickness = 0.5
        cardStroke.Transparency = 0.5
        cardStroke.Parent = card

        -- 功能名称
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -80, 0, 16)
        nameLabel.Position = UDim2.new(0, 12, 0, 8)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = featureName
        nameLabel.TextColor3 = CONFIG.UI.TextColor
        nameLabel.TextSize = 13
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = card

        -- 描述
        local descLabel = Instance.new("TextLabel")
        descLabel.Size = UDim2.new(1, -80, 0, 14)
        descLabel.Position = UDim2.new(0, 12, 0, 28)
        descLabel.BackgroundTransparency = 1
        descLabel.Text = description
        descLabel.TextColor3 = CONFIG.UI.SubTextColor
        descLabel.TextSize = 10
        descLabel.Font = Enum.Font.Gotham
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.Parent = card

        -- 开关按钮
        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Name = "Toggle"
        toggleBtn.Size = UDim2.fromOffset(44, 24)
        toggleBtn.Position = UDim2.new(1, -56, 0.5, -12)
        toggleBtn.BackgroundColor3 = defaultState and CONFIG.UI.SuccessColor or CONFIG.UI.BorderColor
        toggleBtn.BackgroundTransparency = 0.2
        toggleBtn.Text = ""
        toggleBtn.BorderSizePixel = 0
        toggleBtn.AutoButtonColor = false
        toggleBtn.Parent = card

        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(1, 0)
        toggleCorner.Parent = toggleBtn

        -- 开关圆点
        local knob = Instance.new("Frame")
        knob.Name = "Knob"
        knob.Size = UDim2.fromOffset(18, 18)
        knob.Position = defaultState and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel = 0
        knob.Parent = toggleBtn

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = knob

        -- 状态指示灯
        local indicator = Instance.new("Frame")
        indicator.Name = "Indicator"
        indicator.Size = UDim2.fromOffset(6, 6)
        indicator.Position = UDim2.new(0, 3, 0, 3)
        indicator.BackgroundColor3 = defaultState and CONFIG.UI.SuccessColor or CONFIG.UI.DangerColor
        indicator.BorderSizePixel = 0
        indicator.Parent = card

        local indCorner = Instance.new("UICorner")
        indCorner.CornerRadius = UDim.new(1, 0)
        indCorner.Parent = indicator

        -- 开关交互
        local isOn = defaultState
        toggleBtn.MouseButton1Click:Connect(function()
            isOn = not isOn

            -- 动画切换
            local targetPos = isOn and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
            local targetColor = isOn and CONFIG.UI.SuccessColor or CONFIG.UI.BorderColor

            TweenService:Create(knob, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
                Position = targetPos
            }):Play()

            TweenService:Create(toggleBtn, TweenInfo.new(0.25), {
                BackgroundColor3 = targetColor
            }):Play()

            TweenService:Create(indicator, TweenInfo.new(0.25), {
                BackgroundColor3 = isOn and CONFIG.UI.SuccessColor or CONFIG.UI.DangerColor
            }):Play()

            -- 触发功能回调
            FeatureInterface:Toggle(featureName)
        end)

        return card
    end

    -----------------------------------------------------------------------
    -- 注册所有功能
    -----------------------------------------------------------------------
    FeatureInterface:Register("移动残影", CONFIG.Afterimage.Enabled, function(state)
        CONFIG.Afterimage.Enabled = state
        if state then
            AfterimageSystem:Start()
        else
            AfterimageSystem:Stop()
        end
    end)

    FeatureInterface:Register("3D信息卡片", CONFIG.InfoCard.Enabled, function(state)
        CONFIG.InfoCard.Enabled = state
        if state then
            InfoCardSystem:Start()
        else
            InfoCardSystem:Stop()
        end
    end)

    FeatureInterface:Register("高亮玩家", false, function(state)
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then
                local highlight = p.Character:FindFirstChild("Highlight")
                if state then
                    if not highlight then
                        highlight = Instance.new("Highlight")
                        highlight.Name = "Highlight"
                        highlight.FillColor = CONFIG.UI.AccentColor
                        highlight.FillTransparency = 0.7
                        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                        highlight.OutlineTransparency = 0.3
                        highlight.Parent = p.Character
                    end
                else
                    if highlight then
                        highlight:Destroy()
                    end
                end
            end
        end
    end)

    FeatureInterface:Register("ESP线框", false, function(state)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and p.Character then
                local espBox = p.Character:FindFirstChild("ESPBox")
                if state then
                    if not espBox then
                        local box = Instance.new("BoxHandleAdornment")
                        box.Name = "ESPBox"
                        box.Adornee = p.Character
                        box.Size = Vector3.new(4, 5.5, 4)
                        box.Color3 = CONFIG.UI.AccentColor
                        box.Transparency = 0.6
                        box.AlwaysOnTop = true
                        box.ZIndex = 10
                        box.Parent = p.Character
                    end
                else
                    if espBox then
                        espBox:Destroy()
                    end
                end
            end
        end
    end)

    FeatureInterface:Register("全屏模糊", false, function(state)
        uiBlur.Size = state and 20 or 0
    end)

    FeatureInterface:Register("FPS显示", false, function(state)
        local fpsLabel = screenGui:FindFirstChild("FPSLabel")
        if state then
            if not fpsLabel then
                fpsLabel = Instance.new("TextLabel")
                fpsLabel.Name = "FPSLabel"
                fpsLabel.Size = UDim2.new(0, 100, 0, 30)
                fpsLabel.Position = UDim2.new(1, -120, 0, 10)
                fpsLabel.BackgroundColor3 = CONFIG.UI.CardColor
                fpsLabel.BackgroundTransparency = 0.2
                fpsLabel.TextColor3 = CONFIG.UI.SuccessColor
                fpsLabel.TextSize = 14
                fpsLabel.Font = Enum.Font.GothamBold
                fpsLabel.BorderSizePixel = 0
                fpsLabel.Parent = screenGui

                local fpsCorner = Instance.new("UICorner")
                fpsCorner.CornerRadius = UDim.new(0, 8)
                fpsCorner.Parent = fpsLabel

                local fpsStroke = Instance.new("UIStroke")
                fpsStroke.Color = CONFIG.UI.BorderColor
                fpsStroke.Thickness = 0.5
                fpsStroke.Transparency = 0.5
                fpsStroke.Parent = fpsLabel

                spawn(function()
                    local lastTick = tick()
                    local frames = 0
                    while fpsLabel and fpsLabel.Parent do
                        frames = frames + 1
                        if tick() - lastTick >= 1 then
                            fpsLabel.Text = "FPS: " .. tostring(frames)
                            frames = 0
                            lastTick = tick()
                        end
                        RunService.Heartbeat:Wait()
                    end
                end)
            end
        else
            if fpsLabel then
                fpsLabel:Destroy()
            end
        end
    end)

    -----------------------------------------------------------------------
    -- 创建功能卡片
    -----------------------------------------------------------------------
    CreateFeatureCard("移动残影", "移动时产生残影拖尾效果", CONFIG.Afterimage.Enabled, 1)
    CreateFeatureCard("3D信息卡片", "在角色头顶显示3D悬浮信息卡", CONFIG.InfoCard.Enabled, 2)
    CreateFeatureCard("高亮玩家", "为所有玩家添加高亮轮廓", false, 3)
    CreateFeatureCard("ESP线框", "显示其他玩家的ESP方框", false, 4)
    CreateFeatureCard("全屏模糊", "启用全屏模糊效果", false, 5)
    CreateFeatureCard("FPS显示", "显示实时帧率", false, 6)

    -----------------------------------------------------------------------
    -- 底部状态栏
    -----------------------------------------------------------------------
    local footer = Instance.new("Frame")
    footer.Name = "Footer"
    footer.Size = UDim2.new(1, 0, 0, 32)
    footer.Position = UDim2.new(0, 0, 1, -32)
    footer.BackgroundColor3 = CONFIG.UI.BackgroundColor
    footer.BackgroundTransparency = 0.3
    footer.BorderSizePixel = 0
    footer.Parent = panel

    local footerCorner = Instance.new("UICorner")
    footerCorner.CornerRadius = UDim.new(0, 0)
    footerCorner.Parent = footer

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -16, 1, 0)
    statusLabel.Position = UDim2.new(0, 8, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "● 已连接 | " .. Players:GetPlayers()[1].Name
    statusLabel.TextColor3 = CONFIG.UI.SuccessColor
    statusLabel.TextSize = 10
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = footer

    -----------------------------------------------------------------------
    -- 面板拖拽功能
    -----------------------------------------------------------------------
    local dragging = false
    local dragStart, startPos

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = panel.Position
        end
    end)

    header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    -----------------------------------------------------------------------
    -- 快捷键: RightCtrl 切换面板显隐
    -----------------------------------------------------------------------
    local panelVisible = true
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.RightControl then
            panelVisible = not panelVisible
            local targetSize = panelVisible and UDim2.new(0, 300, 0, 480) or UDim2.new(0, 300, 0, 0)
            local targetTrans = panelVisible and 0.08 or 1
            TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
                Size = targetSize,
                BackgroundTransparency = targetTrans,
            }):Play()
        end
    end)

    -----------------------------------------------------------------------
    -- 面板入场动画
    -----------------------------------------------------------------------
    panel.Size = UDim2.new(0, 300, 0, 0)
    panel.BackgroundTransparency = 1
    panel.ClipsDescendants = true

    task.wait(0.5)
    TweenService:Create(panel, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 300, 0, 480),
        BackgroundTransparency = 0.08,
    }):Play()

    screenGui.Parent = player:WaitForChild("PlayerGui")
    return screenGui
end

---------------------------------------------------------------------------
-- 角色重生处理
---------------------------------------------------------------------------
player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid = newChar:WaitForChild("Humanoid")
    rootPart = newChar:WaitForChild("HumanoidRootPart")

    -- 重新启动残影系统
    if CONFIG.Afterimage.Enabled then
        AfterimageSystem:Stop()
        AfterimageSystem:Start()
    end

    -- 重新创建自己的信息卡片
    if CONFIG.InfoCard.Enabled and CONFIG.InfoCard.ShowOnSelf then
        task.wait(1)
        InfoCardSystem:CreatePlayerCard(player)
    end
end)

---------------------------------------------------------------------------
-- 启动
---------------------------------------------------------------------------
local mainUI = BuildMainUI()

-- 启动默认开启的功能
if CONFIG.Afterimage.Enabled then
    AfterimageSystem:Start()
end

if CONFIG.InfoCard.Enabled then
    InfoCardSystem:Start()
end

print("[Acrylic Pure] 视觉脚本已加载")
