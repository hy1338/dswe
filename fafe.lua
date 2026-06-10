--[[
    Roblox Visual Script - Acrylic Pure Edition v2.1 (Bug Fixed)
    Features:
      - Acrylic Pure 风格 UI (毛玻璃/亚克力透明质感)
      - Feature Interface 面板 (功能开关列表)
      - 3D 信息卡片 (BillboardGui)
      - 移动残影效果 (Trail)
      - 手机端悬浮按钮
    
    修复内容:
      - 修复信息卡片健康值显示错误
      - 修复高亮/ESP对新玩家无效
      - 修复角色重生时的组件获取问题
      - 修复内存泄漏
      - 添加UI边界检查
      - 优化协程安全性
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

---------------------------------------------------------------------------
-- 配置
---------------------------------------------------------------------------
local CONFIG = {
    Afterimage = {
        Enabled = true,
        Lifetime = 0.5,
        Color = Color3.fromRGB(120, 180, 255),
    },

    InfoCard = {
        Enabled = true,
        ShowOnSelf = true,
        ShowOnOthers = true,
        Distance = 50,
    },

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
    },
}

---------------------------------------------------------------------------
-- 安全工具函数
---------------------------------------------------------------------------
local function safeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[Acrylic Pure] " .. tostring(err))
    end
    return ok
end

local function isDescendant(obj, parent)
    return obj and obj:IsDescendantOf(parent)
end

local function clampUdim2(pos, size, screenSize)
    local maxXScale = 1 - size.X.Scale
    local maxYScale = 1 - size.Y.Scale
    local maxXOffset = screenSize.X - size.X.Offset
    local maxYOffset = screenSize.Y - size.Y.Offset
    
    return UDim2.new(
        math.clamp(pos.X.Scale, 0, maxXScale),
        math.clamp(pos.X.Offset, 0, maxXOffset),
        math.clamp(pos.Y.Scale, 0, maxYScale),
        math.clamp(pos.Y.Offset, 0, maxYOffset)
    )
end

---------------------------------------------------------------------------
-- Acrylic Pure 风格工具
---------------------------------------------------------------------------
local AcrylicPure = {}

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
-- Feature Interface
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
            safeCall(feature.Callback, state)
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
        local newState = not feature.State
        self:Set(name, newState)
        return newState
    end
    return nil
end

function FeatureInterface:Cleanup()
    for _, conn in ipairs(self.Connections) do
        safeCall(function() conn:Disconnect() end)
    end
    self.Connections = {}
end

---------------------------------------------------------------------------
-- 残影系统 (Trail)
---------------------------------------------------------------------------
local AfterimageSystem = {
    trail = nil,
    attachment0 = nil,
    attachment1 = nil,
    isActive = false,
}

function AfterimageSystem:Start()
    self:Stop()
    
    if not rootPart or not rootPart.Parent then
        warn("[Afterimage] rootPart not ready")
        return false
    end

    local success = safeCall(function()
        self.attachment0 = Instance.new("Attachment")
        self.attachment0.Name = "TrailTop"
        self.attachment0.Position = Vector3.new(0, 2, 0)
        self.attachment0.Parent = rootPart

        self.attachment1 = Instance.new("Attachment")
        self.attachment1.Name = "TrailBottom"
        self.attachment1.Position = Vector3.new(0, -2, 0)
        self.attachment1.Parent = rootPart

        self.trail = Instance.new("Trail")
        self.trail.Name = "AfterimageTrail"
        self.trail.Attachment0 = self.attachment0
        self.trail.Attachment1 = self.attachment1
        self.trail.Lifetime = CONFIG.Afterimage.Lifetime
        self.trail.MinLength = 0.1
        self.trail.FaceCamera = true
        self.trail.LightEmission = 0.8
        self.trail.LightInfluence = 0
        self.trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(0.5, 0.6),
            NumberSequenceKeypoint.new(1, 1),
        })
        self.trail.WidthScale = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.8, 0.6),
            NumberSequenceKeypoint.new(1, 0),
        })
        self.trail.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, CONFIG.Afterimage.Color),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 120, 255)),
            ColorSequenceKeypoint.new(1, CONFIG.Afterimage.Color),
        })
        self.trail.Enabled = true
        self.trail.Parent = rootPart
        self.isActive = true
    end)
    
    return success
