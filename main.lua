-- Aimbot + ESP para personagens padrão do Roblox.
-- RightShift: mostrar/ocultar painel.
-- Botão direito segurado: ativar mira.
-- Fechar: remover interface, efeitos e conexões.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local environment = getgenv and getgenv() or _G
local instanceKey = "__MeowAimESP"

if type(environment[instanceKey]) == "function" then
    pcall(environment[instanceKey])
end

local config = {
    Aim = false,
    ESP = false,
    TeamCheck = true,
    VisibleOnly = true,
    ThroughWalls = false,
    ShowFOV = true,
    FOV = 150,             -- Raio em pixels.
    Response = 12,         -- Resposta por segundo; maior = mais rápido.
    MaxDistance = 1500,    -- Distância em studs.
    AimPart = "Head",
}

local connections = {}
local visuals = {}
local destroyed = false

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local gui = Instance.new("ScreenGui")
gui.Name = "MeowAimESP"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function create(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function round(object, radius)
    create("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
    }, object)
end

local accent = Color3.fromRGB(169, 132, 255)

local panel = create("Frame", {
    Size = UDim2.fromOffset(310, 465),
    Position = UDim2.fromOffset(40, 110),
    BackgroundColor3 = Color3.fromRGB(23, 24, 31),
    BorderSizePixel = 0,
    Active = true,
}, gui)
round(panel, 12)

create("UIStroke", {
    Color = Color3.fromRGB(65, 62, 82),
    Thickness = 1,
}, panel)

local header = create("TextLabel", {
    Size = UDim2.new(1, -55, 0, 48),
    Position = UDim2.fromOffset(16, 0),
    BackgroundTransparency = 1,
    Text = "MEOW / AIM + ESP",
    TextColor3 = accent,
    TextSize = 16,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    Active = true,
}, panel)

local close = create("TextButton", {
    Size = UDim2.fromOffset(32, 32),
    Position = UDim2.new(1, -42, 0, 8),
    BackgroundColor3 = Color3.fromRGB(45, 37, 48),
    Text = "×",
    TextColor3 = Color3.fromRGB(255, 160, 170),
    TextSize = 23,
    Font = Enum.Font.Gotham,
    BorderSizePixel = 0,
}, panel)
round(close)

