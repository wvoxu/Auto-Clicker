-- Auto Clicker (by wvoxu) - locked-position autoclicker, UI Library
-- Press your key to start clicking where your cursor is. Press it again to stop.
-- Everything is set in the window. UI Library credits are in the library's header comment.

-- UI LIBRARY: loaded from this link (the "main.lua" of your UI Library repo). Change it if the repo is named differently.
local LIB_URL = "https://raw.githubusercontent.com/wvoxu/UI-Library/main/main.lua"

----------------------------------------------------------------------
-- SAVED SETTINGS
----------------------------------------------------------------------
-- Settings are kept in a small file in your executor's workspace folder and loaded on start.
-- (Whether the clicker is on or off is never saved. The theme and menu key are saved by the UI itself.)
local HttpService = game:GetService("HttpService")
local SAVE_FILE = "WvoxuAutoClicker.json"
local saved = HttpService:JSONDecode("{}") -- (decoded this way so editors treat it as a flexible table)
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

local saveSettings = function() end -- replaced once the UI exists

-- If this script was already run, shut the old copy down first.
local sharedEnv = (getgenv and getgenv()) or _G
if sharedEnv.__WvoxuAutoClickerCleanup then
    pcall(sharedEnv.__WvoxuAutoClickerCleanup)
    sharedEnv.__WvoxuAutoClickerCleanup = nil
end

----------------------------------------------------------------------
-- LOAD THE UI LIBRARY (built in)
----------------------------------------------------------------------
local UILib
do
    local okGet, body = pcall(game.HttpGet, game, LIB_URL .. "?v=" .. os.time())
    if not okGet or type(body) ~= "string" or body == "" then
        warn("[Auto Clicker] couldn't download the UI library from " .. LIB_URL .. ": " .. tostring(body))
        return
    end
    local chunk, compileError = loadstring(body)
    if not chunk then
        warn("[Auto Clicker] the UI library didn't compile: " .. tostring(compileError))
        return
    end
    local okRun, library = pcall(chunk)
    if not okRun or type(library) ~= "table" or not library.Window then
        warn("[Auto Clicker] the UI library didn't give a window library: " .. tostring(library))
        return
    end
    UILib = library
end

----------------------------------------------------------------------
-- SERVICES / STATE
----------------------------------------------------------------------
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")

local autoClicking = false
local clickSpeed = (tonumber(saved.clickSpeed) and tonumber(saved.clickSpeed) > 0) and tonumber(saved.clickSpeed) or 0.1
local toggleKey = keyFromName(saved.key, Enum.KeyCode.KeypadPlus)
local randomDelay = saved.randomDelay == true      -- vary the delay by +-25%
local followCursor = saved.followCursor == true    -- click wherever the cursor is instead of a fixed spot
local notificationsOn = saved.notifications ~= false
local clickLimit = math.max(0, math.floor(tonumber(saved.clickLimit) or 0)) -- 0 = unlimited
local clickCount = 0
local mouseButtonName = (saved.mouseButton == "Right" or saved.mouseButton == "Middle") and saved.mouseButton or "Left"
local MOUSE_BUTTONS = { Left = 0, Right = 1, Middle = 2 }
local mouseButton = MOUSE_BUTTONS[mouseButtonName]
local lockedPos = Vector2.new(0, 0) -- where the cursor was when you started; clicks land here
local lastKeyChange = 0
local alive = true
local keyConn
local ready = false -- settings are only written once the UI has finished loading

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
local Window = UILib:Window({
    Title = "Auto Clicker",
    Subtitle = "by wvoxu",
    Key = Enum.KeyCode.RightShift, -- change it in Settings, it's remembered
    Folder = "WvoxuAutoClicker",
    Size = Vector2.new(440, 340),
    MinSize = Vector2.new(400, 300),
    Compact = true, -- no sidebar or resizing; the gear in the corner opens Settings
    Splash = false,
    Logo = "W",
    KeepPrevious = true,
})

-- Settings are saved by the UI itself now (Settings > Configs: Autosave / Autoload).
-- The old settings file is only read once, to fill in the first "Default" config.
saveSettings = function() end

sharedEnv.__WvoxuAutoClickerCleanup = function()
    alive = false
    autoClicking = false
    if keyConn then keyConn:Disconnect() end
    pcall(function() Window:Unload(true) end)
end

local function notify(title, text)
    if not notificationsOn then return end
    Window:Notify({ Title = title, Text = text, Duration = 2 })
end