end

function AfterimageSystem:Stop()
    safeCall(function()
        if self.trail then
            self.trail.Enabled = false
            if self.trail.Parent then
                self.trail:Clear()
                self.trail:Destroy()
            end
        end
        if self.attachment0 and self.attachment0.Parent then
            self.attachment0:Destroy()
        end
        if self.attachment1 and self.attachment1.Parent then
            self.attachment1:Destroy()
        end
    end)
    self.trail = nil
    self.attachment0 = nil
    self.attachment1 = nil
    self.isActive = false
end

function AfterimageSystem:Restart()
    if self.isActive then
        self:Stop()
        task.wait(0.1)
        self:Start()
    end
end

---------------------------------------------------------------------------
-- 3D 信息卡片系统
---------------------------------------------------------------------------
local InfoCardSystem = {
    cards = {},
    connections = {},
    playerAddedConn = nil,
    playerRemovingConn = nil,
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

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.Size = UDim2.fromScale(1, 1)
    card.BackgroundTransparency = 1
    card.Parent = billboard

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

    local sep = Instance.new("Frame")
    sep.Name = "Separator"
    sep.Size = UDim2.new(1, -16, 0, 1)
    sep.Position = UDim2.new(0, 8, 0, 36)
    sep.BackgroundColor3 = CONFIG.UI.BorderColor
    sep.BackgroundTransparency = 0.5
    sep.BorderSizePixel = 0
    sep.Parent = bg

    local dataFrame = Instance.new("Frame")
    dataFrame.Name = "DataFrame"
    dataFrame.Size = UDim2.new(1, -16, 1, -50)
    dataFrame.Position = UDim2.new(0, 8, 0, 42)
    dataFrame.BackgroundTransparency = 1
    dataFrame.Parent = bg

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 4)
    listLayout.Parent = dataFrame

    -- 动态创建数据行
    local rows = {}
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
        
        rows[key] = valueLabel
    end

    safeCall(function()
        TweenService:Create(billboard, TweenInfo.new(
            2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true
        ), {
            StudsOffset = Vector3.new(0, 4.3, 0)
        }):Play()
    end)

    billboard.Parent = adornee
    return billboard, rows
end

function InfoCardSystem:CreatePlayerCard(targetPlayer)
    local targetChar = targetPlayer.Character
    if not targetChar then return end
    
    local head = targetChar:FindFirstChild("Head")
    if not head then return end
    
    -- 如果已存在卡片，先清理
    local existingCard = self.cards[targetPlayer.UserId]
    if existingCard and existingCard.Parent then
        existingCard:Destroy()
    end

    local title = targetPlayer.DisplayName
    local data = {
        ["用户名"] = "@" .. targetPlayer.Name,
        ["生命值"] = "??",
        ["速度"] = "??",
        ["距离"] = "0",
    }

    local card, rows = self:CreateCard(head, title, data)
    card.Name = "InfoCard_" .. targetPlayer.UserId
    self.cards[targetPlayer.UserId] = card

    -- 存储 rows 引用以便更新
    self.cards[targetPlayer.UserId .. "_rows"] = rows

    -- 更新数据的协程
    local updateCoroutine
    updateCoroutine = task.spawn(function()
        while card and card.Parent and isDescendant(card, game) do
            safeCall(function()
                local currentChar = targetPlayer.Character
                if not currentChar then break end
                
                local hrp = currentChar:FindFirstChild("HumanoidRootPart")
                local hum = currentChar:FindFirstChild("Humanoid")
                local myHrp = character and character:FindFirstChild("HumanoidRootPart")

                if hrp and hum and myHrp and rows then
                    local dist = math.floor((hrp.Position - myHrp.Position).Magnitude)
                    local health = math.floor(hum.Health)
                    local speed = math.floor(hum.WalkSpeed)

                    if rows["生命值"] then rows["生命值"].Text = tostring(health) end
                    if rows["速度"] then rows["速度"].Text = tostring(speed) end
                    if rows["距离"] then rows["距离"].Text = tostring(dist) end
                end
            end)
            RunService.Heartbeat:Wait()
        end
    end)
    
    -- 存储协程引用以便清理
    self.cards[targetPlayer.UserId .. "_coroutine"] = updateCoroutine
    
    return card
