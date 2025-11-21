-- Professional Lua State Viewer GUI Suite
local ProfessionalGUI = {
    _gui = nil,
    _tabs = {},
    _currentView = "overview"
}

-- Color scheme
ProfessionalGUI.Colors = {
    Background = Color3.fromRGB(30, 30, 40),
    Panel = Color3.fromRGB(45, 45, 55),
    Header = Color3.fromRGB(25, 25, 35),
    Accent = Color3.fromRGB(0, 162, 255),
    Text = Color3.fromRGB(240, 240, 240),
    SubText = Color3.fromRGB(180, 180, 180),
    Success = Color3.fromRGB(76, 175, 80),
    Warning = Color3.fromRGB(255, 152, 0),
    Error = Color3.fromRGB(244, 67, 54)
}

-- Create the main GUI
function ProfessionalGUI:Create()
    if self._gui then return self._gui end
    
    -- Main ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LuaStateViewer"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Main Window Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainWindow"
    mainFrame.Size = UDim2.new(0, 900, 0, 600)
    mainFrame.Position = UDim2.new(0.5, -450, 0.5, -300)
    mainFrame.BackgroundColor3 = self.Colors.Background
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui
    
    -- Drop Shadow
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 10, 1, 10)
    shadow.Position = UDim2.new(0, -5, 0, -5)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://1316045217"
    shadow.ImageColor3 = Color3.new(0, 0, 0)
    shadow.ImageTransparency = 0.8
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(10, 10, 118, 118)
    shadow.Parent = mainFrame
    
    -- Title Bar
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.BackgroundColor3 = self.Colors.Header
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    
    -- Title Text
    local titleText = Instance.new("TextLabel")
    titleText.Name = "Title"
    titleText.Size = UDim2.new(0, 200, 1, 0)
    titleText.Position = UDim2.new(0, 10, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "LUA STATE VIEWER"
    titleText.TextColor3 = self.Colors.Text
    titleText.TextSize = 14
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Font = Enum.Font.GothamBold
    titleText.Parent = titleBar
    
    -- Control Buttons
    local buttons = {"Minimize", "Close"}
    for i, name in ipairs(buttons) do
        local button = Instance.new("TextButton")
        button.Name = name
        button.Size = UDim2.new(0, 30, 0, 30)
        button.Position = UDim2.new(1, -30 * i, 0, 0)
        button.BackgroundColor3 = self.Colors.Header
        button.BorderSizePixel = 0
        button.Text = name == "Minimize" and "_" :or "X"
        button.TextColor3 = self.Colors.Text
        button.TextSize = 14
        button.Font = Enum.Font.Gotham
        button.Parent = titleBar
        
        button.MouseButton1Click:Connect(function()
            if name == "Minimize" then
                self:ToggleVisibility()
            else
                screenGui.Enabled = false
            end
        end)
    end
    
    -- Make window draggable
    self:MakeDraggable(titleBar, mainFrame)
    
    -- Content Area
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.Size = UDim2.new(1, 0, 1, -30)
    contentFrame.Position = UDim2.new(0, 0, 0, 30)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = mainFrame
    
    -- Create sidebar and main content
    self:CreateSidebar(contentFrame)
    self:CreateMainContent(contentFrame)
    
    self._gui = screenGui
    return screenGui
end

-- Make window draggable
function ProfessionalGUI:MakeDraggable(dragHandle, mainFrame)
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
    
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- Create sidebar with navigation
function ProfessionalGUI:CreateSidebar(parent)
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, 200, 1, 0)
    sidebar.BackgroundColor3 = self.Colors.Panel
    sidebar.BorderSizePixel = 0
    sidebar.Parent = parent
    
    -- Navigation items
    local navItems = {
        {"Overview", "📊"},
        {"Closures", "🔍"}, 
        {"Tables", "📋"},
        {"Upvalues", "🔗"},
        {"Events", "📝"},
        {"Require Log", "📦"},
        {"Search", "🔎"},
        {"Snapshots", "⏱️"},
        {"Settings", "⚙️"}
    }
    
    for i, item in ipairs(navItems) do
        local button = Instance.new("TextButton")
        button.Name = item[1]
        button.Size = UDim2.new(1, -10, 0, 40)
        button.Position = UDim2.new(0, 5, 0, (i-1) * 42 + 10)
        button.BackgroundColor3 = self.Colors.Panel
        button.BorderSizePixel = 0
        button.Text = "   " .. item[2] .. " " .. item[1]
        button.TextColor3 = self.Colors.Text
        button.TextSize = 14
        button.TextXAlignment = Enum.TextXAlignment.Left
        button.Font = Enum.Font.Gotham
        button.Parent = sidebar
        
        button.MouseButton1Click:Connect(function()
            self:SwitchView(item[1]:lower())
        end)
        
        -- Hover effects
        button.MouseEnter:Connect(function()
            if self._currentView ~= item[1]:lower() then
                button.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
            end
        end)
        
        button.MouseLeave:Connect(function()
            if self._currentView ~= item[1]:lower() then
                button.BackgroundColor3 = self.Colors.Panel
            end
        end)
    end
    
    -- Status bar at bottom
    local statusBar = Instance.new("Frame")
    statusBar.Name = "StatusBar"
    statusBar.Size = UDim2.new(1, 0, 0, 30)
    statusBar.Position = UDim2.new(0, 0, 1, -30)
    statusBar.BackgroundColor3 = self.Colors.Header
    statusBar.BorderSizePixel = 0
    statusBar.Parent = sidebar
    
    local statusText = Instance.new("TextLabel")
    statusText.Name = "Status"
    statusText.Size = UDim2.new(1, -10, 1, 0)
    statusText.Position = UDim2.new(0, 5, 0, 0)
    statusText.BackgroundTransparency = 1
    statusText.Text = "Ready"
    statusText.TextColor3 = self.Colors.Success
    statusText.TextSize = 12
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.Font = Enum.Font.Gotham
    statusText.Parent = statusBar
    
    self._statusLabel = statusText
