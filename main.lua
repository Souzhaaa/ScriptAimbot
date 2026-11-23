-- SOUZADAS | painel em Luau; logo PNG opcional hospedada no GitHub.
-- Personagens padrao: Humanoid, Head e HumanoidRootPart.
-- RightShift: painel (configuravel pelo botao do cabecalho).
-- Clique no atalho do cabecalho e pressione a nova tecla. Esc cancela.
-- X: encerra e remove todos os efeitos. Atalhos valem nesta execucao.
-- Logo original carregada com writefile + getcustomasset/getsynasset.
-- Identidade vetorial de reserva se o executor nao oferecer essas APIs.
-- Velocidade 30 = mira direta; valores menores = suavizacao acumulada.
-- Aba Jogador: speed local via Humanoid.WalkSpeed, com restauracao.
-- N: alterna noclip. O atalho pode ser trocado na aba Jogador.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local env = getgenv and getgenv() or _G
for _, key in ipairs({"__MeowAimESP", "__SouzadasPanel"}) do
    if type(env[key]) == "function" then pcall(env[key]) end
end

local defaults = {
    Aim = false, ESP = false, TeamCheck = true, WallCheck = true,
    ThroughWalls = false, ShowFOV = true, Names = true,
    Health = true, Distance = true, FOV = 150, Response = 30,
    MaxDistance = 1500, AimPart = "Head",
    Activation = 1, PanelKey = Enum.KeyCode.RightShift,
    Speed = false, SpeedValue = 24,
    Noclip = false, NoclipKey = Enum.KeyCode.N,
}
local settings = table.clone(defaults)
local connections, refreshers, effects, animations = {}, {}, {}, {}
local activeSlider, dragging, dragStart, panelStart
local captureTarget, footerHint, noclipKeyButton
local suppressAimUntilRelease = false
local destroyed, focused = false, true
local binding = "Souzadas_" .. HttpService:GenerateGUID(false)
local cleanup
local purple = Color3.fromRGB(177, 108, 245)
local light = Color3.fromRGB(238, 232, 250)
local muted = Color3.fromRGB(166, 157, 187)