end

function InfoCardSystem:RemovePlayerCard(targetPlayer)
    local userId = targetPlayer.UserId
    local card = self.cards[userId]
    if card then
        safeCall(function() card:Destroy() end)
        self.cards[userId] = nil
    end
    
    local coroutineRef = self.cards[userId .. "_coroutine"]
    if coroutineRef then
        -- 协程会在下一次心跳时自然结束，无法强制停止，但引用可被GC
        self.cards[userId .. "_coroutine"] = nil
    end
    
    self.cards[userId .. "_rows"] = nil
end

function InfoCardSystem:Start()
    -- 清理旧数据
    self:Stop()
    
    if CONFIG.InfoCard.ShowOnSelf then
        safeCall(function() self:CreatePlayerCard(player) end)
    end

    if CONFIG.InfoCard.ShowOnOthers then
        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if otherPlayer ~= player and otherPlayer.Character then
                safeCall(function() self:CreatePlayerCard(otherPlayer) end)
            end
        end

        self.playerAddedConn = Players.PlayerAdded:Connect(function(newPlayer)
            -- 延迟等待角色加载
            task.wait(1)
            if newPlayer ~= player then
                safeCall(function() self:CreatePlayerCard(newPlayer) end)
            end
        end)
        
        self.playerRemovingConn = Players.PlayerRemoving:Connect(function(leavingPlayer)
            if leavingPlayer ~= player then
                self:RemovePlayerCard(leavingPlayer)
            end
        end)
        
        table.insert(self.connections, self.playerAddedConn)
        table.insert(self.connections, self.playerRemovingConn)
    end
end

function InfoCardSystem:Stop()
    for _, conn in ipairs(self.connections) do
        safeCall(function() conn:Disconnect() end)
    end
    for userId, card in pairs(self.cards) do
        if type(userId) == "number" then
            safeCall(function()
                if card and card.Parent then card:Destroy() end
            end)
        end
    end
    self.cards = {}
    self.connections = {}
    self.playerAddedConn = nil
    self.playerRemovingConn = nil
end

function InfoCardSystem:Restart()
    if CONFIG.InfoCard.Enabled then
        self:Stop()
        task.wait(0.1)
        self:Start()
    end
end

---------------------------------------------------------------------------
-- 高亮系统 (独立管理)
---------------------------------------------------------------------------
local HighlightSystem = {
    isActive = false,
    connections = {},
    highlights = {},
}

function HighlightSystem:ApplyHighlight(targetPlayer)
    local char = targetPlayer.Character
    if not char then return end
    
    local highlight = char:FindFirstChild("AcrylicHighlight")
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "AcrylicHighlight"
        highlight.FillColor = CONFIG.UI.AccentColor
        highlight.FillTransparency = 0.7
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        highlight.OutlineTransparency = 0.3
        highlight.Parent = char
        self.highlights[targetPlayer.UserId] = highlight
    end
end

function HighlightSystem:RemoveHighlight(targetPlayer)
    local userId = targetPlayer.UserId
    local highlight = self.highlights[userId]
    if highlight then
        safeCall(function() highlight:Destroy() end)
        self.highlights[userId] = nil
    end
    
    -- 也检查角色上可能残留的
    if targetPlayer.Character then
        local existing = targetPlayer.Character:FindFirstChild("AcrylicHighlight")
        if existing then existing:Destroy() end
    end
end