end

-- Create main content area
function ProfessionalGUI:CreateMainContent(parent)
    local content = Instance.new("Frame")
    content.Name = "MainContent"
    content.Size = UDim2.new(1, -200, 1, 0)
    content.Position = UDim2.new(0, 200, 0, 0)
    content.BackgroundTransparency = 1
    content.Parent = parent
    
    -- Create all views
    self:CreateOverviewView(content)
    self:CreateClosuresView(content)
    self:CreateTablesView(content)
    self:CreateUpvaluesView(content)
    self:CreateEventsView(content)
    self:CreateRequireLogView(content)
    self:CreateSearchView(content)
    self:CreateSnapshotsView(content)
    self:CreateSettingsView(content)
    
    -- Show overview by default
    self:SwitchView("overview")
end

-- Overview View
function ProfessionalGUI:CreateOverviewView(parent)
    local overview = Instance.new("Frame")
    overview.Name = "Overview"
    overview.Size = UDim2.new(1, 0, 1, 0)
    overview.BackgroundTransparency = 1
    overview.Visible = false
    overview.Parent = parent
    
    -- Stats Grid
    local statsGrid = Instance.new("Frame")
    statsGrid.Name = "StatsGrid"
    statsGrid.Size = UDim2.new(1, -20, 0, 120)
    statsGrid.Position = UDim2.new(0, 10, 0, 10)
    statsGrid.BackgroundTransparency = 1
    statsGrid.Parent = overview
    
    local stats = {
        {"Objects Tracked", "0", self.Colors.Accent},
        {"Tables Watched", "0", self.Colors.Success},
        {"Events Logged", "0", self.Colors.Warning},
        {"Memory Usage", "0 KB", self.Colors.Text}
    }
    
    for i, stat in ipairs(stats) do
        local statFrame = Instance.new("Frame")
        statFrame.Name = stat[1]
        statFrame.Size = UDim2.new(0.25, -10, 1, 0)
        statFrame.Position = UDim2.new((i-1) * 0.25, 5, 0, 0)
        statFrame.BackgroundColor3 = self.Colors.Panel
        statFrame.BorderSizePixel = 0
        statFrame.Parent = statsGrid
        
        local statName = Instance.new("TextLabel")
        statName.Name = "Name"
        statName.Size = UDim2.new(1, 0, 0, 30)
        statName.Position = UDim2.new(0, 0, 0, 0)
        statName.BackgroundTransparency = 1
        statName.Text = stat[1]
        statName.TextColor3 = self.Colors.SubText
        statName.TextSize = 12
        statName.Font = Enum.Font.Gotham
        statName.Parent = statFrame
        
        local statValue = Instance.new("TextLabel")
        statValue.Name = "Value"
        statValue.Size = UDim2.new(1, 0, 1, -30)
        statValue.Position = UDim2.new(0, 0, 0, 30)
        statValue.BackgroundTransparency = 1
        statValue.Text = stat[2]
        statValue.TextColor3 = stat[3]
        statValue.TextSize = 24
        statValue.Font = Enum.Font.GothamBold
        statValue.Parent = statFrame
        
        self["_stat"..stat[1]:gsub(" ", "")] = statValue
    end
    
    -- Quick Actions
    local actionsFrame = Instance.new("Frame")
    actionsFrame.Name = "QuickActions"
    actionsFrame.Size = UDim2.new(1, -20, 0, 50)
    actionsFrame.Position = UDim2.new(0, 10, 0, 140)
    actionsFrame.BackgroundTransparency = 1
    actionsFrame.Parent = overview
    
    local actions = {
        {"Start Monitoring", self.Colors.Success},
        {"Take Snapshot", self.Colors.Accent},
        {"Clear Data", self.Colors.Warning}
    }
    
    for i, action in ipairs(actions) do
        local button = Instance.new("TextButton")
        button.Name = action[1]
        button.Size = UDim2.new(0.3, -10, 1, 0)
        button.Position = UDim2.new((i-1) * 0.3, 5, 0, 0)
        button.BackgroundColor3 = action[2]
        button.BorderSizePixel = 0
        button.Text = action[1]
        button.TextColor3 = self.Colors.Text
        button.TextSize = 14
        button.Font = Enum.Font.Gotham
        button.Parent = actionsFrame
        
        button.MouseButton1Click:Connect(function()
            self:HandleQuickAction(action[1])
        end)
    end
    
    -- Recent Activity
    local activityFrame = Instance.new("Frame")
    activityFrame.Name = "RecentActivity"
    activityFrame.Size = UDim2.new(1, -20, 1, -210)
    activityFrame.Position = UDim2.new(0, 10, 0, 200)
    activityFrame.BackgroundColor3 = self.Colors.Panel
    activityFrame.BorderSizePixel = 0
    activityFrame.Parent = overview
    
    local activityHeader = Instance.new("TextLabel")
    activityHeader.Name = "Header"
    activityHeader.Size = UDim2.new(1, 0, 0, 30)
    activityHeader.Position = UDim2.new(0, 0, 0, 0)
    activityHeader.BackgroundColor3 = self.Colors.Header
    activityHeader.BorderSizePixel = 0
    activityHeader.Text = "RECENT ACTIVITY"
    activityHeader.TextColor3 = self.Colors.Text
    activityHeader.TextSize = 12
    activityHeader.Font = Enum.Font.GothamBold
    activityHeader.Parent = activityFrame
    
    local activityScroll = Instance.new("ScrollingFrame")
    activityScroll.Name = "Scroll"
    activityScroll.Size = UDim2.new(1, 0, 1, -30)
    activityScroll.Position = UDim2.new(0, 0, 0, 30)
    activityScroll.BackgroundTransparency = 1
    activityScroll.BorderSizePixel = 0
    activityScroll.ScrollBarThickness = 6
    activityScroll.Parent = activityFrame
    
    local activityList = Instance.new("UIListLayout")
    activityList.Name = "List"
    activityList.Parent = activityScroll
    
    self._activityScroll = activityScroll
