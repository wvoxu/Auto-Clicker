-- Auto Clicker (by wvoxu) - locked-position autoclicker (Orbital UI)

-- SAVED SETTINGS --
-- Settings are kept in a small file in your executor's workspace folder and loaded on start.
-- (Whether the clicker is on or off is never saved.)
local HttpService = game:GetService("HttpService")
local SAVE_FILE = "WvoxuAutoClicker.json"
local saved = {}
local canSave = (writefile and readfile and isfile) ~= nil
if canSave and isfile(SAVE_FILE) then
    local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(SAVE_FILE)) end)
    if ok and type(decoded) == "table" then
        saved = decoded
    end
end

local function keyFromName(name, fallback)
    if type(name) ~= "string" then return fallback end
    local ok, key = pcall(function() return Enum.KeyCode[name] end)
    if ok and key then return key end
    return fallback
end

local uiKey = keyFromName(saved.uiKey, Enum.KeyCode.RightShift)
local saveSettings = function() end -- replaced once the UI exists

-- LOADING --
local function safeloadstring(url)
    local source = game:HttpGet(url)
    -- Key for hiding/showing the window: saved key, else RightShift (library default is F3).
    -- ChangedCallback reports rebinds back to this script so they can be saved.
    do
        local a, b = source:find("Default = Enum.KeyCode.F3,", 1, true)
        if a then
            source = source:sub(1, a - 1)
                .. "Default = Enum.KeyCode." .. uiKey.Name .. ","
                .. " ChangedCallback = function(k) local g = (getgenv and getgenv()) or _G;"
                .. " if g.__WvoxuAC_SaveUiKey then g.__WvoxuAC_SaveUiKey(k) end end,"
                .. source:sub(b + 1)
        end
    end
    -- Skip the logo intro (and the wait that comes with it)
    source = source:gsub("self:Intro%(%)%s*task%.wait%(1%)", "", 1)
    -- Remove the F2 "hide whole GUI" keybind so RightShift is the only UI toggle
    source = source:gsub('self:AddSettingKeybind%(%{%s*Text = "Toggle SBEUI GUI".-%}%)', "", 1)
    -- Rename the remaining toggle
    source = source:gsub("Toggle SBEUI Frame", "Toggle UI", 1)
    -- No search bar row: shrink the title bar to just the title
    source = source:gsub("self%.Config%.TitleHeight %+ 35", "self.Config.TitleHeight")

    -- Notifications: use the theme's colours instead of the hardcoded cyan/dark look.
    -- The notification is a CanvasGroup, and a UIGradient on a CanvasGroup tints EVERYTHING inside it
    -- (text included). The old dark gradient is what made the text look dim, so make it neutral white
    -- and put the real colour on the background instead.
    local function replace(old, new)
        local a, b = source:find(old, 1, true)
        if a then
            source = source:sub(1, a - 1) .. new .. source:sub(b + 1)
        end
    end
    replace("config.AccentColor or Color3.fromRGB(0, 200, 255)", "config.AccentColor or self.Colors.AccentColor")
    replace("frame.BackgroundColor3 = Color3.fromRGB(100, 100, 100)", "frame.BackgroundColor3 = self.Colors.MainFrameColor")
    replace("Color3.fromRGB(80, 80, 90)", "Color3.fromRGB(255, 255, 255)")
    replace("Color3.fromRGB(40, 40, 45)", "Color3.fromRGB(255, 255, 255)")
    replace("title.TextColor3 = Color3.fromRGB(255, 255, 255)", "title.TextColor3 = self.Colors.TitleColor")
    replace("msg.TextColor3 = Color3.fromRGB(245, 245, 245)", "msg.TextColor3 = self.Colors.LabelColor")
    replace("closeBtn.TextColor3 = Color3.fromRGB(255, 0, 0)", "closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)")
    -- Hide the thin accent strip down the left edge
    replace("accent.Size = UDim2.new(0, 5, 1, 0)", "accent.Size = UDim2.new(0, 0, 1, 0)")
    -- Hide the white countdown bar at the bottom of notifications
    replace("progressBarBackground.BackgroundTransparency = 0.7", "progressBarBackground.BackgroundTransparency = 1")
    replace("progressBar.BackgroundColor3 = Color3.fromRGB(255,255,255)", "progressBar.BackgroundTransparency = 1")

    local func, err = loadstring(source)
    if func then
        return func()
    end
    warn("LOADSTRING FAILED: " .. tostring(err))
    return nil