-- Is the cursor over this window? The clicker never clicks the window's own buttons.
local function overUI()
    if not Window:IsVisible() or not Window.Frame then return false end
    local p = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
    local pos, size = Window.Frame.AbsolutePosition, Window.Frame.AbsoluteSize
    return p.X >= pos.X and p.X <= pos.X + size.X and p.Y >= pos.Y and p.Y <= pos.Y + size.Y
end

local Tab = Window:Tab({ Name = "Auto Clicker", Icon = "Misc" })

local statusGroup = Tab:Group("Status")
local statusRow = statusGroup:Label("Status: Off")
local countRow = statusGroup:Label("Clicks: 0")

local function setStatus()
    statusRow:Set("Status: " .. (autoClicking and "On" or "Off") .. "  |  Key: " .. toggleKey.Name)
    countRow:Set("Clicks: " .. clickCount)
end
setStatus()

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
    notify("Auto Clicker on", followCursor and "Following your cursor" or string.format("Clicking at %d, %d", lockedPos.X, lockedPos.Y))
end

local function stopClicking(reason)
    if not autoClicking then return end
    autoClicking = false
    setStatus()
    notify("Auto Clicker off", reason or (clickCount .. " clicks sent"))
end

local clickGroup = Tab:Group({ Name = "Clicking", Description = "Your settings are saved automatically." })

local keyEl
keyEl = clickGroup:Keybind({
    Name = "Auto Clicker Key",
    Flag = "key",
    Description = "Press it to start or stop. Click the box to change it.",
    Default = toggleKey,
    Changed = function(newKey)
        lastKeyChange = os.clock()
        if newKey then toggleKey = newKey end
        stopClicking()
        setStatus()
        saveSettings()
    end,
})

clickGroup:Input({
    Name = "Click Delay (s)",
    Flag = "delay",
    Description = "Seconds between clicks. 0.1 is about 10 clicks a second.",
    Default = tostring(clickSpeed),
    Placeholder = "0.1",
    Numeric = true,
    Callback = function(value)
        local speed = tonumber(value)
        if speed and speed > 0 then
            clickSpeed = speed
            saveSettings()
        end
    end,
})

clickGroup:Input({
    Name = "Click Limit",
    Flag = "limit",
    Description = "Stops after this many clicks. 0 means it never stops.",
    Default = tostring(clickLimit),
    Placeholder = "0",
    Numeric = true,
    Callback = function(value)
        local n = tonumber(value)
        if n and n >= 0 then
            clickLimit = math.floor(n)
            saveSettings()
        end
    end,
})

clickGroup:Dropdown({
    Name = "Mouse Button",
    Flag = "button",
    Description = "Which mouse button it clicks with.",
    Options = { "Left", "Right", "Middle" },
    Default = mouseButtonName,
    Callback = function(option)
        if MOUSE_BUTTONS[option] then
            mouseButton = MOUSE_BUTTONS[option]
            mouseButtonName = option
            saveSettings()
        end
    end,
})

local optionGroup = Tab:Group("Options")

optionGroup:Toggle({
    Name = "Random Delay",
    Flag = "random",
    Description = "Changes the delay a little each click so the timing isn't even.",
    Default = randomDelay,
    Callback = function(state)
        randomDelay = state
        saveSettings()
    end,
})

optionGroup:Toggle({
    Name = "Follow Cursor",
    Flag = "follow",
    Description = "Clicks wherever your cursor is, instead of where you started.",
    Default = followCursor,
    Callback = function(state)
        followCursor = state
        saveSettings()
    end,
})

optionGroup:Toggle({
    Name = "Notifications",
    Flag = "notifications",
    Description = "Pop-ups for on/off and the click limit.",
    Default = notificationsOn,
    Callback = function(state)
        notificationsOn = state
        saveSettings()
    end,
})

----------------------------------------------------------------------
-- AUTOCLICK LOOP
----------------------------------------------------------------------
-- Only sends clicks at the chosen position. It never touches MouseBehavior, so it can't drag the camera.
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
                if clickCount % 10 == 0 then countRow:Set("Clicks: " .. clickCount) end

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
            -- keep the status line in step if the key was changed by loading a config
            if keyEl and keyEl:Get() and keyEl:Get() ~= toggleKey then
                toggleKey = keyEl:Get()
                setStatus()
            end
            task.wait(0.1)
        end
    end
end)

----------------------------------------------------------------------
-- KEY HANDLING
----------------------------------------------------------------------
-- Done here (not in the UI's callback) so every key works, including shift/keypad keys.
keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if keyEl and keyEl:Get() then toggleKey = keyEl:Get() end
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

-- everything is built: from now on, changes get saved
ready = true