-- BEGIN LOGO LOADER
local LOGO_URL = "https://raw.githubusercontent.com/Souzhaaa/ScriptAimbot/main/LogoSouzadas.png"
local LOGO_FILE = "SOUZADAS_Logo.png"
local function loadLogoAsset()
    local registerAsset = type(getcustomasset) == "function" and getcustomasset or getsynasset
    if type(registerAsset) ~= "function" or type(writefile) ~= "function" then
        return nil, "Executor sem suporte a imagem local; usando logo de reserva."
    end
    local ok, bytes = pcall(function() return game:HttpGet(LOGO_URL) end)
    if not ok or type(bytes) ~= "string" then return nil, "Falha ao baixar a logo; usando reserva." end
    if #bytes < 33 or #bytes > 5 * 1024 * 1024
        or bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" or bytes:sub(13, 16) ~= "IHDR" then
        return nil, "Resposta nao e um PNG valido para a logo; usando reserva."
    end
    local function readU32(offset)
        local a, b, c, d = bytes:byte(offset, offset + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    -- Regioes medidas na imagem enviada: 1312 x 1199 pixels.
    -- Mudancas nessa composicao exigem ajustar os retangulos do cabecalho.
    if readU32(17) ~= 1312 or readU32(21) ~= 1199 then
        return nil, "A imagem da logo mudou de tamanho; usando reserva."
    end
    if destroyed then return nil end
    local saved = pcall(writefile, LOGO_FILE, bytes)
    if not saved or destroyed then return nil, "Logo nao foi gravada; usando reserva." end
    local registered, asset = pcall(registerAsset, LOGO_FILE)
    if not registered or type(asset) ~= "string" or asset == "" then
        return nil, "Logo nao foi registrada pelo executor; usando reserva."
    end
    return asset
end
-- END LOGO LOADER

-- BEGIN SPEED CONTROLLER
-- Altera somente ao acionar o controle, ajustar o valor ou renascer.
-- Nao reescreve WalkSpeed continuamente se o jogo substituir esse valor.
local speedHumanoid, speedOriginal, speedLastApplied
local speedChildConnection, speedDiedConnection
local function restoreSpeed()
    local humanoid, original, applied = speedHumanoid, speedOriginal, speedLastApplied
    speedHumanoid, speedOriginal, speedLastApplied = nil, nil, nil
    -- Nao sobrescreve uma mudanca posterior feita pelo proprio jogo.
    if humanoid and humanoid.Parent and original ~= nil and applied ~= nil
        and humanoid.WalkSpeed == applied then
        humanoid.WalkSpeed = original
    end
end
local function syncSpeed()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if destroyed or not settings.Speed or not humanoid or humanoid.Health <= 0 then
        restoreSpeed()
        return
    end
    if humanoid ~= speedHumanoid then
        restoreSpeed()
        speedHumanoid, speedOriginal = humanoid, humanoid.WalkSpeed
    end
    local value = tonumber(settings.SpeedValue) or defaults.SpeedValue
    if value ~= value or math.abs(value) == math.huge then value = defaults.SpeedValue end
    value = math.clamp(math.floor(value + 0.5), 8, 80)
    settings.SpeedValue = value
    humanoid.WalkSpeed = value
    speedLastApplied = value
end
local function disconnectSpeedWatchers()
    if speedChildConnection then speedChildConnection:Disconnect(); speedChildConnection = nil end
    if speedDiedConnection then speedDiedConnection:Disconnect(); speedDiedConnection = nil end
end
local function watchSpeedCharacter(character)
    disconnectSpeedWatchers()
    restoreSpeed()
    if destroyed or not character then return end
    local function attach(humanoid)
        if destroyed or player.Character ~= character then return end
        if speedDiedConnection then speedDiedConnection:Disconnect() end
        speedDiedConnection = humanoid.Died:Connect(restoreSpeed)
        syncSpeed()
    end
    speedChildConnection = character.ChildAdded:Connect(function(child)
        if child:IsA("Humanoid") then attach(child) end
    end)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then attach(humanoid) end
end
-- END SPEED CONTROLLER

-- BEGIN NOCLIP CONTROLLER
local noclipCharacter
local noclipParts = {}
local noclipAddedConnection, noclipRemovedConnection
local function restoreNoclipPart(part)
    local original = noclipParts[part]
    if original == nil then return end
    noclipParts[part] = nil
    if part.Parent and part.CanCollide == false then part.CanCollide = original end
end
local function restoreNoclip()
    if noclipAddedConnection then noclipAddedConnection:Disconnect(); noclipAddedConnection = nil end
    if noclipRemovedConnection then noclipRemovedConnection:Disconnect(); noclipRemovedConnection = nil end
    for part in pairs(noclipParts) do restoreNoclipPart(part) end
    noclipCharacter = nil
end
local function rememberNoclipPart(part)
    if not part:IsA("BasePart") then return end
    if noclipParts[part] == nil then noclipParts[part] = part.CanCollide end
    part.CanCollide = false
end
local function syncNoclip()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if destroyed or not settings.Noclip or not character or not humanoid or humanoid.Health <= 0 then
        restoreNoclip()
        return
    end
    if character ~= noclipCharacter then
        restoreNoclip()
        noclipCharacter = character
        noclipAddedConnection = character.DescendantAdded:Connect(rememberNoclipPart)
        noclipRemovedConnection = character.DescendantRemoving:Connect(restoreNoclipPart)
        for _, part in ipairs(character:GetDescendants()) do rememberNoclipPart(part) end
    end
    -- Restaura fora do personagem; revalida colisoes antes da simulacao.
    for part in pairs(noclipParts) do
        if part.Parent and part:IsDescendantOf(character) then
            if part.CanCollide then part.CanCollide = false end
        else
            restoreNoclipPart(part)
        end
    end
end
-- END NOCLIP CONTROLLER

local function listen(signal, fn)
    local connection = signal:Connect(fn)
    table.insert(connections, connection)
    return connection
end
local function make(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props) do object[key] = value end
    object.Parent = parent
    return object
end
local function corner(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius)}, object)
end
local function stroke(object, color, transparency, thickness)
    return make("UIStroke", {
        Color = color or purple, Transparency = transparency or 0,
        Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, object)
end
local function gradient(object, first, last, rotation)
    make("UIGradient", {
        Color = ColorSequence.new(first, last), Rotation = rotation or 90,
    }, object)
end
local function animate(object, props)
    if animations[object] then animations[object]:Cancel() end
    local tween = TweenService:Create(object, TweenInfo.new(0.15), props)
    animations[object] = tween
    tween:Play()
end
local function label(parent, text, x, y, width, height, size, color, bold)
    return make("TextLabel", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundTransparency = 1, Text = text, TextColor3 = color or light,
        TextSize = size or 15,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, parent)
end
local function button(parent, text, x, y, width, height)
    local object = make("TextButton", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Color3.fromRGB(32, 25, 46), BorderSizePixel = 0,
        Text = text, TextColor3 = light, TextSize = 14,
        Font = Enum.Font.GothamMedium, AutoButtonColor = false,
    }, parent)
    corner(object, 9)
    stroke(object, Color3.fromRGB(111, 86, 146), 0.2)
    return object
end
local function line(parent, x, y, width)
    make("Frame", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, 1),
        BackgroundColor3 = Color3.fromRGB(66, 52, 85),
        BackgroundTransparency = 0.45, BorderSizePixel = 0,
    }, parent)
end