function HighlightSystem:Start()
    if self.isActive then return end
    
    local function onCharacterAdded(targetPlayer)
        return function(char)
            -- 延迟等待角色完全加载
            task.wait(0.5)
            if self.isActive and targetPlayer ~= player then
                self:ApplyHighlight(targetPlayer)
            end
        end
    end
    
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            self:ApplyHighlight(p)
            -- 监听角色重生
            local conn = p.CharacterAdded:Connect(onCharacterAdded(p))
            table.insert(self.connections, conn)
        end
    end
    
    -- 监听新玩家
    local playerAddedConn = Players.PlayerAdded:Connect(function(newPlayer)
        if newPlayer ~= player then
            task.wait(0.5)
            self:ApplyHighlight(newPlayer)
            local conn = newPlayer.CharacterAdded:Connect(onCharacterAdded(newPlayer))
            table.insert(self.connections, conn)
        end
    end)
    table.insert(self.connections, playerAddedConn)
    
    self.isActive = true
end

function HighlightSystem:Stop()
    for _, p in ipairs(Players:GetPlayers()) do
        self:RemoveHighlight(p)
    end
    for _, conn in ipairs(self.connections) do
        safeCall(function() conn:Disconnect() end)
    end
    self.connections = {}
    self.highlights = {}
    self.isActive = false
end

function HighlightSystem:Restart()
    if self.isActive then
        self:Stop()
        task.wait(0.1)
        self:Start()
    end
end

---------------------------------------------------------------------------
-- ESP 线框系统
---------------------------------------------------------------------------
local ESPSystem = {
    isActive = false,
    connections = {},
    espBoxes = {},
}

function ESPSystem:ApplyESP(targetPlayer)
    if targetPlayer == player then return end
    
    local char = targetPlayer.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local espBox = hrp:FindFirstChild("AcrylicESP")
    if not espBox then
        espBox = Instance.new("BoxHandleAdornment")
        espBox.Name = "AcrylicESP"
        espBox.Adornee = hrp
        espBox.Size = Vector3.new(4, 5.5, 4)
        espBox.Color3 = CONFIG.UI.AccentColor
        espBox.Transparency = 0.6
        espBox.AlwaysOnTop = true
        espBox.ZIndex = 10
        espBox.Parent = hrp
        self.espBoxes[targetPlayer.UserId] = espBox
    end
end

function ESPSystem:RemoveESP(targetPlayer)
    local userId = targetPlayer.UserId
    local espBox = self.espBoxes[userId]
    if espBox then
        safeCall(function() espBox:Destroy() end)
        self.espBoxes[userId] = nil
    end
end

function ESPSystem:Start()
    if self.isActive then return end
    
    local function onCharacterAdded(targetPlayer)
        return function(char)
            task.wait(0.5)
            if self.isActive then
                self:ApplyESP(targetPlayer)
            end
        end
    end
    
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            self:ApplyESP(p)
            local conn = p.CharacterAdded:Connect(onCharacterAdded(p))
            table.insert(self.connections, conn)
        end
    end
    
    local playerAddedConn = Players.PlayerAdded:Connect(function(newPlayer)
        if newPlayer ~= player then
            task.wait(0.5)
            self:ApplyESP(newPlayer)
            local conn = newPlayer.CharacterAdded:Connect(onCharacterAdded(newPlayer))
            table.insert(self.connections, conn)
        end
    end)
    table.insert(self.connections, playerAddedConn)
    
    self.isActive = true
end

function ESPSystem:Stop()
    for _, p in ipairs(Players:GetPlayers()) do
        self:RemoveESP(p)
    end
    for _, conn in ipairs(self.connections) do
        safeCall(function() conn:Disconnect() end)
    end
    self.connections = {}
    self.espBoxes = {}
    self.isActive = false
end