end

-- If this script was already run, shut the old copy down first. Otherwise the old window, key
-- listener and click loop keep running in the background next to the new ones.
local sharedEnv = (getgenv and getgenv()) or _G
if sharedEnv.__WvoxuAutoClickerCleanup then
    pcall(sharedEnv.__WvoxuAutoClickerCleanup)
    sharedEnv.__WvoxuAutoClickerCleanup = nil
end

local UILibrary = safeloadstring("https://raw.githubusercontent.com/SugaBlaz/UI-Library/refs/heads/main/Orbital%20UI.lua")

-- SERVICES --
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- VARIABLES --
local autoClicking = false
local clickSpeed = (tonumber(saved.clickSpeed) and tonumber(saved.clickSpeed) > 0) and tonumber(saved.clickSpeed) or 0.1
local toggleKey = keyFromName(saved.key, Enum.KeyCode.KeypadPlus) -- change it in the UI (any key works)
local randomDelay = saved.randomDelay == true            -- vary the delay by +-25%
local followCursor = saved.followCursor == true          -- click wherever the cursor is instead of a fixed spot
local notificationsOn = saved.notifications ~= false
local clickLimit = math.max(0, math.floor(tonumber(saved.clickLimit) or 0)) -- 0 = unlimited
local clickCount = 0
local mouseButtonName = (saved.mouseButton == "Right" or saved.mouseButton == "Middle") and saved.mouseButton or "Left"
local mouseButton = 0                     -- 0 = left, 1 = right, 2 = middle (set from mouseButtonName below)
local lockedPos = Vector2.new(0, 0)       -- where the cursor was when you started; clicks land here
local lastKeyChange = 0
local statusLabel
local alive = true
local keyConn, tipConn

local MOUSE_BUTTONS = { Left = 0, Right = 1, Middle = 2 }
mouseButton = MOUSE_BUTTONS[mouseButtonName]
local ready = false -- settings are only written once the UI has finished loading

-- UI --
local ui = UILibrary.Main.new({
    TitleText = "Auto Clicker (by wvoxu)",
    Size = UDim2.new(0, 300, 0, 260),
    Position = UDim2.new(0.5, -150, 0.5, -130),
    Theme = "Ghost",
    KeySystemEnabled = false,
    SaveOnExit = false,
    NotifcationSound = "", -- silent notifications
})
ui:CreateUI()

saveSettings = function()
    if not (canSave and ready) then return end
    pcall(function()
        writefile(SAVE_FILE, HttpService:JSONEncode({
            key = toggleKey.Name,
            uiKey = uiKey.Name,
            clickSpeed = clickSpeed,
            clickLimit = clickLimit,
            mouseButton = mouseButtonName,
            randomDelay = randomDelay,
            followCursor = followCursor,
            notifications = notificationsOn,
        }))
    end)
end

sharedEnv.__WvoxuAC_SaveUiKey = function(newKey)
    uiKey = newKey
    saveSettings()
end

sharedEnv.__WvoxuAutoClickerCleanup = function()
    alive = false
    autoClicking = false
    if keyConn then keyConn:Disconnect() end
    if tipConn then tipConn:Disconnect() end
    pcall(function() ui.ScreenGui:Destroy() end)
end