local gui = make("ScreenGui", {
    Name = "SOUZADAS", IgnoreGuiInset = true, ResetOnSpawn = false,
    DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

local panel = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(1000, 564), BorderSizePixel = 0,
    BackgroundColor3 = Color3.fromRGB(19, 15, 28), Active = true,
}, gui)
corner(panel, 22)
stroke(panel, Color3.fromRGB(184, 143, 222), 0.08, 1.2)
gradient(panel, Color3.fromRGB(25, 19, 36), Color3.fromRGB(14, 13, 22), 35)
local scale = make("UIScale", {Scale = 1}, panel)

-- Identidade de reserva, mantida ate a imagem original terminar de carregar.
local logo = make("Frame", {
    Position = UDim2.fromOffset(29, 17), Size = UDim2.fromOffset(65, 51),
    BackgroundTransparency = 1,
}, panel)
local points = {{58, 4}, {20, 4}, {5, 19}, {42, 34}, {27, 48}, {0, 48}}
for index = 1, #points - 1 do
    local a, b = points[index], points[index + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local segment = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset((a[1] + b[1]) / 2, (a[2] + b[2]) / 2),
        Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 2, 9),
        Rotation = math.deg(math.atan2(dy, dx)),
        BackgroundColor3 = purple, BorderSizePixel = 0,
    }, logo)
    gradient(segment, Color3.fromRGB(218, 176, 255), Color3.fromRGB(133, 50, 209))
end
make("Frame", {
    Position = UDim2.fromOffset(110, 19), Size = UDim2.fromOffset(1, 43),
    BackgroundColor3 = Color3.fromRGB(98, 78, 123), BorderSizePixel = 0,
}, panel)
local fallbackTitle = label(panel, "SOUZADAS", 126, 16, 430, 32, 28, light, true)
label(panel, "Configurações", 127, 49, 400, 22, 16, muted)
-- As duas regioes usam o MESMO PNG original, sem gerar outra imagem.
local logoSymbol = make("ImageLabel", {
    Position = UDim2.fromOffset(25, 10), Size = UDim2.fromOffset(74, 63),
    BackgroundTransparency = 1, ImageTransparency = 1,
    Image = "", ScaleType = Enum.ScaleType.Fit, ZIndex = 2,
    ImageRectOffset = Vector2.new(245, 185), ImageRectSize = Vector2.new(830, 705),
}, panel)
local logoWordmark = make("ImageLabel", {
    Position = UDim2.fromOffset(123, 12), Size = UDim2.fromOffset(294, 40),
    BackgroundTransparency = 1, ImageTransparency = 1,
    Image = "", ScaleType = Enum.ScaleType.Fit, ZIndex = 2,
    ImageRectOffset = Vector2.new(55, 898), ImageRectSize = Vector2.new(1200, 170),
}, panel)
task.spawn(function()
    local asset, reason = loadLogoAsset()
    if destroyed or not gui.Parent then return end
    if not asset then
        if reason then warn("[SOUZADAS] " .. reason) end
        return
    end
    logoSymbol.Image, logoWordmark.Image = asset, asset
    local deadline = os.clock() + 8
    repeat
        if destroyed or not gui.Parent then return end
        if logoSymbol.IsLoaded and logoWordmark.IsLoaded then
            logo.Visible, fallbackTitle.Visible = false, false
            logoSymbol.ImageTransparency, logoWordmark.ImageTransparency = 0, 0
            return
        end
        task.wait(0.1)
    until os.clock() >= deadline
    if not destroyed then warn("[SOUZADAS] Imagem nao carregou; mantendo logo de reserva.") end
end)
local keyHint = button(panel, "RightShift", 804, 23, 122, 34)
local close = button(panel, "×", 945, 21, 36, 36)
close.BackgroundTransparency = 1
close.TextSize = 30
close:FindFirstChildOfClass("UIStroke").Transparency = 1
line(panel, 0, 84, 1000)
line(panel, 0, 129, 1000)
line(panel, 0, 491, 1000)

local pages, tabs = {}, {}
local selectedTab = "Aimbot"
for index, name in ipairs({"Aimbot", "ESP", "Jogador"}) do
    local tab = button(panel, name, 29 + (index - 1) * 136, 86, 124, 42)
    tab.BackgroundTransparency = 1
    tab:FindFirstChildOfClass("UIStroke").Transparency = 1
    tab.TextSize = 17
    local underline = make("Frame", {
        Position = UDim2.new(0, 7, 1, -4), Size = UDim2.new(1, -14, 0, 3),
        BackgroundColor3 = purple, BorderSizePixel = 0,
    }, tab)
    corner(underline, 3)
    tabs[name] = {button = tab, underline = underline}
    pages[name] = make("Frame", {
        Position = UDim2.fromOffset(22, 146), Size = UDim2.fromOffset(956, 328),
        BackgroundTransparency = 1, Visible = name == selectedTab,
    }, panel)
end
local function showTab(name)
    selectedTab = name
    activeSlider = nil
    for key, page in pairs(pages) do
        page.Visible = key == name
        tabs[key].underline.Visible = key == name
        tabs[key].button.TextColor3 = key == name and purple or muted
    end