function ESPSystem:Restart()
    if self.isActive then
        self:Stop()
        task.wait(0.1)
        self:Start()
    end
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

    local uiBlur = Instance.new("BlurEffect")
    uiBlur.Name = "UIBlur"
    uiBlur.Size = 0
    uiBlur.Enabled = true
    uiBlur.Parent = Lighting

    -----------------------------------------------------------------------
    -- 手机端悬浮按钮
    -----------------------------------------------------------------------
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "ToggleBtn"
    toggleBtn.Size = UDim2.fromOffset(48, 48)
    toggleBtn.Position = UDim2.new(0, 16, 0.5, -24)
    toggleBtn.BackgroundColor3 = CONFIG.UI.CardColor
    toggleBtn.BackgroundTransparency = 0.15
    toggleBtn.Text = "V"
    toggleBtn.TextColor3 = CONFIG.UI.AccentColor
    toggleBtn.TextSize = 20
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.BorderSizePixel = 0
    toggleBtn.AutoButtonColor = false
    toggleBtn.ZIndex = 100
    toggleBtn.Parent = screenGui

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(1, 0)
    toggleCorner.Parent = toggleBtn

    local toggleStroke = Instance.new("UIStroke")
    toggleStroke.Color = CONFIG.UI.AccentColor
    toggleStroke.Thickness = 1.5
    toggleStroke.Transparency = 0.3
    toggleStroke.Parent = toggleBtn

    local btnGlow = Instance.new("ImageLabel")
    btnGlow.Name = "Glow"
    btnGlow.Size = UDim2.fromOffset(80, 80)
    btnGlow.Position = UDim2.fromScale(0.5, 0.5)
    btnGlow.AnchorPoint = Vector2.new(0.5, 0.5)
    btnGlow.BackgroundTransparency = 1
    btnGlow.Image = "rbxassetid://7669168585"
    btnGlow.ImageColor3 = CONFIG.UI.AccentColor
    btnGlow.ImageTransparency = 0.7
    btnGlow.ScaleType = Enum.ScaleType.Slice
    btnGlow.SliceCenter = Rect.new(40, 40, 360, 360)
    btnGlow.ZIndex = 99
    btnGlow.Parent = toggleBtn

    safeCall(function()
        TweenService:Create(btnGlow, TweenInfo.new(
            1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true
        ), {
            ImageTransparency = 0.9,
        }):Play()
    end)

    -- 按钮拖拽 (带边界检查)
    local btnDragging = false
    local btnDragStart, btnStartPos
    local btnDragMoved = false

    toggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            btnDragging = true
            btnDragMoved = false
            btnDragStart = input.Position
            btnStartPos = toggleBtn.Position
        end
    end)

    toggleBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            btnDragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if btnDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - btnDragStart
            if delta.Magnitude > 8 then
                btnDragMoved = true
            end
            local newPos = UDim2.new(
                btnStartPos.X.Scale, btnStartPos.X.Offset + delta.X,
                btnStartPos.Y.Scale, btnStartPos.Y.Offset + delta.Y
            )
            -- 边界检查
            local screenSize = GuiService:GetScreenSize()
            newPos = clampUdim2(newPos, toggleBtn.Size, screenSize)
            toggleBtn.Position = newPos
        end
    end)

    -----------------------------------------------------------------------
    -- 侧边栏面板
    -----------------------------------------------------------------------
    local panel = Instance.new("Frame")
    panel.Name = "SidePanel"
    panel.Size = UDim2.new(0, 280, 0, 460)
    panel.Position = UDim2.new(0, 72, 0.5, -230)
    panel.BackgroundColor3 = CONFIG.UI.BackgroundColor
    panel.BackgroundTransparency = 0.08
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.Visible = false
    panel.Parent = screenGui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = CONFIG.UI.CornerRadius
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = CONFIG.UI.BorderColor
    panelStroke.Thickness = 1
    panelStroke.Transparency = 0.3
    panelStroke.Parent = panel

    AcrylicPure.CreateGlow(panel, CONFIG.UI.AccentColor, 350)

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
    subtitle.Text = "Acrylic Pure Edition v2.1"
    subtitle.TextColor3 = CONFIG.UI.SubTextColor
    subtitle.TextSize = 11
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = header

    AcrylicPure.CreateAccentLine(panel, UDim2.new(0, 12, 0, 56), UDim2.new(1, -24, 0, 1))

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

        local swBtn = Instance.new("TextButton")
        swBtn.Name = "Toggle"
        swBtn.Size = UDim2.fromOffset(44, 24)
        swBtn.Position = UDim2.new(1, -56, 0.5, -12)
        swBtn.BackgroundColor3 = defaultState and CONFIG.UI.SuccessColor or CONFIG.UI.BorderColor
        swBtn.BackgroundTransparency = 0.2
        swBtn.Text = ""
        swBtn.BorderSizePixel = 0
        swBtn.AutoButtonColor = false
        swBtn.Parent = card

        local swCorner = Instance.new("UICorner")
        swCorner.CornerRadius = UDim.new(1, 0)
        swCorner.Parent = swBtn

        local knob = Instance.new("Frame")
        knob.Name = "Knob"
        knob.Size = UDim2.fromOffset(18, 18)
        knob.Position = defaultState and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel = 0
        knob.Parent = swBtn

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = knob

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

        local isOn = defaultState
        swBtn.MouseButton1Click:Connect(function()
            isOn = not isOn
            local targetPos = isOn and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
            local targetColor = isOn and CONFIG.UI.SuccessColor or CONFIG.UI.BorderColor

            TweenService:Create(knob, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
                Position = targetPos
            }):Play()
            TweenService:Create(swBtn, TweenInfo.new(0.25), {
                BackgroundColor3 = targetColor
            }):Play()
            TweenService:Create(indicator, TweenInfo.new(0.25), {
                BackgroundColor3 = isOn and CONFIG.UI.SuccessColor or CONFIG.UI.DangerColor
            }):Play()

            FeatureInterface:Toggle(featureName)
        end)

        return card
    end

    -----------------------------------------------------------------------
    -- 注册功能 (使用修复后的独立系统)
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
        if state then
            HighlightSystem:Start()
        else
            HighlightSystem:Stop()
        end
    end)

    FeatureInterface:Register("ESP线框", false, function(state)
        if state then
            ESPSystem:Start()
        else
            ESPSystem:Stop()
        end
    end)

    FeatureInterface:Register("全屏模糊", false, function(state)
        safeCall(function()
            uiBlur.Size = state and 20 or 0
        end)
    end)

    FeatureInterface:Register("FPS显示", false, function(state)
        safeCall(function()
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

                    task.spawn(function()
                        local lastTick = tick()
                        local frames = 0
                        while fpsLabel and fpsLabel.Parent and isDescendant(fpsLabel, game) do
                            frames = frames + 1
                            local currentTick = tick()
                            if currentTick - lastTick >= 1 then
                                safeCall(function()
                                    fpsLabel.Text = "FPS: " .. tostring(frames)
                                end)
                                frames = 0
                                lastTick = currentTick
                            end
                            RunService.Heartbeat:Wait()
                        end
                    end)
                end
            else
                if fpsLabel and fpsLabel.Parent then 
                    fpsLabel:Destroy() 
                end
            end
        end)
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

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -16, 1, 0)
    statusLabel.Position = UDim2.new(0, 8, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "● 已连接"
    statusLabel.TextColor3 = CONFIG.UI.SuccessColor
    statusLabel.TextSize = 10
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = footer

    -----------------------------------------------------------------------
    -- 面板拖拽 (带边界检查)
    -----------------------------------------------------------------------
    local dragging = false
    local dragStart, startPos

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = panel.Position
        end
    end)

    header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            local newPos = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
            local screenSize = GuiService:GetScreenSize()
            newPos = clampUdim2(newPos, panel.Size, screenSize)
            panel.Position = newPos
        end
    end)

    -----------------------------------------------------------------------
    -- 悬浮按钮控制面板显隐
    -----------------------------------------------------------------------
    local panelVisible = false

    local function togglePanel()
        panelVisible = not panelVisible

        if panelVisible then
            panel.Visible = true
            panel.Size = UDim2.new(0, 280, 0, 0)
            panel.BackgroundTransparency = 1
            TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 280, 0, 460),
                BackgroundTransparency = 0.08,
            }):Play()

            TweenService:Create(toggleBtn, TweenInfo.new(0.25), {
                BackgroundColor3 = CONFIG.UI.AccentColor,
            }):Play()
            TweenService:Create(toggleStroke, TweenInfo.new(0.25), {
                Transparency = 0,
            }):Play()
            toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            local tween = TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                Size = UDim2.new(0, 280, 0, 0),
                BackgroundTransparency = 1,
            })
            tween:Play()
            tween.Completed:Connect(function()
                if not panelVisible then
                    panel.Visible = false
                end
            end)

            TweenService:Create(toggleBtn, TweenInfo.new(0.25), {
                BackgroundColor3 = CONFIG.UI.CardColor,
            }):Play()
            TweenService:Create(toggleStroke, TweenInfo.new(0.25), {
                Transparency = 0.3,
            }):Play()
            toggleBtn.TextColor3 = CONFIG.UI.AccentColor
        end
    end

    toggleBtn.MouseButton1Click:Connect(function()
        if not btnDragMoved then
            togglePanel()
        end
    end)

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.RightControl then
            togglePanel()
        end
    end)

    screenGui.Parent = player:WaitForChild("PlayerGui")
    return screenGui
