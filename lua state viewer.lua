-- FIXED LUA STATE VIEWER FOR CLIENT EXECUTORS
local FixedViewer = {
    _watchers = {},
    _events = {},
    _cache = {},
    _ids = setmetatable({}, {__mode = "k"}),
    _safeMode = true
}

-- Safe environment references
FixedViewer._env = getrenv and getrenv() or _G
FixedViewer._g = FixedViewer._env._G
FixedViewer._require = FixedViewer._env.require

-- Safe object tracking
function FixedViewer._getId(obj)
    local id = FixedViewer._ids[obj]
    if not id then
        local success, result = pcall(function()
            return tostring(obj):match("0x(%x+)") or #FixedViewer._ids + 1
        end)
        id = success and result or #FixedViewer._ids + 1
        FixedViewer._ids[obj] = id
    end
    return id
end

-- Safe table watching
function FixedViewer.watchTable(tbl, name)
    if FixedViewer._watchers[tbl] then return end
    
    local watcher = {
        name = name or "table",
        last = {},
        id = FixedViewer._getId(tbl)
    }
    
    local success = pcall(function()
        for k, v in pairs(tbl) do
            watcher.last[k] = v
        end
    end)
    
    if success then
        FixedViewer._watchers[tbl] = watcher
        return watcher.id
    end
    return nil
end

-- Safe change detection
function FixedViewer.checkTableChanges()
    local changes = {}
    
    for tbl, watcher in pairs(FixedViewer._watchers) do
        local success, result = pcall(function()
            if type(tbl) == "table" then
                local current = {}
                local tableChanges = {}
                
                for k, v in pairs(tbl) do
                    current[k] = true
                    if watcher.last[k] ~= v then
                        table.insert(tableChanges, {watcher.name, k, "changed"})
                        watcher.last[k] = v
                    end
                end
                
                for k in pairs(watcher.last) do
                    if not current[k] then
                        table.insert(tableChanges, {watcher.name, k, "removed"})
                        watcher.last[k] = nil
                    end
                end
                
                return tableChanges
            end
            return {}
        end)
        
        if success then
            for _, change in ipairs(result) do
                table.insert(changes, change)
            end
        end
    end
    
    return changes
end

-- Safe require monitoring
function FixedViewer.monitorRequire()
    if FixedViewer._hooks then return end
    
    FixedViewer._hooks = {require = FixedViewer._require}
    
    FixedViewer._env.require = function(modname)
        local start = tick()
        local result = FixedViewer._hooks.require(modname)
        local loadTime = tick() - start
        
        table.insert(FixedViewer._events, {
            "require", modname, loadTime, FixedViewer._getId(result)
        })
        
        if type(result) == "table" then
            FixedViewer.watchTable(result, "module:" .. modname)
        end
        
        return result
    end
    
    -- Watch important tables
    FixedViewer.watchTable(FixedViewer._g, "_G")
    
    if FixedViewer._env.package and FixedViewer._env.package.loaded then
        FixedViewer.watchTable(FixedViewer._env.package.loaded, "package.loaded")
    end
end

-- Safe events system
function FixedViewer.getEvents(filter, limit)
    local results = {}
    local count = 0
    
    for i = #FixedViewer._events, 1, -1 do
        local event = FixedViewer._events[i]
        if not filter or event[1] == filter then
            table.insert(results, event)
            count = count + 1
            if limit and count >= limit then break end
        end
    end
    
    return results
end

-- Safe statistics
function FixedViewer.getStats()
    return {
        objects = FixedViewer._count(FixedViewer._ids),
        watchers = FixedViewer._count(FixedViewer._watchers),
        events = #FixedViewer._events,
        snapshots = FixedViewer._count(FixedViewer._cache)
    }
end