end
for name, tab in pairs(tabs) do
    local tabName = name
    listen(tab.button.Activated, function() showTab(tabName) end)
end
showTab("Aimbot")

local function card(page, x, title, description, icon)
    local frame = make("Frame", {
        Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(469, 328),
        BackgroundColor3 = Color3.fromRGB(27, 22, 39), BorderSizePixel = 0,
    }, page)
    corner(frame, 16)
    stroke(frame, Color3.fromRGB(95, 73, 125), 0.3)
    gradient(frame, Color3.fromRGB(30, 25, 43), Color3.fromRGB(19, 17, 29), 65)
    local tile = button(frame, icon, 22, 14, 48, 48)
    tile.TextSize = 27
    tile.TextColor3 = Color3.fromRGB(214, 168, 255)
    gradient(tile, Color3.fromRGB(88, 44, 126), Color3.fromRGB(42, 27, 62))
    label(frame, title, 89, 14, 367, 29, 22, light, true)
    label(frame, description, 89, 43, 365, 20, 12, muted)
    line(frame, 22, 74, 425)
    return frame
end
local aimLeft = card(pages.Aimbot, 0, "Assistência de mira", "Ajuste a seleção e o movimento da câmera", "⊕")
local aimRight = card(pages.Aimbot, 487, "Precisão e alcance", "Defina os limites da assistência", "◇")
local espLeft = card(pages.ESP, 0, "Visualização de jogadores", "Escolha as informações exibidas", "◉")
local espRight = card(pages.ESP, 487, "Filtros e alcance", "Controle a exibição dos jogadores", "◇")
local speedLeft = card(pages.Jogador, 0, "Movimentação", "Ajuste a velocidade de caminhada", "»")
local speedRight = card(pages.Jogador, 487, "Estado do personagem", "Acompanhe a velocidade atual", "◇")

local function toggle(parent, title, key, y, onChanged)
    label(parent, title, 25, y, 350, 35, 15)
    local control = button(parent, "", 398, y + 4, 47, 26)
    corner(control, 13)
    local knob = make("Frame", {
        Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = Color3.fromRGB(245, 236, 255), BorderSizePixel = 0,
    }, control)
    corner(knob, 10)
    local function refresh()
        local enabled = settings[key]
        animate(control, {BackgroundColor3 = enabled and purple or Color3.fromRGB(49, 42, 61)})
        animate(knob, {Position = UDim2.fromOffset(enabled and 24 or 3, 3)})
    end
    table.insert(refreshers, refresh)
    listen(control.Activated, function()
        settings[key] = not settings[key]
        if onChanged then onChanged() end
        for _, fn in ipairs(refreshers) do fn() end
    end)
    refresh()
end
local function slider(parent, title, key, min, max, unit, y, onChanged)
    label(parent, title, 25, y, 280, 25, 16)
    local value = label(parent, "", 294, y, 150, 25, 15, muted)
    value.TextXAlignment = Enum.TextXAlignment.Right
    local hit = make("TextButton", {
        Position = UDim2.fromOffset(25, y + 28), Size = UDim2.fromOffset(419, 24),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
    }, parent)
    local track = make("Frame", {
        Position = UDim2.fromOffset(0, 9), Size = UDim2.new(1, 0, 0, 7),
        BackgroundColor3 = Color3.fromRGB(57, 46, 77), BorderSizePixel = 0,
    }, hit)
    corner(track, 4)
    local fill = make("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = purple, BorderSizePixel = 0}, track)
    corner(fill, 4)
    gradient(fill, Color3.fromRGB(209, 155, 255), Color3.fromRGB(160, 80, 234), 0)
    local knob = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(15, 15),
        Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = light, BorderSizePixel = 0,
    }, track)
    corner(knob, 8)
    stroke(knob, purple, 0.1)
    local function refresh()
        local fraction = math.clamp((settings[key] - min) / (max - min), 0, 1)
        value.Text = key == "Response" and settings[key] == max
            and "30 · direta" or tostring(settings[key]) .. unit
        fill.Size = UDim2.fromScale(fraction, 1)
        knob.Position = UDim2.fromScale(fraction, 0.5)
    end
    local function update(x)
        if track.AbsoluteSize.X <= 0 then return end
        local fraction = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        settings[key] = math.clamp(math.floor(min + fraction * (max - min) + 0.5), min, max)
        if onChanged then onChanged() end
        -- Alcance e compartilhado entre as duas abas.
        for _, fn in ipairs(refreshers) do fn() end
    end
    listen(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeSlider = update
            update(input.Position.X)
        end
    end)
    table.insert(refreshers, refresh)
    refresh()
end