-- Make the ON/OFF text easy to read (Ghost's grey-on-grey OFF was hard to see)
ui.Colors.ToggleColorOFF = Color3.fromRGB(255, 95, 95)
ui.Colors.ToggleColorON = Color3.fromRGB(95, 230, 130)
ui.Colors.ToggleColor = Color3.fromRGB(18, 18, 18)

-- Remove the redundant tab column + search bar and tidy the title bar
ui.TabScrollingFrame.Visible = false
ui.SearchFrame.Visible = false
ui.TitleText.Position = UDim2.new(0, 12, 0, 0)
ui.MinimizeButton.Parent.Position = UDim2.new(1, 0, 0, 0)
ui.SettingsBtn.Position = UDim2.new(1, -90, 0, 2.5)

-- Fill the space the tab column used to take: widen content to the full window width
local contentPadding = ui.ScrollingFrame:FindFirstChildOfClass("UIPadding")
if contentPadding then
    contentPadding.PaddingLeft = UDim.new(0, 0)
    contentPadding.PaddingRight = UDim.new(0, 0)
end
-- Elements are (full width - 24px) and default to left-aligned; centre them for an even 12px margin each side
ui.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- HELPERS --
local function notify(title, text)
    if not notificationsOn then return end
    task.spawn(function()
        ui:Notify({
            Title = title,
            Text = text,
            Duration = 2,
            StartPosition = UDim2.new(1, 0, 0.776, 0),
            EndPosition = UDim2.new(0.724, 0, 0.776, 0),
            TweenTime = 0.5,
        })
    end)
end

-- Is the cursor over this window? Tracked with the elements' own hover events (hooked up at the
-- bottom of the script). Used so the clicker never clicks the window's own buttons.
local uiHover = {}
local function overUI()
    if not (ui.ScreenGui.Enabled and ui.UIWrapper.Visible) then
        table.clear(uiHover) -- window hidden: drop any stale state
        return false
    end
    return next(uiHover) ~= nil
end

local function fmtPos(v)
    return string.format("%d, %d", v.X, v.Y)
end

local function setStatus()
    if statusLabel then
        statusLabel.Text = "Status: " .. (autoClicking and "ON" or "OFF") .. "  |  Key: " .. toggleKey.Name
    end
end

local function startClicking()
    if autoClicking then return end
    if not followCursor and overUI() then
        -- the saved spot would be on the window itself, so every click would hit its buttons
        notify("Can't start yet", "Your cursor is over this window. Move the window or your cursor.")
        return
    end
    lockedPos = UserInputService:GetMouseLocation() -- remember where the mouse is right now
    clickCount = 0
    autoClicking = true
    setStatus()
    notify("Auto Clicker ON", followCursor and "Following your cursor" or ("Clicking at " .. fmtPos(lockedPos)))
end

local function stopClicking(reason)
    if not autoClicking then return end
    autoClicking = false
    setStatus()
    if reason then
        notify("Auto Clicker OFF", reason)
    else
        notify("Auto Clicker OFF", clickCount .. " clicks sent")
    end
end

-- AUTOCLICK LOOP --
-- Only sends clicks at the chosen position. It never touches MouseBehavior,
-- so it can't drag the camera.
task.spawn(function()
    while alive do
        if autoClicking then
            if followCursor and overUI() then
                task.wait(0.05) -- cursor is on this window: pause instead of clicking its buttons
            else
                local pos = followCursor and UserInputService:GetMouseLocation() or lockedPos
                VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, mouseButton, true, game, 0)
                task.wait()
                VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, mouseButton, false, game, 0)
                clickCount = clickCount + 1

                if clickLimit > 0 and clickCount >= clickLimit then
                    stopClicking("Click limit reached (" .. clickLimit .. ")")
                else
                    local delay = clickSpeed
                    if randomDelay then
                        delay = clickSpeed * (0.75 + math.random() * 0.5)
                    end
                    task.wait(delay)
                end
            end
        else
            task.wait(0.1)
        end
    end
end)

-- KEYBIND HANDLING --
-- Done here (not in the UI's Callback) so every key works, including shift/keypad keys.
keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode ~= toggleKey then return end
    if UserInputService:GetFocusedTextBox() then return end -- typing in a textbox/chat
    if os.clock() - lastKeyChange < 0.3 then return end     -- the press that just rebound the key
    if gameProcessed and not (toggleKey.Name:find("Shift") or toggleKey.Name:find("Keypad")
        or toggleKey.Name:find("Control") or toggleKey.Name:find("Alt")) then
        return
    end

    if autoClicking then
        stopClicking()
    else
        startClicking()
    end
end)

-- AUTOCLICKER SECTION --
statusLabel = ui:AddLabel("Status: OFF  |  Key: " .. toggleKey.Name)
statusLabel.TextXAlignment = Enum.TextXAlignment.Center