local body = create("ScrollingFrame", {
    Position = UDim2.fromOffset(12, 52),
    Size = UDim2.new(1, -24, 1, -89),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = accent,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)

create("UIListLayout", {
    Padding = UDim.new(0, 7),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, body)

create("TextLabel", {
    Position = UDim2.new(0, 12, 1, -29),
    Size = UDim2.new(1, -24, 0, 20),
    BackgroundTransparency = 1,
    Text = "RMB: mirar  •  RightShift: painel",
    TextColor3 = Color3.fromRGB(150, 151, 165),
    TextSize = 11,
    Font = Enum.Font.Gotham,
}, panel)

local function button(text, callback)
    local control = create("TextButton", {
        Size = UDim2.new(1, -5, 0, 33),
        BackgroundColor3 = Color3.fromRGB(34, 35, 45),
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(225, 225, 235),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
    }, body)
    round(control, 6)
    connect(control.Activated, callback)
    return control
end

local function toggle(label, key)
    local control
    local function refresh()
        control.Text = label .. "  ·  " .. (config[key] and "ON" or "OFF")
        control.TextColor3 = config[key]
            and accent or Color3.fromRGB(170, 170, 185)
    end
    control = button("", function()
        config[key] = not config[key]
        refresh()
    end)
    refresh()
end

local activeSlider
local function slider(label, key, minimum, maximum)
    local row = create("Frame", {
        Size = UDim2.new(1, -5, 0, 48),
        BackgroundTransparency = 1,
    }, body)

    local caption = create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(200, 200, 215),
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local track = create("TextButton", {
        Position = UDim2.fromOffset(0, 28),
        Size = UDim2.new(1, 0, 0, 12),
        BackgroundColor3 = Color3.fromRGB(48, 49, 62),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row)
    round(track, 6)

    local fill = create("Frame", {
        Size = UDim2.new(),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        Active = false,
    }, track)
    round(fill, 6)

    local function refresh()
        caption.Text = string.format("%s: %d", label, config[key])
        fill.Size = UDim2.fromScale(
            (config[key] - minimum) / (maximum - minimum), 1
        )
    end

    local function update(x)
        local width = track.AbsoluteSize.X
        if width <= 0 then return end
        local fraction = math.clamp(
            (x - track.AbsolutePosition.X) / width, 0, 1
        )
        config[key] = math.floor(
            minimum + (maximum - minimum) * fraction + 0.5
        )
        refresh()
    end

    connect(track.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeSlider = update
            update(input.Position.X)
        end
    end)
    refresh()
end

toggle("Aimbot", "Aim")
toggle("ESP", "ESP")
toggle("Ignorar mesma equipe", "TeamCheck")
toggle("Mira somente com visão livre", "VisibleOnly")
toggle("ESP através de paredes", "ThroughWalls")
toggle("Mostrar círculo de FOV", "ShowFOV")

local partButton
partButton = button("Ponto de mira: cabeça", function()
    config.AimPart = config.AimPart == "Head"
        and "HumanoidRootPart" or "Head"
    partButton.Text = "Ponto de mira: " ..
        (config.AimPart == "Head" and "cabeça" or "tronco")
end)

slider("FOV / raio em pixels", "FOV", 30, 500)
slider("Velocidade da mira", "Response", 1, 30)
slider("Distância máxima / studs", "MaxDistance", 100, 5000)

local circle = create("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    Size = UDim2.fromOffset(config.FOV * 2, config.FOV * 2),
    Visible = false,
}, gui)
round(circle, 10000)

create("UIStroke", {
    Color = accent,
    Thickness = 1,
    Transparency = 0.25,
}, circle)

local dragging = false
local dragStart
local panelStart

connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        panelStart = panel.Position
    end
end)

connect(UIS.InputChanged, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

    if activeSlider then
        activeSlider(input.Position.X)
    elseif dragging then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(
            panelStart.X.Scale, panelStart.X.Offset + delta.X,
            panelStart.Y.Scale, panelStart.Y.Offset + delta.Y
        )
    end
end)

connect(UIS.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        activeSlider = nil
    end
end)

connect(UIS.WindowFocusReleased, function()
    dragging = false
    activeSlider = nil
end)

connect(UIS.InputBegan, function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then
        panel.Visible = not panel.Visible
    end
end)

local function removeVisual(player)
    local visual = visuals[player]
    if not visual then return end
    visual.highlight:Destroy()
    visual.billboard:Destroy()
    visuals[player] = nil
end

local function getVisual(player, character, root)
    local visual = visuals[player]
    if visual and visual.character == character then
        visual.billboard.Adornee = character:FindFirstChild("Head") or root
        return visual
    end

    removeVisual(player)

    local highlight = create("Highlight", {
        Adornee = character,
        FillColor = accent,
        OutlineColor = Color3.fromRGB(235, 225, 255),
        FillTransparency = 0.7,
        OutlineTransparency = 0.1,
        Enabled = false,
    }, gui)

    local billboard = create("BillboardGui", {
        Adornee = character:FindFirstChild("Head") or root,
        Size = UDim2.fromOffset(190, 38),
        StudsOffset = Vector3.new(0, 2.6, 0),
        Enabled = false,
    }, gui)

    local label = create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(240, 235, 255),
        TextStrokeTransparency = 0.3,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
    }, billboard)

    visual = {
        character = character,
        highlight = highlight,
        billboard = billboard,
        label = label,
    }
    visuals[player] = visual
    return visual
end

connect(Players.PlayerRemoving, removeVisual)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function validCharacter(player)
    if player == LocalPlayer then return end

    if config.TeamCheck
        and not LocalPlayer.Neutral
        and not player.Neutral
        and LocalPlayer.Team ~= nil
        and player.Team == LocalPlayer.Team then
        return
    end

    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or humanoid.Health <= 0
        or not root or not root:IsA("BasePart") then
        return
    end

    return character, humanoid, root
end