toggle(aimLeft, "Ativar aimbot", "Aim", 84)
toggle(aimLeft, "Ignorar mesma equipe", "TeamCheck", 125)
toggle(aimLeft, "Checar paredes", "WallCheck", 166)
for _, y in ipairs({123, 164, 205, 262}) do line(aimLeft, 25, y, 419) end
label(aimLeft, "Ponto de mira", 25, 214, 180, 35, 15)
local head = button(aimLeft, "Cabeça", 207, 216, 119, 33)
local torso = button(aimLeft, "Tronco", 326, 216, 119, 33)
local function refreshParts()
    for _, item in ipairs({{head, "Head"}, {torso, "HumanoidRootPart"}}) do
        item[1].BackgroundColor3 = settings.AimPart == item[2]
            and Color3.fromRGB(126, 54, 190) or Color3.fromRGB(31, 26, 42)
    end
end
table.insert(refreshers, refreshParts)
listen(head.Activated, function() settings.AimPart = "Head"; refreshParts() end)
listen(torso.Activated, function() settings.AimPart = "HumanoidRootPart"; refreshParts() end)
refreshParts()
label(aimLeft, "Ativação", 25, 274, 130, 35, 15)
local activation = button(aimLeft, "", 151, 275, 294, 36)
local activationNames = {"Segurar botão direito", "Segurar Alt esquerdo", "Segurar tecla E"}
local activationKeys = {[2] = Enum.KeyCode.LeftAlt, [3] = Enum.KeyCode.E}
local function refreshBindings()
    activation.Text = activationNames[settings.Activation] .. "  ▾"
    keyHint.Text = captureTarget == "PanelKey" and "Tecla..." or settings.PanelKey.Name
    if noclipKeyButton then
        noclipKeyButton.Text = captureTarget == "NoclipKey"
            and "Pressione uma tecla..." or settings.NoclipKey.Name .. " · trocar"
    end
    if footerHint then
        footerHint.Text = captureTarget and "Escolha o atalho · Esc cancela"
            or settings.PanelKey.Name .. " painel · " .. settings.NoclipKey.Name .. " noclip · clique no atalho para trocar"
    end
end
local function beginCapture(target)
    captureTarget = target
    dragging, activeSlider = false, nil
    refreshBindings()
end
local function cancelCapture()
    captureTarget = nil
    refreshBindings()
end
table.insert(refreshers, refreshBindings)
listen(activation.Activated, function()
    repeat
        settings.Activation = settings.Activation % #activationNames + 1
    until activationKeys[settings.Activation] ~= settings.PanelKey
        and activationKeys[settings.Activation] ~= settings.NoclipKey
    refreshBindings()
end)
listen(keyHint.Activated, function() beginCapture("PanelKey") end)
refreshBindings()
slider(aimRight, "Campo de visão", "FOV", 30, 500, " px", 82)
slider(aimRight, "Velocidade da mira", "Response", 1, 30, "", 143)
slider(aimRight, "Distância máxima", "MaxDistance", 100, 5000, " studs", 204)
line(aimRight, 25, 265, 419)
toggle(aimRight, "Mostrar círculo de FOV", "ShowFOV", 275)

toggle(espLeft, "Ativar ESP", "ESP", 84)
toggle(espLeft, "Mostrar nomes", "Names", 128)
toggle(espLeft, "Mostrar vida", "Health", 172)
toggle(espLeft, "Mostrar distância", "Distance", 216)
label(espLeft, "Contorno e preenchimento em roxo", 25, 281, 420, 23, 12, muted)
toggle(espRight, "Ignorar mesma equipe", "TeamCheck", 84)
toggle(espRight, "Através de paredes", "ThroughWalls", 128)
line(espRight, 25, 175, 419)
slider(espRight, "Distância máxima", "MaxDistance", 100, 5000, " studs", 191)
label(espRight, "O alcance e o filtro de equipe valem nas duas abas.", 25, 281, 420, 23, 11, muted)

toggle(speedLeft, "Ativar speed", "Speed", 88, syncSpeed)
line(speedLeft, 25, 137, 419)
slider(speedLeft, "Velocidade", "SpeedValue", 8, 80, " studs/s", 155, syncSpeed)
toggle(speedLeft, "Ativar noclip", "Noclip", 221, syncNoclip)
line(speedLeft, 25, 266, 419)
label(speedLeft, "Tecla do noclip", 25, 277, 180, 32, 14)
noclipKeyButton = button(speedLeft, "", 218, 277, 227, 32)
listen(noclipKeyButton.Activated, function() beginCapture("NoclipKey") end)
refreshBindings()
local speedState = label(speedRight, "Desativado", 25, 88, 419, 34, 21, purple, true)
local speedCurrentLabel = label(speedRight, "Velocidade atual: —", 25, 151, 419, 28, 16)
local speedOriginalLabel = label(speedRight, "Valor anterior: —", 25, 199, 419, 28, 15, muted)
local noclipStateLabel = label(speedRight, "Noclip: desativado", 25, 254, 419, 28, 16, muted)
local function refreshSpeedStatus()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not settings.Speed then speedState.Text = "Desativado"
    elseif not humanoid or humanoid.Health <= 0 then speedState.Text = "Aguardando personagem"
    elseif humanoid ~= speedHumanoid or humanoid.WalkSpeed ~= speedLastApplied then
        speedState.Text = "Valor alterado pelo jogo"
    else speedState.Text = "Ativado" end
    speedCurrentLabel.Text = "Velocidade atual: " .. (humanoid and tostring(humanoid.WalkSpeed) .. " studs/s" or "—")
    speedOriginalLabel.Text = "Valor anterior: " .. (speedOriginal and tostring(speedOriginal) .. " studs/s" or "—")
    noclipStateLabel.Text = not settings.Noclip and "Noclip: desativado"
        or (noclipCharacter and "Noclip: ativado" or "Noclip: aguardando personagem")