function FixedViewer._count(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

-- Memory management
function FixedViewer.cleanup()
    if #FixedViewer._events > 100 then
        for i = 1, 50 do
            table.remove(FixedViewer._events, 1)
        end
    end
end

-- FIXED GUI WITH PROPER ERROR HANDLING
local FixedGUI = {
    _gui = nil,
    _currentView = "overview",
    _viewer = FixedViewer,
    _initialized = false
}

FixedGUI.Colors = {
    Background = Color3.fromRGB(40, 40, 40),
    Panel = Color3.fromRGB(50, 50, 50),
    Header = Color3.fromRGB(30, 30, 30),
    Accent = Color3.fromRGB(100, 100, 100),
    Text = Color3.fromRGB(200, 200, 200),
    SubText = Color3.fromRGB(150, 150, 150),
    Success = Color3.fromRGB(100, 200, 100),
    Warning = Color3.fromRGB(200, 150, 50),
    Error = Color3.fromRGB(200, 100, 100)
}

function FixedGUI:Create()
    if self._gui then return self._gui end
    
    -- Safe GUI creation with error handling
    local success, screenGui = pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "DevTools"
        gui.ResetOnSpawn = false
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        
        -- Try CoreGui first, fallback to PlayerGui
        local parent = game:GetService("CoreGui")
        if not parent then
            parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
        end
        gui.Parent = parent
        
        return gui
    end)
    
    if not success then
        warn("Failed to create ScreenGui")
        return nil
    end
    
    local screenGui = screenGui

    -- Main Window
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainWindow"
    mainFrame.Size = UDim2.new(0, 700, 0, 400)
    mainFrame.Position = UDim2.new(0.5, -350, 0.5, -200)
    mainFrame.BackgroundColor3 = self.Colors.Background
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui

    -- Title Bar
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 25)
    titleBar.BackgroundColor3 = self.Colors.Header
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame

    local titleText = Instance.new("TextLabel")
    titleText.Name = "Title"
    titleText.Size = UDim2.new(0, 150, 1, 0)
    titleText.Position = UDim2.new(0, 5, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "Lua State Viewer"
    titleText.TextColor3 = self.Colors.Text
    titleText.TextSize = 12
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Font = Enum.Font.SourceSans
    titleText.Parent = titleBar

    -- Control Buttons
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "Minimize"
    minimizeBtn.Size = UDim2.new(0, 25, 0, 25)
    minimizeBtn.Position = UDim2.new(1, -50, 0, 0)
    minimizeBtn.BackgroundColor3 = self.Colors.Header
    minimizeBtn.BorderSizePixel = 0
    minimizeBtn.Text = "_"
    minimizeBtn.TextColor3 = self.Colors.Text
    minimizeBtn.TextSize = 12
    minimizeBtn.Font = Enum.Font.SourceSans
    minimizeBtn.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "Close"
    closeBtn.Size = UDim2.new(0, 25, 0, 25)
    closeBtn.Position = UDim2.new(1, -25, 0, 0)
    closeBtn.BackgroundColor3 = self.Colors.Header
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.TextColor3 = self.Colors.Text
    closeBtn.TextSize = 12
    closeBtn.Font = Enum.Font.SourceSans
    closeBtn.Parent = titleBar

    -- Make draggable
    self:MakeDraggable(titleBar, mainFrame)

    -- Content Area
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.Size = UDim2.new(1, 0, 1, -25)
    contentFrame.Position = UDim2.new(0, 0, 0, 25)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = mainFrame

    -- Create layout
    self:CreateSidebar(contentFrame)
    self:CreateMainContent(contentFrame)

    -- Connect button events
    minimizeBtn.MouseButton1Click:Connect(function()
        self:ToggleVisibility()
    end)

    closeBtn.MouseButton1Click:Connect(function()
        screenGui.Enabled = false
    end)

    self._gui = screenGui
    self._initialized = true
    return screenGui
end

function FixedGUI:MakeDraggable(dragHandle, mainFrame)
    local dragging = false
    local dragInput, dragStart, startPos
    
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    local inputService = game:GetService("UserInputService")
    if inputService then
        inputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end)
    end
end