local function hasLineOfSight(camera, character, point)
    local direction = point - camera.CFrame.Position
    if direction.Magnitude < 0.001 then return true end

    local result = workspace:Raycast(
        camera.CFrame.Position, direction, rayParams
    )
    return result == nil or result.Instance:IsDescendantOf(character)
end

connect(RunService.RenderStepped, function(dt)
    local camera = workspace.CurrentCamera
    if not camera then
        circle.Visible = false
        for _, visual in pairs(visuals) do
            visual.highlight.Enabled = false
            visual.billboard.Enabled = false
        end
        return
    end

    -- WorldToViewportPoint usa coordenadas sem o inset superior.
    -- O ScreenGui também ignora esse inset.
    local center = camera.ViewportSize * 0.5
    circle.Position = UDim2.fromOffset(center.X, center.Y)
    circle.Size = UDim2.fromOffset(config.FOV * 2, config.FOV * 2)
    circle.Visible = config.Aim and config.ShowFOV

    local localCharacter = LocalPlayer.Character
    local localHumanoid = localCharacter
        and localCharacter:FindFirstChildOfClass("Humanoid")
    local localRoot = localCharacter
        and localCharacter:FindFirstChild("HumanoidRootPart")

    local alive = localHumanoid and localHumanoid.Health > 0
        and localRoot and localRoot:IsA("BasePart")

    local origin = alive and localRoot.Position or camera.CFrame.Position

    rayParams.FilterDescendantsInstances =
        localCharacter and {localCharacter} or {}

    local canAim = config.Aim and alive
        and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        and UIS:GetFocusedTextBox() == nil
        and not dragging and activeSlider == nil

    local bestPoint
    local bestDistance = config.FOV

    for _, player in ipairs(Players:GetPlayers()) do
        local character, humanoid, root = validCharacter(player)
        local visual = visuals[player]

        if visual then
            visual.highlight.Enabled = false
            visual.billboard.Enabled = false
        end

        if character then
            local distance = (root.Position - origin).Magnitude

            if distance <= config.MaxDistance then
                if config.ESP then
                    visual = getVisual(player, character, root)
                    visual.highlight.Enabled = true
                    visual.highlight.DepthMode = config.ThroughWalls
                        and Enum.HighlightDepthMode.AlwaysOnTop
                        or Enum.HighlightDepthMode.Occluded
                    visual.billboard.Enabled = true
                    visual.billboard.AlwaysOnTop = config.ThroughWalls
                    visual.label.Text = string.format(
                        "%s  ·  %d studs\n%d HP",
                        player.DisplayName,
                        math.floor(distance + 0.5),
                        math.floor(humanoid.Health + 0.5)
                    )
                end

                if canAim then
                    local part = character:FindFirstChild(config.AimPart)
                    if part and part:IsA("BasePart") then
                        local projected, onScreen =
                            camera:WorldToViewportPoint(part.Position)

                        if onScreen and projected.Z > 0 then
                            local screenDistance = (
                                Vector2.new(projected.X, projected.Y) - center
                            ).Magnitude

                            if screenDistance < bestDistance
                                and (
                                    not config.VisibleOnly
                                    or hasLineOfSight(
                                        camera, character, part.Position
                                    )
                                ) then
                                bestDistance = screenDistance
                                bestPoint = part.Position
                            end
                        end
                    end
                end
            end
        end
    end

    if bestPoint then
        local position = camera.CFrame.Position
        if (bestPoint - position).Magnitude > 0.001 then
            local goal = CFrame.lookAt(position, bestPoint)
            local alpha = 1 - math.exp(
                -config.Response * math.clamp(dt, 0, 0.1)
            )
            camera.CFrame = camera.CFrame:Lerp(goal, alpha)
        end
    end
end)

local cleanup
cleanup = function()
    if destroyed then return end
    destroyed = true

    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end

    for _, visual in pairs(visuals) do
        visual.highlight:Destroy()
        visual.billboard:Destroy()
    end
    table.clear(visuals)
    gui:Destroy()

    if environment[instanceKey] == cleanup then
        environment[instanceKey] = nil
    end
end

environment[instanceKey] = cleanup
connect(close.Activated, cleanup)