end
table.insert(refreshers, refreshSpeedStatus)
listen(player.CharacterAdded, watchSpeedCharacter)
listen(player.CharacterRemoving, function(character)
    if speedHumanoid and speedHumanoid:IsDescendantOf(character) then restoreSpeed() end
    disconnectSpeedWatchers()
end)
watchSpeedCharacter(player.Character)
listen(RunService.Stepped, function()
    if settings.Noclip then syncNoclip() end
end)
listen(player.CharacterRemoving, function(character)
    if character == noclipCharacter then restoreNoclip() end
end)
refreshSpeedStatus()

label(panel, "⌨", 30, 511, 40, 30, 25, muted)
footerHint = label(panel, "", 83, 511, 680, 30, 13, muted)
refreshBindings()
local reset = button(panel, "Restaurar padrões", 785, 506, 190, 38)
listen(reset.Activated, function()
    activeSlider = nil
    captureTarget = nil
    suppressAimUntilRelease = true
    for key, value in pairs(defaults) do settings[key] = value end
    syncSpeed()
    syncNoclip()
    for _, refresh in ipairs(refreshers) do refresh() end
end)

local header = make("Frame", {
    Position = UDim2.fromOffset(115, 0), Size = UDim2.fromOffset(680, 82),
    BackgroundTransparency = 1, Active = true, ZIndex = 5,
}, panel)
listen(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, dragStart, panelStart = true, input.Position, panel.Position
    end
end)
local function clampPanel()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local half = Vector2.new(1000 * scale.Scale, 564 * scale.Scale) / 2
    local x = panel.Position.X.Scale * viewport.X + panel.Position.X.Offset
    local y = panel.Position.Y.Scale * viewport.Y + panel.Position.Y.Offset
    panel.Position = UDim2.fromOffset(
        math.clamp(x, half.X + 6, math.max(half.X + 6, viewport.X - half.X - 6)),
        math.clamp(y, half.Y + 6, math.max(half.Y + 6, viewport.Y - half.Y - 6))
    )
end
local previousViewport
local function fitPanel(camera)
    local viewport = camera.ViewportSize
    if viewport ~= previousViewport then
        previousViewport = viewport
        scale.Scale = math.max(0.05, math.min(1, (viewport.X - 24) / 1000, (viewport.Y - 24) / 564))
        clampPanel()
    end
end
listen(Input.InputChanged, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    if activeSlider then activeSlider(input.Position.X)
    elseif dragging then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + delta.X,
            panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
        clampPanel()
    end
end)
listen(Input.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, activeSlider = false, nil
    end
end)
local function togglePanel()
    panel.Visible = not panel.Visible
    dragging, activeSlider = false, nil
    cancelCapture()
end
-- BEGIN SHORTCUT HANDLER
local function handleKeyInput(input, processed)
    if captureTarget then
        if input.KeyCode == Enum.KeyCode.Escape then cancelCapture(); return end
        if Input:GetFocusedTextBox() then return end
        local candidate
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode ~= Enum.KeyCode.Unknown then
            candidate = input.KeyCode
        end
        if not candidate then return end
        -- Os atalhos nao compartilham a mesma tecla para evitar conflitos.
        local otherKey = captureTarget == "PanelKey" and settings.NoclipKey or settings.PanelKey
        local conflict = candidate == activationKeys[settings.Activation] or candidate == otherKey
        if conflict then
            footerHint.Text = "Tecla já usada · escolha outra ou Esc para cancelar"
            return
        end
        settings[captureTarget] = candidate
        suppressAimUntilRelease = true
        cancelCapture()
        return
    end
    if processed or Input:GetFocusedTextBox()
        or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode == settings.PanelKey then
        togglePanel()
    elseif input.KeyCode == settings.NoclipKey then
        settings.Noclip = not settings.Noclip
        syncNoclip()
        for _, refresh in ipairs(refreshers) do refresh() end
    end
end
-- END SHORTCUT HANDLER
listen(Input.InputBegan, handleKeyInput)
listen(Input.WindowFocusReleased, function()
    focused, dragging, activeSlider = false, false, nil
    suppressAimUntilRelease = true
    cancelCapture()
end)
listen(Input.WindowFocused, function() focused = true end)