function FixedGUI:CreateSidebar(parent)
    if not parent then return end
    
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, 120, 1, 0)
    sidebar.BackgroundColor3 = self.Colors.Panel
    sidebar.BorderSizePixel = 0
    sidebar.Parent = parent

    local navItems = {
        {"Overview", "📊"},
        {"Tables", "📋"},
        {"Events", "📝"},
        {"Require", "📦"}
    }

    for i, item in ipairs(navItems) do
        local button = Instance.new("TextButton")
        button.Name = item[1]
        button.Size = UDim2.new(1, -10, 0, 35)
        button.Position = UDim2.new(0, 5, 0, (i-1) * 37 + 5)
        button.BackgroundColor3 = self.Colors.Panel
        button.BorderSizePixel = 0
        button.Text = item[2] .. " " .. item[1]
        button.TextColor3 = self.Colors.Text
        button.TextSize = 12
        button.Font = Enum.Font.SourceSans
        button.Parent = sidebar

        button.MouseButton1Click:Connect(function()
            self:SwitchView(item[1]:lower())
        end)
    end

    -- Status bar
    local statusBar = Instance.new("Frame")
    statusBar.Name = "StatusBar"
    statusBar.Size = UDim2.new(1, 0, 0, 20)
    statusBar.Position = UDim2.new(0, 0, 1, -20)
    statusBar.BackgroundColor3 = self.Colors.Header
    statusBar.BorderSizePixel = 0
    statusBar.Parent = sidebar

    local statusText = Instance.new("TextLabel")
    statusText.Name = "Status"
    statusText.Size = UDim2.new(1, -5, 1, 0)
    statusText.Position = UDim2.new(0, 5, 0, 0)
    statusText.BackgroundTransparency = 1
    statusText.Text = "Ready"
    statusText.TextColor3 = self.Colors.Success
    statusText.TextSize = 10
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.Font = Enum.Font.SourceSans
    statusText.Parent = statusBar

    self._statusLabel = statusText
end

function FixedGUI:CreateMainContent(parent)
    if not parent then return end
    
    local content = Instance.new("Frame")
    content.Name = "MainContent"
    content.Size = UDim2.new(1, -120, 1, 0)
    content.Position = UDim2.new(0, 120, 0, 0)
    content.BackgroundTransparency = 1
    content.Parent = parent

    -- Store reference to main content
    self._mainContent = content

    self:CreateOverviewView(content)
    self:CreateTablesView(content)
    self:CreateEventsView(content)
    self:CreateRequireView(content)

    -- Safe initial view switch
    task.spawn(function()
        wait(0.1) -- Small delay to ensure everything is created
        self:SwitchView("overview")
    end)
end