end

-- Closures View
function ProfessionalGUI:CreateClosuresView(parent)
    local closures = Instance.new("Frame")
    closures.Name = "Closures"
    closures.Size = UDim2.new(1, 0, 1, 0)
    closures.BackgroundTransparency = 1
    closures.Visible = false
    closures.Parent = parent
    
    -- Header with controls
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = self.Colors.Header
    header.BorderSizePixel = 0
    header.Parent = closures
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(0, 200, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "FUNCTION CLOSURES"
    title.TextColor3 = self.Colors.Text
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.Parent = header
    
    local scanButton = Instance.new("TextButton")
    scanButton.Name = "ScanButton"
    scanButton.Size = UDim2.new(0, 120, 0, 30)
    scanButton.Position = UDim2.new(1, -130, 0.5, -15)
    scanButton.BackgroundColor3 = self.Colors.Accent
    scanButton.BorderSizePixel = 0
    scanButton.Text = "Scan Closures"
    scanButton.TextColor3 = self.Colors.Text
    scanButton.TextSize = 14
    scanButton.Font = Enum.Font.Gotham
    scanButton.Parent = header
    
    -- Closures List
    local listFrame = Instance.new("Frame")
    listFrame.Name = "ClosuresList"
    listFrame.Size = UDim2.new(1, 0, 1, -40)
    listFrame.Position = UDim2.new(0, 0, 0, 40)
    listFrame.BackgroundTransparency = 1
    listFrame.Parent = closures
    
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "Scroll"
    scrollFrame.Size = UDim2.new(1, 0, 1, 0)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.Parent = listFrame
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.Name = "ListLayout"
    listLayout.Parent = scrollFrame
    
    self._closuresScroll = scrollFrame
    self._scanClosuresButton = scanButton
end

-- Tables View
function ProfessionalGUI:CreateTablesView(parent)
    local tables = Instance.new("Frame")
    tables.Name = "Tables"
    tables.Size = UDim2.new(1, 0, 1, 0)
    tables.BackgroundTransparency = 1
    tables.Visible = false
    tables.Parent = parent
    
    -- Similar structure to closures view but for tables
    -- ... (implementation similar to closures view)
end

-- Upvalues View
function ProfessionalGUI:CreateUpvaluesView(parent)
    local upvalues = Instance.new("Frame")
    upvalues.Name = "Upvalues"
    upvalues.Size = UDim2.new(1, 0, 1, 0)
    upvalues.BackgroundTransparency = 1
    upvalues.Visible = false
    upvalues.Parent = parent
    
    -- Similar structure to closures view but for upvalues
    -- ... (implementation similar to closures view)
end

-- Events View
function ProfessionalGUI:CreateEventsView(parent)
    local events = Instance.new("Frame")
    events.Name = "Events"
    events.Size = UDim2.new(1, 0, 1, 0)
    events.BackgroundTransparency = 1
    events.Visible = false
    events.Parent = parent
    
    -- Similar structure but for events log
    -- ... (implementation similar to closures view)
end

-- Require Log View
function ProfessionalGUI:CreateRequireLogView(parent)
    local requireLog = Instance.new("Frame")
    requireLog.Name = "RequireLog"
    requireLog.Size = UDim2.new(1, 0, 1, 0)
    requireLog.BackgroundTransparency = 1
    requireLog.Visible = false
    requireLog.Parent = parent
    
    -- Similar structure but for require calls
    -- ... (implementation similar to closures view)
end

-- Search View
function ProfessionalGUI:CreateSearchView(parent)
    local search = Instance.new("Frame")
    search.Name = "Search"
    search.Size = UDim2.new(1, 0, 1, 0)
    search.BackgroundTransparency = 1
    search.Visible = false
    search.Parent = parent
    
    -- Search box and results
    -- ... (implementation with search input and results list)
end

-- Snapshots View
function ProfessionalGUI:CreateSnapshotsView(parent)
    local snapshots = Instance.new("Frame")
    snapshots.Name = "Snapshots"
    snapshots.Size = UDim2.new(1, 0, 1, 0)
    snapshots.BackgroundTransparency = 1
    snapshots.Visible = false
    snapshots.Parent = parent
    
    -- Snapshot management and diff viewing
    -- ... (implementation for snapshot controls and diff display)
end

-- Settings View
function ProfessionalGUI:CreateSettingsView(parent)
    local settings = Instance.new("Frame")
    settings.Name = "Settings"
    settings.Size = UDim2.new(1, 0, 1, 0)
    settings.BackgroundTransparency = 1
    settings.Visible = false
    settings.Parent = parent
    
    -- Configuration options
    -- ... (implementation for various settings)
end

-- View Management
function ProfessionalGUI:SwitchView(viewName)
    -- Hide all views
    local content = self._gui:FindFirstChild("MainWindow"):FindFirstChild("Content"):FindFirstChild("MainContent")
    for _, child in ipairs(content:GetChildren()) do
        child.Visible = false
    end
    
    -- Show selected view
    local targetView = content:FindFirstChild(viewName:gsub("^%l", string.upper))
    if targetView then
        targetView.Visible = true
        self._currentView = viewName
    end
    
    -- Update sidebar button states
    self:UpdateSidebarButtons()
end

function ProfessionalGUI:UpdateSidebarButtons()
    local sidebar = self._gui:FindFirstChild("MainWindow"):FindFirstChild("Content"):FindFirstChild("Sidebar")
    for _, button in ipairs(sidebar:GetChildren()) do
        if button:IsA("TextButton") then
            local viewName = button.Name:lower()
            if viewName == self._currentView then
                button.BackgroundColor3 = self.Colors.Accent
            else
                button.BackgroundColor3 = self.Colors.Panel
            end
        end
    end
end

-- Quick Actions Handler
function ProfessionalGUI:HandleQuickAction(action)
    if action == "Start Monitoring" then
        UltraViewer.start()
        self:UpdateStatus("Monitoring started", self.Colors.Success)
    elseif action == "Take Snapshot" then
        UltraViewer.takeSnapshot("manual_" .. os.time())
        self:UpdateStatus("Snapshot taken", self.Colors.Success)
    elseif action == "Clear Data" then
        UltraViewer.cleanup()
        self:UpdateStatus("Data cleared", self.Colors.Warning)
    end
    self:RefreshOverview()
end

-- Status Updates
function ProfessionalGUI:UpdateStatus(message, color)
    if self._statusLabel then
        self._statusLabel.Text = message
        self._statusLabel.TextColor3 = color
    end
end

-- Data Refresh
function ProfessionalGUI:RefreshOverview()
    if not UltraViewer then return end
    
    local stats = UltraViewer.getStats()
    if stats then
        if self._statObjectsTracked then
            self._statObjectsTracked.Text = tostring(stats.objects or 0)
        end
        if self._statTablesWatched then
            self._statTablesWatched.Text = tostring(stats.watchers or 0)
        end
        if self._statEventsLogged then
            self._statEventsLogged.Text = tostring(stats.events or 0)
        end
    end
end

-- Toggle Visibility
function ProfessionalGUI:ToggleVisibility()
    if self._gui then
        self._gui.Enabled = not self._gui.Enabled
    end
end

-- Show/Hide
function ProfessionalGUI:Show()
    if self._gui then
        self._gui.Enabled = true
    end
end

function ProfessionalGUI:Hide()
    if self._gui then
        self._gui.Enabled = false
    end
end

-- Initialize the GUI
function ProfessionalGUI:Init(parent)
    local gui = self:Create()
    gui.Parent = parent
    
    -- Start auto-refresh
    while true do
        wait(2) -- Refresh every 2 seconds
        if self._currentView == "overview" then
            self:RefreshOverview()
        end
    end
end

return ProfessionalGUI