local circle = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(300, 300),
    BackgroundTransparency = 1, Visible = false, ZIndex = 0,
}, gui)
corner(circle, 10000)
stroke(circle, purple, 0.22)
local function removeEffect(target)
    local effect = effects[target]
    if not effect then return end
    effect.highlight:Destroy()
    effect.billboard:Destroy()
    effects[target] = nil
end
local function getEffect(target, character, root)
    local effect = effects[target]
    if effect and effect.character == character then
        effect.billboard.Adornee = character:FindFirstChild("Head") or root
        return effect
    end
    removeEffect(target)
    local highlight = make("Highlight", {
        Adornee = character, FillColor = purple, OutlineColor = light,
        FillTransparency = 0.75, OutlineTransparency = 0.08, Enabled = false,
    }, gui)
    local billboard = make("BillboardGui", {
        Adornee = character:FindFirstChild("Head") or root,
        Size = UDim2.fromOffset(220, 52), StudsOffset = Vector3.new(0, 2.7, 0),
        Enabled = false,
    }, gui)
    local text = label(billboard, "", 0, 0, 220, 52, 12, light, true)
    text.TextXAlignment = Enum.TextXAlignment.Center
    text.TextStrokeTransparency = 0.25
    effect = {character = character, highlight = highlight, billboard = billboard, text = text}
    effects[target] = effect
    return effect
end
local roster = Players:GetPlayers()
listen(Players.PlayerAdded, function() roster = Players:GetPlayers() end)
listen(Players.PlayerRemoving, function(target)
    removeEffect(target)
    local index = table.find(roster, target)
    if index then table.remove(roster, index) end
end)
local function getCharacter(target)
    if target == player or target.Parent ~= Players then return end
    if settings.TeamCheck and not player.Neutral and not target.Neutral
        and player.Team ~= nil and player.Team == target.Team then return end
    local character = target.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return end
    return character, humanoid, root
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
-- Usa CanQuery: paredes sem colisao fisica ainda podem bloquear a mira.
rayParams.RespectCanCollide = false
local function clearPath(origin, character, position)
    local direction = position - origin
    if direction.Magnitude < 0.001 then return true end
    local hit = workspace:Raycast(origin, direction, rayParams)
    return hit == nil or hit.Instance:IsDescendantOf(character)
end
local function visible(camera, character, position, shooterOrigin)
    if not clearPath(camera.CFrame.Position, character, position) then return false end
    -- A camera em terceira pessoa pode enxergar alem da quina. A segunda
    -- consulta impede adquirir um alvo oculto a partir do personagem.
    -- A cabeca e uma referencia de visibilidade; nao e o cano real da arma.
    if shooterOrigin and not clearPath(shooterOrigin, character, position) then return false end
    return true
end
local function activationHeld()
    local held
    if settings.Activation == 1 then
        held = Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    else
        held = Input:IsKeyDown(activationKeys[settings.Activation])
    end
    if suppressAimUntilRelease then
        if not held then suppressAimUntilRelease = false end
        return false
    end
    return held
end
local function pointerOnPanel()
    if not panel.Visible then return false end
    local mouse = Input:GetMouseLocation()
    local position, size = panel.AbsolutePosition, panel.AbsoluteSize
    return mouse.X >= position.X and mouse.Y >= position.Y
        and mouse.X <= position.X + size.X and mouse.Y <= position.Y + size.Y
end

local effectElapsed = 0
local lockedTarget, aimRotation, aimCamera, aimCharacter
local function clearAim()
    lockedTarget, aimRotation, aimCamera, aimCharacter = nil, nil, nil, nil
end
local function finitePosition(position)
    return position.X == position.X and position.Y == position.Y and position.Z == position.Z
        and math.abs(position.X) < math.huge and math.abs(position.Y) < math.huge
        and math.abs(position.Z) < math.huge