ui:AddKeybind({
    Text = "AutoClicker Key",
    Default = toggleKey,
    SavingEnabled = false,
    ChangedCallback = function(newKey)
        lastKeyChange = os.clock()
        toggleKey = newKey
        stopClicking()
        setStatus()
        saveSettings()
    end,
})

-- Make the key boxes hug their text and grow leftwards from the right edge
local function fitKeyBoxes(container)
    for _, box in ipairs(container:GetDescendants()) do
        if box.Name == "BindDisplay" and box:IsA("TextButton") then
            box.AutomaticSize = Enum.AutomaticSize.X
            box.Size = UDim2.new(0, 0, 0, 22)
            box.TextXAlignment = Enum.TextXAlignment.Right
            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 8)
            pad.PaddingRight = UDim.new(0, 8)
            pad.Parent = box
        end
    end
end
fitKeyBoxes(ui.ScrollingFrame)        -- AutoClicker Key
fitKeyBoxes(ui.SettingScrollingFrame) -- Toggle UI key

ui:AddTextBox({
    Text = "Click Delay (s)",
    Default = tostring(clickSpeed),
    Placeholder = "0.1",
    SavingEnabled = false,
    Callback = function(text)
        local speed = tonumber(text)
        if speed and speed > 0 then
            clickSpeed = speed
            saveSettings()
        else
            warn("Invalid speed input")
        end
    end,
})

ui:AddTextBox({
    Text = "Click Limit (0 = unlimited)",
    Default = tostring(clickLimit),
    Placeholder = "0",
    SavingEnabled = false,
    Callback = function(text)
        local n = tonumber(text)
        if n and n >= 0 then
            clickLimit = math.floor(n)
            saveSettings()
        else
            warn("Invalid click limit")
        end
    end,
})

local buttonDropdown = ui:AddDropdown({
    Text = "Mouse Button",
    Default = mouseButtonName,
    Options = { "Left", "Right", "Middle" },
    SavingEnabled = false,
    Callback = function(option)
        mouseButton = MOUSE_BUTTONS[option] or 0
        mouseButtonName = MOUSE_BUTTONS[option] and option or "Left"
        saveSettings()
    end,
})
buttonDropdown:Set(mouseButtonName) -- the library starts dropdowns on "None"; show the real value

ui:AddToggle({
    Text = "Random Delay",
    Default = randomDelay,
    SavingEnabled = false,
    Callback = function(state)
        randomDelay = state
        saveSettings()
    end,
})

ui:AddToggle({
    Text = "Follow Cursor",
    Default = followCursor,
    SavingEnabled = false,
    Callback = function(state)
        followCursor = state
        saveSettings()
    end,
})

ui:AddToggle({
    Text = "Notifications",
    Default = notificationsOn,
    SavingEnabled = false,
    Callback = function(state)
        notificationsOn = state
        saveSettings()
    end,
})

-- Bold ON/OFF text on every toggle
for _, child in ipairs(ui.ScrollingFrame:GetChildren()) do
    local btn = child:FindFirstChild("ToggleButton")
    if btn then
        btn.Font = Enum.Font.GothamBold
    end
end

-- No outlines on text: the library puts a UIStroke on its text boxes and buttons, and on a
-- text object that stroke traces the letters. Remove them all.
for _, d in ipairs(ui.ScreenGui:GetDescendants()) do
    if d:IsA("UIStroke") and (d.Parent:IsA("TextLabel") or d.Parent:IsA("TextButton") or d.Parent:IsA("TextBox")) then
        d:Destroy()
    end
end

-- Track hover over the whole window (main frame, settings panel, every element)
do
    local objs = { ui.UIWrapper }
    for _, d in ipairs(ui.UIWrapper:GetDescendants()) do
        table.insert(objs, d)
    end
    for _, o in ipairs(objs) do
        if o:IsA("GuiObject") then
            o.MouseEnter:Connect(function() uiHover[o] = true end)
            o.MouseLeave:Connect(function() uiHover[o] = nil end)
        end
    end
end

-- HOVER TIPS --
-- Hover an option for a moment to see what it does.
local RunService = game:GetService("RunService")