function FixedGUI:CreateOverviewView(parent)
    if not parent then return end
    
    local overview = Instance.new("Frame")
    overview.Name = "Overview"
    overview.Size = UDim2.new(1, 0, 1, 0)
    overview.BackgroundTransparency = 1
    overview.Visible = false
    overview.Parent = parent

    -- Stats
    local statsFrame = Instance.new("Frame")
    statsFrame.Name = "Stats"
    statsFrame.Size = UDim2.new(1, -10, 0, 80)
    statsFrame.Position = UDim2.new(0, 5, 0, 5)
    statsFrame.BackgroundColor3 = self.Colors.Panel
    statsFrame.BorderSizePixel = 0
    statsFrame.Parent = overview

    local stats = {
        {"Objects", "0", 0, 0},
        {"Tables", "0", 0.5, 0},
        {"Events", "0", 0, 0.5},
        {"Snapshots", "0", 0.5, 0.5}
    }

    for i, stat in ipairs(stats) do
        local statFrame = Instance.new("Frame")
        statFrame.Name = stat[1]
        statFrame.Size = UDim2.new(0.5, -5, 0.5, -5)
        statFrame.Position = UDim2.new(stat[3], 5, stat[4], 5)
        statFrame.BackgroundTransparency = 1
        statFrame.Parent = statsFrame

        local statName = Instance.new("TextLabel")
        statName.Name = "Name"
        statName.Size = UDim2.new(1, 0, 0, 15)
        statName.Position = UDim2.new(0, 0, 0, 0)
        statName.BackgroundTransparency = 1
        statName.Text = stat[1]
        statName.TextColor3 = self.Colors.SubText
        statName.TextSize = 10
        statName.Font = Enum.Font.SourceSans
        statName.Parent = statFrame

        local statValue = Instance.new("TextLabel")
        statValue.Name = "Value"
        statValue.Size = UDim2.new(1, 0, 1, -15)
        statValue.Position = UDim2.new(0, 0, 0, 15)
        statValue.BackgroundTransparency = 1
        statValue.Text = stat[2]
        statValue.TextColor3 = self.Colors.Text
        statValue.TextSize = 16
        statValue.Font = Enum.Font.SourceSansBold
        statValue.Parent = statFrame

        self["_stat"..stat[1]] = statValue
    end

    -- Controls
    local controlsFrame = Instance.new("Frame")
    controlsFrame.Name = "Controls"
    controlsFrame.Size = UDim2.new(1, -10, 0, 30)
    controlsFrame.Position = UDim2.new(0, 5, 0, 90)
    controlsFrame.BackgroundTransparency = 1
    controlsFrame.Parent = overview

    local controls = {
        {"Start", self.Colors.Success},
        {"Stop", self.Colors.Error},
        {"Clear", self.Colors.Warning}
    }

    for i, control in ipairs(controls) do
        local button = Instance.new("TextButton")
        button.Name = control[1]
        button.Size = UDim2.new(0.33, -5, 1, 0)
        button.Position = UDim2.new((i-1) * 0.33, 0, 0, 0)
        button.BackgroundColor3 = control[2]
        button.BorderSizePixel = 0
        button.Text = control[1]
        button.TextColor3 = self.Colors.Text
        button.TextSize = 12
        button.Font = Enum.Font.SourceSans
        button.Parent = controlsFrame

        button.MouseButton1Click:Connect(function()
            self:HandleControl(control[1])
        end)
    end

    -- Activity Log
    local activityFrame = Instance.new("Frame")
    activityFrame.Name = "Activity"
    activityFrame.Size = UDim2.new(1, -10, 1, -130)
    activityFrame.Position = UDim2.new(0, 5, 0, 125)
    activityFrame.BackgroundColor3 = self.Colors.Panel
    activityFrame.BorderSizePixel = 0
    activityFrame.Parent = overview

    local activityHeader = Instance.new("TextLabel")
    activityHeader.Name = "Header"
    activityHeader.Size = UDim2.new(1, 0, 0, 20)
    activityHeader.Position = UDim2.new(0, 0, 0, 0)
    activityHeader.BackgroundColor3 = self.Colors.Header
    activityHeader.BorderSizePixel = 0
    activityHeader.Text = "RECENT ACTIVITY"
    activityHeader.TextColor3 = self.Colors.Text
    activityHeader.TextSize = 11
    activityHeader.Font = Enum.Font.SourceSansBold
    activityHeader.Parent = activityFrame

    local activityScroll = Instance.new("ScrollingFrame")
    activityScroll.Name = "Scroll"
    activityScroll.Size = UDim2.new(1, 0, 1, -20)
    activityScroll.Position = UDim2.new(0, 0, 0, 20)
    activityScroll.BackgroundTransparency = 1
    activityScroll.BorderSizePixel = 0
    activityScroll.ScrollBarThickness = 4
    activityScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    activityScroll.Parent = activityFrame

    local activityList = Instance.new("UIListLayout")
    activityList.Name = "List"
    activityList.Parent = activityScroll

    self._activityScroll = activityScroll
end