end
local function render(dt)
    local camera = workspace.CurrentCamera
    if not camera then
        clearAim()
        circle.Visible = false
        for _, effect in pairs(effects) do
            effect.highlight.Enabled, effect.billboard.Enabled = false, false
        end
        return
    end
    fitPanel(camera)
    local localCharacter = player.Character
    local localHumanoid = localCharacter and localCharacter:FindFirstChildOfClass("Humanoid")
    local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
    local alive = localHumanoid and localHumanoid.Health > 0 and localRoot and localRoot:IsA("BasePart")
    local origin = alive and localRoot.Position or camera.CFrame.Position
    local localHead = localCharacter and localCharacter:FindFirstChild("Head")
    local shooterOrigin = localHead and localHead:IsA("BasePart") and localHead.Position or origin
    local center = camera.ViewportSize / 2
    circle.Position = UDim2.fromOffset(center.X, center.Y)
    circle.Size = UDim2.fromOffset(settings.FOV * 2, settings.FOV * 2)
    circle.Visible = settings.Aim and settings.ShowFOV and alive and true or false
    -- Atualiza a liberacao mesmo com a mira desligada ou durante a captura.
    local held = activationHeld()
    local canAim = settings.Aim and alive and focused and held and captureTarget == nil
        and Input:GetFocusedTextBox() == nil and not dragging
        and activeSlider == nil and not pointerOnPanel()
    if not canAim or camera ~= aimCamera or localCharacter ~= aimCharacter then
        clearAim()
    end
    rayParams.FilterDescendantsInstances = localCharacter and {localCharacter, camera} or {camera}
    effectElapsed = effectElapsed + dt
    local updateEffects = effectElapsed >= 0.1
    if updateEffects then effectElapsed = 0; refreshSpeedStatus() end
    local best, bestDistance, retained = nil, settings.FOV, nil
    for _, target in ipairs(roster) do
        local character, humanoid, root = getCharacter(target)
        local distance = root and (root.Position - origin).Magnitude or math.huge
        local inRange = character and distance <= settings.MaxDistance
        if updateEffects then
            local effect = effects[target]
            if effect then effect.highlight.Enabled, effect.billboard.Enabled = false, false end
            if settings.ESP and inRange then
                effect = getEffect(target, character, root)
                effect.highlight.Enabled = true
                effect.highlight.DepthMode = settings.ThroughWalls
                    and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
                effect.billboard.AlwaysOnTop = settings.ThroughWalls
                local text = {}
                if settings.Names then table.insert(text, target.DisplayName) end
                if settings.Distance then table.insert(text, math.floor(distance + 0.5) .. " studs") end
                if settings.Health then table.insert(text, math.floor(humanoid.Health + 0.5) .. " HP") end
                effect.text.Text = table.concat(text, "  ·  ")
                effect.billboard.Enabled = #text > 0
            end
        end
        if canAim and inRange then
            local part = character:FindFirstChild(settings.AimPart)
            -- Tronco visivel em R15/R6 em vez do root, que pode ter offset.
            if settings.AimPart == "HumanoidRootPart" then
                part = character:FindFirstChild("UpperTorso")
                    or character:FindFirstChild("Torso") or part
            end
            if part and part:IsA("BasePart") and finitePosition(part.Position) then
                local projected, onScreen = camera:WorldToViewportPoint(part.Position)
                if onScreen and projected.Z > 0 then
                    local distanceToCenter = (Vector2.new(projected.X, projected.Y) - center).Magnitude
                    if distanceToCenter <= settings.FOV
                        and (not settings.WallCheck or visible(camera, character, part.Position, shooterOrigin)) then
                        local candidate = {player = target, character = character, part = part}
                        if target == lockedTarget then retained = candidate end
                        if distanceToCenter < bestDistance or best == nil then
                            best, bestDistance = candidate, distanceToCenter
                        end
                    end
                end
            end
        end
    end
    -- Mantem o mesmo alvo enquanto valido; soltar o botao libera o alvo.
    best = retained or best
    if best then
        if lockedTarget ~= best.player then aimRotation = nil end
        lockedTarget, aimCamera, aimCharacter = best.player, camera, localCharacter
        local position = camera.CFrame.Position
        -- Le a posicao atual da parte, nao uma previsao ou offset inventado.
        local point = best.part.Position
        if best.part:IsDescendantOf(best.character) and finitePosition(point)
            and (point - position).Magnitude > 0.001
            and (not settings.WallCheck or visible(camera, best.character, point, shooterOrigin)) then
            local desired = CFrame.lookAt(position, point).Rotation
            local alpha = settings.Response >= 30 and 1
                or 1 - math.exp(-settings.Response * math.clamp(dt, 0, 0.1))
            -- Acumula nossa rotacao: a camera do jogo pode recomecar de outra
            -- orientacao no proximo frame. Lerp da camera bruta gerava desvio.
            aimRotation = (aimRotation or camera.CFrame.Rotation):Lerp(desired, alpha)
            camera.CFrame = CFrame.new(position) * aimRotation
        else
            clearAim()
        end
    else
        clearAim()
    end
end

cleanup = function()
    if destroyed then return end
    destroyed = true
    disconnectSpeedWatchers()
    restoreSpeed()
    restoreNoclip()
    clearAim()
    RunService:UnbindFromRenderStep(binding)
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, tween in pairs(animations) do tween:Cancel() end
    for _, effect in pairs(effects) do effect.highlight:Destroy(); effect.billboard:Destroy() end
    table.clear(effects)
    table.clear(animations)
    gui:Destroy()
    if env.__SouzadasPanel == cleanup then env.__SouzadasPanel = nil end
end
env.__SouzadasPanel = cleanup
listen(close.Activated, cleanup)
-- Aplica depois das prioridades padrao de camera/personagem.
RunService:BindToRenderStep(binding, Enum.RenderPriority.Last.Value + 1, render)