local tipLabel = Instance.new("TextLabel")
tipLabel.Name = "HoverTip"
tipLabel.AutomaticSize = Enum.AutomaticSize.XY
tipLabel.Size = UDim2.new(0, 0, 0, 0)
tipLabel.BackgroundColor3 = ui.Colors.ButtonColor
tipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
tipLabel.Font = Enum.Font.Gotham
tipLabel.TextSize = 12
tipLabel.TextWrapped = true
tipLabel.ZIndex = 50
tipLabel.Visible = false
tipLabel.Parent = ui.ScreenGui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = tipLabel
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 5); pad.PaddingBottom = UDim.new(0, 5)
    pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = tipLabel
    local sc = Instance.new("UISizeConstraint"); sc.MaxSize = Vector2.new(230, math.huge); sc.Parent = tipLabel
    end

local tips = {} -- { frame = <element frame>, text = "..." }
local function addTip(container, frameName, text)
    local frame = container:FindFirstChild(frameName)
    if frame then
        table.insert(tips, { frame = frame, text = text, objects = {} })
    end
end

addTip(ui.ScrollingFrame, "Keybind_AutoClicker Key", "Press this key to start or stop. Click the box to change it.")
addTip(ui.ScrollingFrame, "TextBox_Click Delay (s)", "Seconds between clicks. 0.1 is about 10 clicks a second.")
addTip(ui.ScrollingFrame, "TextBox_Click Limit (0 = unlimited)", "Stops after this many clicks. 0 means it never stops.")
addTip(ui.ScrollingFrame, "Dropdown_Mouse Button", "Which mouse button it clicks with.")
addTip(ui.ScrollingFrame, "Toggle_Random Delay", "Changes the delay a little each click so the timing isn't even.")
addTip(ui.ScrollingFrame, "Toggle_Follow Cursor", "Clicks wherever your cursor is, instead of where you started.")
addTip(ui.ScrollingFrame, "Toggle_Notifications", "Pop-ups for on/off, the click limit and errors.")
addTip(ui.SettingScrollingFrame, "Keybind_Toggle UI", "Shows or hides this window.")

-- Hover is detected with the elements' own MouseEnter/MouseLeave events (instead of comparing
-- cursor coordinates), so it can't drift out of line with what's actually under the mouse.
local over = {}
for _, tip in ipairs(tips) do
    local objs = { tip.frame }
    for _, d in ipairs(tip.frame:GetDescendants()) do
        table.insert(objs, d)
    end
    for _, o in ipairs(objs) do
        if o:IsA("GuiObject") then
            table.insert(tip.objects, o)
            o.MouseEnter:Connect(function() over[o] = true end)
            o.MouseLeave:Connect(function() over[o] = nil end)
        end
    end
end

local function isShown(gui)
    local g = gui
    while g and g ~= ui.ScreenGui do
        if g:IsA("GuiObject") and not g.Visible then return false end
        g = g.Parent
    end
    return ui.ScreenGui.Enabled
end

local hovered, hoverSince = nil, 0
tipConn = RunService.Heartbeat:Connect(function()
    local found = nil
    if ui.ScreenGui.Enabled and ui.UIWrapper.Visible then
        for _, tip in ipairs(tips) do
            if isShown(tip.frame) then
                for _, o in ipairs(tip.objects) do
                    if over[o] then
                        found = tip
                        break
                    end
                end
            end
            if found then break end
        end
    else
        table.clear(over) -- window hidden: drop any stale hover state
    end

    if found ~= hovered then
        hovered = found
        hoverSince = os.clock()
        tipLabel.Visible = false
    end

    if hovered and os.clock() - hoverSince > 0.4 then
        local pos = UserInputService:GetMouseLocation()
        tipLabel.Text = hovered.text
        tipLabel.Visible = true
        local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
        local size = tipLabel.AbsoluteSize
        local x = math.min(pos.X + 14, view.X - size.X - 6)
        local y = math.min(pos.Y + 18, view.Y - size.Y - 6)
        tipLabel.Position = UDim2.fromOffset(x, y)
    end
end)

-- everything is built: from now on, changes get saved
ready = true