end

---------------------------------------------------------------------------
-- 等待角色部件就绪的工具函数
---------------------------------------------------------------------------
local function waitForCharacterReady(newChar)
    return function(callback)
        local bindable = Instance.new("BindableEvent")
        
        local function checkParts()
            local hrp = newChar:FindFirstChild("HumanoidRootPart")
            local hum = newChar:FindFirstChild("Humanoid")
            if hrp and hum then
                bindable:Fire({hrp = hrp, hum = hum})
            end
        end
        
        local conn = newChar.ChildAdded:Connect(checkParts)
        checkParts()
        
        local result = bindable.Event:Wait()
        conn:Disconnect()
        bindable:Destroy()
        
        if callback then
            callback(result.hrp, result.hum)
        end
        return result.hrp, result.hum
    end
end

---------------------------------------------------------------------------
-- 角色重生处理
---------------------------------------------------------------------------
local characterAddedConn = player.CharacterAdded:Connect(function(newChar)
    character = newChar
    
    -- 等待角色完全加载
    local readyWaiter = waitForCharacterReady(newChar)
    readyWaiter(function(hrp, hum)
        rootPart = hrp
        humanoid = hum
        
        -- 重启残影系统
        if CONFIG.Afterimage.Enabled then
            AfterimageSystem:Restart()
        end
        
        -- 重启信息卡片（自己的）
        if CONFIG.InfoCard.Enabled and CONFIG.InfoCard.ShowOnSelf then
            -- 延迟一下让其他系统也更新
            task.wait(0.5)
            safeCall(function() InfoCardSystem:CreatePlayerCard(player) end)
        end
    end)
end)

---------------------------------------------------------------------------
-- 启动
---------------------------------------------------------------------------
local mainUI = BuildMainUI()

-- 启动启用的功能
if CONFIG.Afterimage.Enabled then
    AfterimageSystem:Start()
end

if CONFIG.InfoCard.Enabled then
    InfoCardSystem:Start()
end

-- 高亮和ESP默认是关闭的，由用户手动开启

print("[Acrylic Pure] 视觉脚本已加载 v2.1 (修复版)")

---------------------------------------------------------------------------
-- 优雅退出 (可选)
---------------------------------------------------------------------------
local function cleanup()
    safeCall(function()
        AfterimageSystem:Stop()
        InfoCardSystem:Stop()
        HighlightSystem:Stop()
        ESPSystem:Stop()
        FeatureInterface:Cleanup()
        if characterAddedConn then characterAddedConn:Disconnect() end
        if mainUI then mainUI:Destroy() end
    end)
end

-- 玩家离开时清理（脚本会自然销毁，但显式清理更安全）
player.PlayerRemoving:Connect(cleanup)