function FixedGUI:CreateTablesView(parent)
    if not parent then return end
    
    local tablesView = Instance.new("Frame")
    tablesView.Name = "Tables"
    tablesView.Size = UDim2.new(1, 0, 1, 0)
    tablesView.BackgroundTransparency = 1
    tablesView.Visible = false
    tablesView.Parent = parent

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundColor3 = self.Colors.Header
    header.BorderSizePixel = 0
    header.Parent = tablesView

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(0, 200, 1, 0)
    title.Position = UDim2.new(0, 5, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "TABLE MONITOR"
    title.TextColor3 = self.Colors.Text
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.SourceSansBold
    title.Parent = header

    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Name = "Refresh"
    refreshBtn.Size = UDim2.new(0, 100, 0, 20)
    refreshBtn.Position = UDim2.new(1, -105, 0.5, -10)
    refreshBtn.BackgroundColor3 = self.Colors.Accent
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Text = "Check Changes"
    refreshBtn.TextColor3 = self.Colors.Text
    refreshBtn.TextSize = 11
    refreshBtn.Font = Enum.Font.SourceSans
    refreshBtn.Parent = header

    refreshBtn.MouseButton1Click:Connect(function()
        self:RefreshTablesView()
    end)

    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "TablesScroll"
    scrollFrame.Size = UDim2.new(1, 0, 1, -30)
    scrollFrame.Position = UDim2.new(0, 0, 0, 30)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = tablesView

    local listLayout = Instance.new("UIListLayout")
    listLayout.Name = "ListLayout"
    listLayout.Parent = scrollFrame

    self._tablesScroll = scrollFrame
end

function FixedGUI:CreateEventsView(parent)
    if not parent then return end
    
    local eventsView = Instance.new("Frame")
    eventsView.Name = "Events"
    eventsView.Size = UDim2.new(1, 0, 1, 0)
    eventsView.BackgroundTransparency = 1
    eventsView.Visible = false
    eventsView.Parent = parent

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundColor3 = self.Colors.Header
    header.BorderSizePixel = 0
    header.Parent = eventsView

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(0, 200, 1, 0)
    title.Position = UDim2.new(0, 5, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "EVENT LOG"
    title.TextColor3 = self.Colors.Text
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.SourceSansBold
    title.Parent = header

    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "EventsScroll"
    scrollFrame.Size = UDim2.new(1, 0, 1, -30)
    scrollFrame.Position = UDim2.new(0, 0, 0, 30)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = eventsView

    local listLayout = Instance.new("UIListLayout")
    listLayout.Name = "ListLayout"
    listLayout.Parent = scrollFrame

    self._eventsScroll = scrollFrame
end

function FixedGUI:CreateRequireView(parent)
    if not parent then return end
    
    local requireView = Instance.new("Frame")
    requireView.Name = "Require"
    requireView.Size = UDim2.new(1, 0, 1, 0)
    requireView.BackgroundTransparency = 1
    requireView.Visible = false
    requireView.Parent = parent

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundColor3 = self.Colors.Header
    header.BorderSizePixel = 0
    header.Parent = requireView

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(0, 200, 1, 0)
    title.Position = UDim2.new(0, 5, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "REQUIRE LOG"
    title.TextColor3 = self.Colors.Text
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.SourceSansBold
    title.Parent = header

    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "RequireScroll"
    scrollFrame.Size = UDim2.new(1, 0, 1, -30)
    scrollFrame.Position = UDim2.new(0, 0, 0, 30)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = requireView

    local listLayout = Instance.new("UIListLayout")
    listLayout.Name = "ListLayout"
    listLayout.Parent = scrollFrame

    self._requireScroll = scrollFrame
end

-- FIXED SwitchView function with proper error handling
function FixedGUI:SwitchView(viewName)
    if not self._initialized or not self._mainContent then
        warn("GUI not fully initialized yet")
        return
    end
    
    -- Hide all views safely
    for _, child in pairs(self._mainContent:GetChildren()) do
        if child:IsA("Frame") then
            child.Visible = false
        end
    end
    
    -- Show target view
    local targetView = self._mainContent:FindFirstChild(viewName:gsub("^%l", string.upper))
    if targetView then
        targetView.Visible = true
        self._currentView = viewName
        self:RefreshCurrentView()
    else
        warn("View not found: " .. viewName)
    end
end

function FixedGUI:HandleControl(action)
    if action == "Start" then
        self._viewer.monitorRequire()
        self:UpdateStatus("Monitoring started", self.Colors.Success)
    elseif action == "Stop" then
        if self._viewer._hooks then
            self._viewer._env.require = self._viewer._hooks.require
            self._viewer._hooks = nil
        end
        self:UpdateStatus("Monitoring stopped", self.Colors.Warning)
    elseif action == "Clear" then
        self._viewer.cleanup()
        self:UpdateStatus("Data cleared", self.Colors.Warning)
    end
    self:RefreshCurrentView()
end

function FixedGUI:UpdateStatus(message, color)
    if self._statusLabel then
        self._statusLabel.Text = message
        self._statusLabel.TextColor3 = color
    end
end

function FixedGUI:RefreshCurrentView()
    if not self._initialized then return end
    
    if self._currentView == "overview" then
        self:RefreshOverview()
    elseif self._currentView == "tables" then
        self:RefreshTablesView()
    elseif self._currentView == "events" then
        self:RefreshEventsView()
    elseif self._currentView == "require" then
        self:RefreshRequireView()
    end
end

function FixedGUI:RefreshOverview()
    local stats = self._viewer.getStats()
    
    if self._statObjects then
        self._statObjects.Text = tostring(stats.objects)
    end
    if self._statTables then
        self._statTables.Text = tostring(stats.watchers)
    end
    if self._statEvents then
        self._statEvents.Text = tostring(stats.events)
    end
    if self._statSnapshots then
        self._statSnapshots.Text = tostring(stats.snapshots)
    end
    
    -- Update activity log
    if self._activityScroll then
        self._activityScroll:ClearAllChildren()
        
        local events = self._viewer.getEvents(nil, 15)
        local ySize = 0
        
        for i, event in ipairs(events) do
            local eventFrame = Instance.new("Frame")
            eventFrame.Size = UDim2.new(1, 0, 0, 20)
            eventFrame.Position = UDim2.new(0, 0, 0, (i-1) * 22)
            eventFrame.BackgroundTransparency = 1
            eventFrame.Parent = self._activityScroll
            
            local eventText = Instance.new("TextLabel")
            eventText.Size = UDim2.new(1, -5, 1, 0)
            eventText.Position = UDim2.new(0, 5, 0, 0)
            eventText.BackgroundTransparency = 1
            eventText.Text = string.format("[%s] %s", event[1], tostring(event[2]))
            eventText.TextColor3 = self.Colors.Text
            eventText.TextSize = 10
            eventText.TextXAlignment = Enum.TextXAlignment.Left
            eventText.Font = Enum.Font.SourceSans
            eventText.Parent = eventFrame
            
            ySize = ySize + 22
        end
        
        self._activityScroll.CanvasSize = UDim2.new(0, 0, 0, ySize)
    end
end

function FixedGUI:RefreshTablesView()
    if self._tablesScroll then
        self._tablesScroll:ClearAllChildren()
        
        local changes = self._viewer.checkTableChanges()
        local ySize = 0
        
        for i, change in ipairs(changes) do
            local changeFrame = Instance.new("Frame")
            changeFrame.Size = UDim2.new(1, -10, 0, 20)
            changeFrame.Position = UDim2.new(0, 5, 0, (i-1) * 22)
            changeFrame.BackgroundColor3 = self.Colors.Panel
            changeFrame.BorderSizePixel = 0
            changeFrame.Parent = self._tablesScroll
            
            local changeText = Instance.new("TextLabel")
            changeText.Size = UDim2.new(1, 0, 1, 0)
            changeText.BackgroundTransparency = 1
            changeText.Text = string.format("%s: %s %s", change[1], change[2], change[3])
            changeText.TextColor3 = self.Colors.Text
            changeText.TextSize = 10
            changeText.TextXAlignment = Enum.TextXAlignment.Left
            changeText.Font = Enum.Font.SourceSans
            changeText.Parent = changeFrame
            
            ySize = ySize + 22
        end
        
        if #changes == 0 then
            local noChanges = Instance.new("TextLabel")
            noChanges.Size = UDim2.new(1, 0, 0, 30)
            noChanges.Position = UDim2.new(0, 0, 0, 0)
            noChanges.BackgroundTransparency = 1
            noChanges.Text = "No table changes detected"
            noChanges.TextColor3 = self.Colors.SubText
            noChanges.TextSize = 12
            noChanges.Font = Enum.Font.SourceSans
            noChanges.Parent = self._tablesScroll
            ySize = 30
        end
        
        self._tablesScroll.CanvasSize = UDim2.new(0, 0, 0, ySize)
    end
end

function FixedGUI:RefreshEventsView()
    if self._eventsScroll then
        self._eventsScroll:ClearAllChildren()
        
        local events = self._viewer.getEvents(nil, 30)
        local ySize = 0
        
        for i, event in ipairs(events) do
            local eventFrame = Instance.new("Frame")
            eventFrame.Size = UDim2.new(1, -10, 0, 18)
            eventFrame.Position = UDim2.new(0, 5, 0, (i-1) * 20)
            eventFrame.BackgroundColor3 = self.Colors.Panel
            eventFrame.BorderSizePixel = 0
            eventFrame.Parent = self._eventsScroll
            
            local eventText = Instance.new("TextLabel")
            eventText.Size = UDim2.new(1, 0, 1, 0)
            eventText.BackgroundTransparency = 1
            eventText.Text = string.format("[%s] %s", event[1], tostring(event[2]))
            eventText.TextColor3 = self.Colors.Text
            eventText.TextSize = 9
            eventText.TextXAlignment = Enum.TextXAlignment.Left
            eventText.Font = Enum.Font.SourceSans
            eventText.Parent = eventFrame
            
            ySize = ySize + 20
        end
        
        self._eventsScroll.CanvasSize = UDim2.new(0, 0, 0, ySize)
    end
end

function FixedGUI:RefreshRequireView()
    if self._requireScroll then
        self._requireScroll:ClearAllChildren()
        
        local events = self._viewer.getEvents("require", 30)
        local ySize = 0
        
        for i, event in ipairs(events) do
            local eventFrame = Instance.new("Frame")
            eventFrame.Size = UDim2.new(1, -10, 0, 18)
            eventFrame.Position = UDim2.new(0, 5, 0, (i-1) * 20)
            eventFrame.BackgroundColor3 = self.Colors.Panel
            eventFrame.BorderSizePixel = 0
            eventFrame.Parent = self._requireScroll
            
            local eventText = Instance.new("TextLabel")
            eventText.Size = UDim2.new(1, 0, 1, 0)
            eventText.BackgroundTransparency = 1
            eventText.Text = string.format("require('%s') - %.4fs", event[2], event[3])
            eventText.TextColor3 = self.Colors.Text
            eventText.TextSize = 9
            eventText.TextXAlignment = Enum.TextXAlignment.Left
            eventText.Font = Enum.Font.SourceSans
            eventText.Parent = eventFrame
            
            ySize = ySize + 20
        end
        
        self._requireScroll.CanvasSize = UDim2.new(0, 0, 0, ySize)
    end
end

function FixedGUI:ToggleVisibility()
    if self._gui then
        self._gui.Enabled = not self._gui.Enabled
    end
end

function FixedGUI:Show()
    if self._gui then
        self._gui.Enabled = true
    end
end

function FixedGUI:Hide()
    if self._gui then
        self._gui.Enabled = false
    end
end

-- FIXED AutoStart with proper initialization
function FixedGUI:AutoStart()
    -- Create GUI first
    local success = pcall(function()
        self:Create()
    end)
    
    if not success then
        warn("Failed to create GUI")
        return
    end
    
    -- Start monitoring
    self._viewer.monitorRequire()
    
    -- Wait a moment for GUI to fully initialize
    task.spawn(function()
        wait(0.5)
        if self._statusLabel then
            self:UpdateStatus("Executor Viewer Ready", self.Colors.Success)
        end
    end)
    
    -- Auto-refresh
    task.spawn(function()
        while wait(1) do
            if self._gui and self._gui.Enabled and self._initialized then
                self:RefreshCurrentView()
            end
        end
    end)
    
    print("Lua State Viewer for Executors - Ready!")
end

-- Safe auto-start
task.spawn(function()
    wait(1) -- Give executor time to initialize
    FixedGUI:AutoStart()
end)

return {
    Viewer = FixedViewer,
    GUI = FixedGUI
}
