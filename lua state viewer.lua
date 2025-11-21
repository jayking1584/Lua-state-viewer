-- Universal Lua State Viewer for Roblox - Auto-Open Edition
-- Enhanced with all fixes and auto-opens GUI in PlayerGui

local UniversalLuaStateViewer = {}
UniversalLuaStateViewer.__index = UniversalLuaStateViewer

-- Core Data Structures
local state = {
    closures = {},
    upvalues = {},
    tables = {},
    modules = {},
    metatables = {},
    globals = {},
    constants = {},
    prototypes = {},
    execution = {},
    snapshots = {},
    currentSnapshot = 1
}

-- Color Scheme
local colors = {
    background = Color3.fromRGB(28, 28, 36),
    sidebar = Color3.fromRGB(35, 35, 45),
    header = Color3.fromRGB(45, 45, 58),
    accent = Color3.fromRGB(0, 162, 255),
    success = Color3.fromRGB(76, 175, 80),
    warning = Color3.fromRGB(255, 152, 0),
    error = Color3.fromRGB(244, 67, 54),
    text = Color3.fromRGB(240, 240, 240),
    textSecondary = Color3.fromRGB(180, 180, 190)
}

-- Store original functions for safe hooking
local originalFunctions = {
    loadstring = nil,
    setmetatable = nil,
    require = nil
}

function UniversalLuaStateViewer.new()
    local self = setmetatable({}, UniversalLuaStateViewer)
    self.enabled = false
    self.gui = nil
    self.isMinimized = false
    self.originalSize = nil
    self.originalPosition = nil
    self.guiUpdateQueue = {}
    self.guiUpdatePending = false
    return self
end

-- =========================================
-- 1. CIRCULAR TABLE DETECTION & DEPTH LIMIT
-- =========================================

function UniversalLuaStateViewer:captureTable(tbl, name, visited, depth)
    visited = visited or {}
    depth = depth or 1
    
    -- Prevent circular references
    if visited[tbl] then
        return visited[tbl].id
    end
    
    -- Depth limit to prevent freezing
    if depth > 5 then
        return "depth_limit_reached"
    end
    
    local tableId = tostring(tbl)
    
    if not state.tables[tableId] then
        state.tables[tableId] = {
            id = tableId,
            name = name or "anonymous_table",
            elements = {},
            metatable = nil,
            size = 0,
            timestamp = tick(),
            depth = depth
        }
        
        visited[tbl] = state.tables[tableId]
        self:captureTableContents(tbl, tableId, visited, depth)
        self:monitorTableChanges(tbl, tableId)
    end
    
    return tableId
end

function UniversalLuaStateViewer:captureTableContents(tbl, tableId, visited, depth)
    local elements = {}
    local count = 0
    
    for k, v in pairs(tbl) do
        count = count + 1
        elements[tostring(k)] = {
            key = k,
            value = v,
            keyType = type(k),
            valueType = type(v),
            captured = false
        }
        
        -- Recursively capture nested tables with depth limit
        if type(v) == "table" then
            elements[tostring(k)].captured = true
            self:captureTable(v, "nested_table_" .. tableId, visited, depth + 1)
        end
    end
    
    state.tables[tableId].elements = elements
    state.tables[tableId].size = count
end

-- =========================================
-- 2. COMPLETE GUI TABS IMPLEMENTATION
-- =========================================

function UniversalLuaStateViewer:createUpvalueView(parent)
    local statsBar = Instance.new("Frame")
    statsBar.Size = UDim2.new(1, 0, 0, 30)
    statsBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    statsBar.BorderSizePixel = 0
    statsBar.Parent = parent
    
    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(0.3, 0, 1, 0)
    countLabel.BackgroundTransparency = 1
    countLabel.TextColor3 = colors.success
    countLabel.Text = "Upvalue Sets: " .. self:countTable(state.upvalues)
    countLabel.Font = Enum.Font.Gotham
    countLabel.TextSize = 12
    countLabel.Parent = statsBar
    
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -30)
    scroll.Position = UDim2.new(0, 0, 0, 30)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.Parent = parent
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    local count = 0
    for closureId, upvalues in pairs(state.upvalues) do
        local upvalueSetFrame = Instance.new("Frame")
        upvalueSetFrame.Size = UDim2.new(1, -20, 0, 80)
        upvalueSetFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
        upvalueSetFrame.BorderSizePixel = 0
        upvalueSetFrame.Parent = scroll
        
        local closureLabel = Instance.new("TextLabel")
        closureLabel.Size = UDim2.new(1, -20, 0.4, 0)
        closureLabel.Position = UDim2.new(0, 10, 0, 5)
        closureLabel.BackgroundTransparency = 1
        closureLabel.TextColor3 = colors.accent
        closureLabel.Text = "Closure: " .. (state.closures[closureId] and state.closures[closureId].name or closureId)
        closureLabel.Font = Enum.Font.GothamBold
        closureLabel.TextSize = 14
        closureLabel.TextXAlignment = Enum.TextXAlignment.Left
        closureLabel.Parent = upvalueSetFrame
        
        local upvalueCount = 0
        for name, upvalue in pairs(upvalues) do
            upvalueCount = upvalueCount + 1
        end
        
        local countLabel = Instance.new("TextLabel")
        countLabel.Size = UDim2.new(1, -20, 0.3, 0)
        countLabel.Position = UDim2.new(0, 10, 0.4, 0)
        countLabel.BackgroundTransparency = 1
        countLabel.TextColor3 = colors.textSecondary
        countLabel.Text = "Upvalues: " .. upvalueCount
        countLabel.Font = Enum.Font.Gotham
        countLabel.TextSize = 12
        countLabel.TextXAlignment = Enum.TextXAlignment.Left
        countLabel.Parent = upvalueSetFrame
        
        local viewButton = Instance.new("TextButton")
        viewButton.Size = UDim2.new(0.3, 0, 0.3, 0)
        viewButton.Position = UDim2.new(0.7, 0, 0.7, 0)
        viewButton.BackgroundColor3 = colors.accent
        viewButton.TextColor3 = colors.text
        viewButton.Text = "View Details"
        viewButton.Font = Enum.Font.Gotham
        viewButton.TextSize = 12
        viewButton.Parent = upvalueSetFrame
        
        viewButton.MouseButton1Click:Connect(function()
            self:showUpvalueDetails(closureId, upvalues)
        end)
        
        count = count + 1
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 85)
end

function UniversalLuaStateViewer:showUpvalueDetails(closureId, upvalues)
    local popup = Instance.new("Frame")
    popup.Size = UDim2.new(0.6, 0, 0.7, 0)
    popup.Position = UDim2.new(0.2, 0, 0.15, 0)
    popup.BackgroundColor3 = colors.background
    popup.BorderSizePixel = 0
    popup.ZIndex = 10
    popup.Parent = self.mainContainer
    
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = colors.header
    header.BorderSizePixel = 0
    header.ZIndex = 11
    header.Parent = popup
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.8, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = colors.text
    title.Text = "Upvalue Details - " .. (state.closures[closureId] and state.closures[closureId].name or closureId)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 12
    title.Parent = header
    
    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 30, 0.7, 0)
    closeButton.Position = UDim2.new(1, -35, 0.15, 0)
    closeButton.BackgroundColor3 = colors.error
    closeButton.TextColor3 = colors.text
    closeButton.Text = "×"
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 16
    closeButton.ZIndex = 12
    closeButton.Parent = header
    
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -20, 1, -60)
    scroll.Position = UDim2.new(0, 10, 0, 50)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.ZIndex = 11
    scroll.Parent = popup
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    local count = 0
    for name, upvalue in pairs(upvalues) do
        local upvalueFrame = Instance.new("Frame")
        upvalueFrame.Size = UDim2.new(1, 0, 0, 70)
        upvalueFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        upvalueFrame.BorderSizePixel = 0
        upvalueFrame.ZIndex = 11
        upvalueFrame.Parent = scroll
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -20, 0.3, 0)
        nameLabel.Position = UDim2.new(0, 10, 0, 5)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = colors.accent
        nameLabel.Text = "Name: " .. name
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 14
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 12
        nameLabel.Parent = upvalueFrame
        
        local typeLabel = Instance.new("TextLabel")
        typeLabel.Size = UDim2.new(0.5, -10, 0.3, 0)
        typeLabel.Position = UDim2.new(0, 10, 0.3, 0)
        typeLabel.BackgroundTransparency = 1
        typeLabel.TextColor3 = colors.textSecondary
        typeLabel.Text = "Type: " .. upvalue.type
        typeLabel.Font = Enum.Font.Gotham
        typeLabel.TextSize = 12
        typeLabel.TextXAlignment = Enum.TextXAlignment.Left
        typeLabel.ZIndex = 12
        typeLabel.Parent = upvalueFrame
        
        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size = UDim2.new(1, -20, 0.4, 0)
        valueLabel.Position = UDim2.new(0, 10, 0.6, 0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.TextColor3 = colors.text
        valueLabel.Text = "Value: " .. tostring(upvalue.value)
        valueLabel.Font = Enum.Font.Gotham
        valueLabel.TextSize = 12
        valueLabel.TextXAlignment = Enum.TextXAlignment.Left
        valueLabel.ZIndex = 12
        valueLabel.Parent = upvalueFrame
        
        count = count + 1
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 75)
    
    closeButton.MouseButton1Click:Connect(function()
        popup:Destroy()
    end)
end

function UniversalLuaStateViewer:createModuleView(parent)
    local statsBar = Instance.new("Frame")
    statsBar.Size = UDim2.new(1, 0, 0, 30)
    statsBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    statsBar.BorderSizePixel = 0
    statsBar.Parent = parent
    
    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(0.3, 0, 1, 0)
    countLabel.BackgroundTransparency = 1
    countLabel.TextColor3 = colors.success
    countLabel.Text = "Modules: " .. self:countTable(state.modules)
    countLabel.Font = Enum.Font.Gotham
    countLabel.TextSize = 12
    countLabel.Parent = statsBar
    
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -30)
    scroll.Position = UDim2.new(0, 0, 0, 30)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.Parent = parent
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    local count = 0
    for name, module in pairs(state.modules) do
        local moduleFrame = Instance.new("Frame")
        moduleFrame.Size = UDim2.new(1, -20, 0, 80)
        moduleFrame.BackgroundColor3 = module.success and Color3.fromRGB(45, 45, 58) or Color3.fromRGB(58, 45, 45)
        moduleFrame.BorderSizePixel = 0
        moduleFrame.Parent = scroll
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -20, 0.3, 0)
        nameLabel.Position = UDim2.new(0, 10, 0, 5)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = module.success and colors.accent or colors.error
        nameLabel.Text = "Module: " .. name
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 14
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = moduleFrame
        
        local statusLabel = Instance.new("TextLabel")
        statusLabel.Size = UDim2.new(0.5, -10, 0.3, 0)
        statusLabel.Position = UDim2.new(0, 10, 0.3, 0)
        statusLabel.BackgroundTransparency = 1
        statusLabel.TextColor3 = module.success and colors.success or colors.error
        statusLabel.Text = module.success and "✓ Success" or "✗ Failed"
        statusLabel.Font = Enum.Font.Gotham
        statusLabel.TextSize = 12
        statusLabel.TextXAlignment = Enum.TextXAlignment.Left
        statusLabel.Parent = moduleFrame
        
        local typeLabel = Instance.new("TextLabel")
        typeLabel.Size = UDim2.new(0.5, -10, 0.3, 0)
        typeLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
        typeLabel.BackgroundTransparency = 1
        typeLabel.TextColor3 = colors.textSecondary
        typeLabel.Text = "Type: " .. module.type
        typeLabel.Font = Enum.Font.Gotham
        typeLabel.TextSize = 12
        typeLabel.TextXAlignment = Enum.TextXAlignment.Right
        typeLabel.Parent = moduleFrame
        
        local timeLabel = Instance.new("TextLabel")
        timeLabel.Size = UDim2.new(1, -20, 0.4, 0)
        timeLabel.Position = UDim2.new(0, 10, 0.6, 0)
        timeLabel.BackgroundTransparency = 1
        timeLabel.TextColor3 = colors.textSecondary
        timeLabel.Text = "Loaded: " .. os.date("%H:%M:%S", module.timestamp)
        timeLabel.Font = Enum.Font.Gotham
        timeLabel.TextSize = 11
        timeLabel.TextXAlignment = Enum.TextXAlignment.Left
        timeLabel.Parent = moduleFrame
        
        count = count + 1
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 85)
end

function UniversalLuaStateViewer:createMetatableView(parent)
    local statsBar = Instance.new("Frame")
    statsBar.Size = UDim2.new(1, 0, 0, 30)
    statsBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    statsBar.BorderSizePixel = 0
    statsBar.Parent = parent
    
    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(0.3, 0, 1, 0)
    countLabel.BackgroundTransparency = 1
    countLabel.TextColor3 = colors.success
    countLabel.Text = "Metatables: " .. self:countTable(state.metatables)
    countLabel.Font = Enum.Font.Gotham
    countLabel.TextSize = 12
    countLabel.Parent = statsBar
    
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -30)
    scroll.Position = UDim2.new(0, 0, 0, 30)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.Parent = parent
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    local count = 0
    for id, metatable in pairs(state.metatables) do
        local metaFrame = Instance.new("Frame")
        metaFrame.Size = UDim2.new(1, -20, 0, 100)
        metaFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
        metaFrame.BorderSizePixel = 0
        metaFrame.Parent = scroll
        
        local idLabel = Instance.new("TextLabel")
        idLabel.Size = UDim2.new(1, -20, 0.3, 0)
        idLabel.Position = UDim2.new(0, 10, 0, 5)
        idLabel.BackgroundTransparency = 1
        idLabel.TextColor3 = colors.accent
        idLabel.Text = "Metatable: " .. id:sub(1, 12) .. "..."
        idLabel.Font = Enum.Font.GothamBold
        idLabel.TextSize = 14
        idLabel.TextXAlignment = Enum.TextXAlignment.Left
        idLabel.Parent = metaFrame
        
        local attachedLabel = Instance.new("TextLabel")
        attachedLabel.Size = UDim2.new(1, -20, 0.3, 0)
        attachedLabel.Position = UDim2.new(0, 10, 0.3, 0)
        attachedLabel.BackgroundTransparency = 1
        attachedLabel.TextColor3 = colors.textSecondary
        attachedLabel.Text = "Attached to: " .. (metatable.attachedTo or "unknown")
        attachedLabel.Font = Enum.Font.Gotham
        attachedLabel.TextSize = 12
        attachedLabel.TextXAlignment = Enum.TextXAlignment.Left
        attachedLabel.Parent = metaFrame
        
        local methodsLabel = Instance.new("TextLabel")
        methodsLabel.Size = UDim2.new(1, -20, 0.2, 0)
        methodsLabel.Position = UDim2.new(0, 10, 0.6, 0)
        methodsLabel.BackgroundTransparency = 1
        methodsLabel.TextColor3 = colors.textSecondary
        methodsLabel.Text = "Methods: " .. self:countTable(metatable.methods)
        methodsLabel.Font = Enum.Font.Gotham
        methodsLabel.TextSize = 12
        methodsLabel.TextXAlignment = Enum.TextXAlignment.Left
        methodsLabel.Parent = metaFrame
        
        local timeLabel = Instance.new("TextLabel")
        timeLabel.Size = UDim2.new(1, -20, 0.2, 0)
        timeLabel.Position = UDim2.new(0, 10, 0.8, 0)
        timeLabel.BackgroundTransparency = 1
        timeLabel.TextColor3 = colors.textSecondary
        timeLabel.Text = "Created: " .. os.date("%H:%M:%S", metatable.timestamp)
        timeLabel.Font = Enum.Font.Gotham
        timeLabel.TextSize = 11
        timeLabel.TextXAlignment = Enum.TextXAlignment.Left
        timeLabel.Parent = metaFrame
        
        count = count + 1
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 105)
end

function UniversalLuaStateViewer:createGlobalsView(parent)
    local statsBar = Instance.new("Frame")
    statsBar.Size = UDim2.new(1, 0, 0, 30)
    statsBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    statsBar.BorderSizePixel = 0
    statsBar.Parent = parent
    
    local globalTable = state.tables[tostring(_G)] or {size = 0}
    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(0.3, 0, 1, 0)
    countLabel.BackgroundTransparency = 1
    countLabel.TextColor3 = colors.success
    countLabel.Text = "Global Entries: " .. globalTable.size
    countLabel.Font = Enum.Font.Gotham
    countLabel.TextSize = 12
    countLabel.Parent = statsBar
    
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -30)
    scroll.Position = UDim2.new(0, 0, 0, 30)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.Parent = parent
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    local globalEnv = getfenv and getfenv(2) or _G
    local count = 0
    
    for key, value in pairs(globalEnv) do
        if count < 100 then -- Limit for performance
            local globalFrame = Instance.new("Frame")
            globalFrame.Size = UDim2.new(1, -20, 0, 50)
            globalFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
            globalFrame.BorderSizePixel = 0
            globalFrame.Parent = scroll
            
            local keyLabel = Instance.new("TextLabel")
            keyLabel.Size = UDim2.new(0.4, -10, 1, 0)
            keyLabel.Position = UDim2.new(0, 10, 0, 0)
            keyLabel.BackgroundTransparency = 1
            keyLabel.TextColor3 = colors.accent
            keyLabel.Text = tostring(key)
            keyLabel.Font = Enum.Font.GothamBold
            keyLabel.TextSize = 14
            keyLabel.TextXAlignment = Enum.TextXAlignment.Left
            keyLabel.Parent = globalFrame
            
            local valueLabel = Instance.new("TextLabel")
            valueLabel.Size = UDim2.new(0.6, -10, 1, 0)
            valueLabel.Position = UDim2.new(0.4, 0, 0, 0)
            valueLabel.BackgroundTransparency = 1
            valueLabel.TextColor3 = colors.text
            valueLabel.Text = type(value) .. ": " .. tostring(value):sub(1, 50)
            valueLabel.Font = Enum.Font.Gotham
            valueLabel.TextSize = 12
            valueLabel.TextXAlignment = Enum.TextXAlignment.Left
            valueLabel.Parent = globalFrame
            
            count = count + 1
        else
            break
        end
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 55)
end

function UniversalLuaStateViewer:createConstantsView(parent)
    local statsBar = Instance.new("Frame")
    statsBar.Size = UDim2.new(1, 0, 0, 30)
    statsBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    statsBar.BorderSizePixel = 0
    statsBar.Parent = parent
    
    local totalConstants = 0
    for _, closure in pairs(state.closures) do
        totalConstants = totalConstants + #closure.constants
    end
    
    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(0.3, 0, 1, 0)
    countLabel.BackgroundTransparency = 1
    countLabel.TextColor3 = colors.success
    countLabel.Text = "Total Constants: " .. totalConstants
    countLabel.Font = Enum.Font.Gotham
    countLabel.TextSize = 12
    countLabel.Parent = statsBar
    
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -30)
    scroll.Position = UDim2.new(0, 0, 0, 30)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.Parent = parent
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    local count = 0
    for closureId, closure in pairs(state.closures) do
        if #closure.constants > 0 then
            local constantSetFrame = Instance.new("Frame")
            constantSetFrame.Size = UDim2.new(1, -20, 0, 60)
            constantSetFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
            constantSetFrame.BorderSizePixel = 0
            constantSetFrame.Parent = scroll
            
            local closureLabel = Instance.new("TextLabel")
            closureLabel.Size = UDim2.new(1, -20, 0.5, 0)
            closureLabel.Position = UDim2.new(0, 10, 0, 5)
            closureLabel.BackgroundTransparency = 1
            closureLabel.TextColor3 = colors.accent
            closureLabel.Text = closure.name .. " - " .. #closure.constants .. " constants"
            closureLabel.Font = Enum.Font.GothamBold
            closureLabel.TextSize = 14
            closureLabel.TextXAlignment = Enum.TextXAlignment.Left
            closureLabel.Parent = constantSetFrame
            
            local viewButton = Instance.new("TextButton")
            viewButton.Size = UDim2.new(0.3, 0, 0.5, 0)
            viewButton.Position = UDim2.new(0.7, 0, 0.5, 0)
            viewButton.BackgroundColor3 = colors.accent
            viewButton.TextColor3 = colors.text
            viewButton.Text = "View Constants"
            viewButton.Font = Enum.Font.Gotham
            viewButton.TextSize = 12
            viewButton.Parent = constantSetFrame
            
            viewButton.MouseButton1Click:Connect(function()
                self:showConstantDetails(closureId, closure.constants)
            end)
            
            count = count + 1
        end
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 65)
end

function UniversalLuaStateViewer:showConstantDetails(closureId, constants)
    local popup = Instance.new("Frame")
    popup.Size = UDim2.new(0.6, 0, 0.7, 0)
    popup.Position = UDim2.new(0.2, 0, 0.15, 0)
    popup.BackgroundColor3 = colors.background
    popup.BorderSizePixel = 0
    popup.ZIndex = 10
    popup.Parent = self.mainContainer
    
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = colors.header
    header.BorderSizePixel = 0
    header.ZIndex = 11
    header.Parent = popup
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.8, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = colors.text
    title.Text = "Constants - " .. (state.closures[closureId] and state.closures[closureId].name or closureId)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 12
    title.Parent = header
    
    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 30, 0.7, 0)
    closeButton.Position = UDim2.new(1, -35, 0.15, 0)
    closeButton.BackgroundColor3 = colors.error
    closeButton.TextColor3 = colors.text
    closeButton.Text = "×"
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 16
    closeButton.ZIndex = 12
    closeButton.Parent = header
    
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -20, 1, -60)
    scroll.Position = UDim2.new(0, 10, 0, 50)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.ZIndex = 11
    scroll.Parent = popup
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    for i, constant in ipairs(constants) do
        local constantFrame = Instance.new("Frame")
        constantFrame.Size = UDim2.new(1, 0, 0, 50)
        constantFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        constantFrame.BorderSizePixel = 0
        constantFrame.ZIndex = 11
        constantFrame.Parent = scroll
        
        local indexLabel = Instance.new("TextLabel")
        indexLabel.Size = UDim2.new(0.1, 0, 1, 0)
        indexLabel.Position = UDim2.new(0, 10, 0, 0)
        indexLabel.BackgroundTransparency = 1
        indexLabel.TextColor3 = colors.accent
        indexLabel.Text = "#" .. i
        indexLabel.Font = Enum.Font.GothamBold
        indexLabel.TextSize = 14
        indexLabel.TextXAlignment = Enum.TextXAlignment.Left
        indexLabel.ZIndex = 12
        indexLabel.Parent = constantFrame
        
        local typeLabel = Instance.new("TextLabel")
        typeLabel.Size = UDim2.new(0.2, 0, 1, 0)
        typeLabel.Position = UDim2.new(0.1, 0, 0, 0)
        typeLabel.BackgroundTransparency = 1
        typeLabel.TextColor3 = colors.textSecondary
        typeLabel.Text = constant.type
        typeLabel.Font = Enum.Font.Gotham
        typeLabel.TextSize = 12
        typeLabel.TextXAlignment = Enum.TextXAlignment.Left
        typeLabel.ZIndex = 12
        typeLabel.Parent = constantFrame
        
        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size = UDim2.new(0.7, -10, 1, 0)
        valueLabel.Position = UDim2.new(0.3, 0, 0, 0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.TextColor3 = colors.text
        valueLabel.Text = tostring(constant.value)
        valueLabel.Font = Enum.Font.Gotham
        valueLabel.TextSize = 12
        valueLabel.TextXAlignment = Enum.TextXAlignment.Left
        valueLabel.ZIndex = 12
        valueLabel.Parent = constantFrame
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, #constants * 55)
    
    closeButton.MouseButton1Click:Connect(function()
        popup:Destroy()
    end)
end

-- =========================================
-- 3. EXPANDED DIFF SYSTEM
-- =========================================

function UniversalLuaStateViewer:compareUpvalues(old, new)
    local diff = {added = {}, removed = {}, modified = {}}
    
    for id, upvalue in pairs(new) do
        if not old[id] then
            diff.added[id] = upvalue
        end
    end
    
    for id, upvalue in pairs(old) do
        if not new[id] then
            diff.removed[id] = upvalue
        end
    end
    
    return diff
end

function UniversalLuaStateViewer:compareMetatables(old, new)
    local diff = {added = {}, removed = {}, modified = {}}
    
    for id, metatable in pairs(new) do
        if not old[id] then
            diff.added[id] = metatable
        end
    end
    
    for id, metatable in pairs(old) do
        if not new[id] then
            diff.removed[id] = metatable
        end
    end
    
    return diff
end

function UniversalLuaStateViewer:compareGlobals(old, new)
    local diff = {added = {}, removed = {}, modified = {}}
    
    -- Compare _G table sizes
    local oldGlobalId = tostring(_G)
    local newGlobalId = tostring(_G)
    
    if old[oldGlobalId] and new[newGlobalId] then
        if old[oldGlobalId].size ~= new[newGlobalId].size then
            diff.modified[oldGlobalId] = {
                old = old[oldGlobalId],
                new = new[newGlobalId]
            }
        end
    end
    
    return diff
end

function UniversalLuaStateViewer:compareConstants(old, new)
    local diff = {added = {}, removed = {}, modified = {}}
    
    -- Compare total constants count per closure
    for closureId, newClosure in pairs(new) do
        local oldClosure = old[closureId]
        if not oldClosure then
            diff.added[closureId] = newClosure
        elseif #oldClosure.constants ~= #newClosure.constants then
            diff.modified[closureId] = {
                old = oldClosure,
                new = newClosure
            }
        end
    end
    
    for closureId, oldClosure in pairs(old) do
        if not new[closureId] then
            diff.removed[closureId] = oldClosure
        end
    end
    
    return diff
end

-- =========================================
-- 4. DEEP COPY SNAPSHOTS
-- =========================================

function UniversalLuaStateViewer:deepCopyTable(orig, visited)
    visited = visited or {}
    
    if visited[orig] then
        return visited[orig]
    end
    
    local copy = {}
    visited[orig] = copy
    
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = self:deepCopyTable(v, visited)
        else
            copy[k] = v
        end
    end
    
    return copy
end

function UniversalLuaStateViewer:takeSnapshot(name)
    local snapshot = {
        name = name or "Snapshot_" .. state.currentSnapshot,
        timestamp = tick(),
        closures = self:deepCopyTable(state.closures),
        upvalues = self:deepCopyTable(state.upvalues),
        tables = self:deepCopyTable(state.tables),
        modules = self:deepCopyTable(state.modules),
        metatables = self:deepCopyTable(state.metatables),
        globals = self:deepCopyTable(state.globals),
        execution = self:deepCopyTable(state.execution)
    }
    
    state.snapshots[state.currentSnapshot] = snapshot
    state.currentSnapshot = state.currentSnapshot + 1
    
    return #state.snapshots
end

-- =========================================
-- 5. EXECUTION TRACE ENHANCEMENTS
-- =========================================

function UniversalLuaStateViewer:recordFunctionCall(level)
    local info = debug.getinfo(level, "nS")
    if info then
        -- Try to capture arguments (limited in Roblox Luau)
        local args = {}
        for i = 1, math.huge do
            local name, value = pcall(debug.getlocal, level + 1, i)
            if not name or not value then break end
            if string.sub(value, 1, 1) == "(" then break end -- Stop at vararg
            
            table.insert(args, {
                name = name,
                value = tostring(value),
                type = type(value)
            })
            
            if i > 10 then break end -- Limit for performance
        end
        
        local call = {
            type = "call",
            name = info.name or "anonymous",
            source = info.source,
            linedefined = info.linedefined,
            args = args,
            timestamp = tick(),
            stack = self:getStackTrace()
        }
        table.insert(state.execution, call)
    end
end

function UniversalLuaStateViewer:recordFunctionReturn(level)
    local info = debug.getinfo(level, "nS")
    if info then
        -- Try to capture return values (limited in Roblox Luau)
        local returns = {}
        for i = 1, math.huge do
            local success, name, value = pcall(debug.getlocal, level, -i)
            if not success or not name then break end
            
            table.insert(returns, {
                name = name,
                value = tostring(value),
                type = type(value)
            })
            
            if i > 5 then break end -- Limit for performance
        end
        
        local returnRecord = {
            type = "return",
            name = info.name or "anonymous",
            source = info.source,
            returns = returns,
            timestamp = tick(),
            stack = self:getStackTrace()
        }
        table.insert(state.execution, returnRecord)
    end
end

-- =========================================
-- 6. GUI PERFORMANCE OPTIMIZATIONS
-- =========================================

function UniversalLuaStateViewer:queueGUIUpdate(callback)
    table.insert(self.guiUpdateQueue, callback)
    
    if not self.guiUpdatePending then
        self.guiUpdatePending = true
        
        -- Spread GUI updates over multiple frames
        spawn(function()
            local processed = 0
            while #self.guiUpdateQueue > 0 and processed < 5 do -- Process max 5 per frame
                local callback = table.remove(self.guiUpdateQueue, 1)
                pcall(callback)
                processed = processed + 1
                wait(0.01) -- Small delay between updates
            end
            self.guiUpdatePending = false
        end)
    end
end

function UniversalLuaStateViewer:createPaginatedView(parent, data, createItemFunc, itemsPerPage)
    itemsPerPage = itemsPerPage or 50
    
    local currentPage = 1
    local totalPages = math.ceil(self:countTable(data) / itemsPerPage)
    
    local controlBar = Instance.new("Frame")
    controlBar.Size = UDim2.new(1, 0, 0, 40)
    controlBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    controlBar.BorderSizePixel = 0
    controlBar.Parent = parent
    
    local prevButton = Instance.new("TextButton")
    prevButton.Size = UDim2.new(0.1, 0, 0.6, 0)
    prevButton.Position = UDim2.new(0.05, 0, 0.2, 0)
    prevButton.BackgroundColor3 = colors.accent
    prevButton.TextColor3 = colors.text
    prevButton.Text = "◀"
    prevButton.Font = Enum.Font.GothamBold
    prevButton.TextSize = 14
    prevButton.Parent = controlBar
    
    local pageLabel = Instance.new("TextLabel")
    pageLabel.Size = UDim2.new(0.2, 0, 1, 0)
    pageLabel.Position = UDim2.new(0.4, 0, 0, 0)
    pageLabel.BackgroundTransparency = 1
    pageLabel.TextColor3 = colors.text
    pageLabel.Text = "Page 1/" .. totalPages
    pageLabel.Font = Enum.Font.Gotham
    pageLabel.TextSize = 12
    pageLabel.Parent = controlBar
    
    local nextButton = Instance.new("TextButton")
    nextButton.Size = UDim2.new(0.1, 0, 0.6, 0)
    nextButton.Position = UDim2.new(0.85, 0, 0.2, 0)
    nextButton.BackgroundColor3 = colors.accent
    nextButton.TextColor3 = colors.text
    nextButton.Text = "▶"
    nextButton.Font = Enum.Font.GothamBold
    nextButton.TextSize = 14
    nextButton.Parent = controlBar
    
    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, 0, 1, -40)
    contentFrame.Position = UDim2.new(0, 0, 0, 40)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = parent
    
    local function showPage(page)
        -- Clear current content
        for _, child in ipairs(contentFrame:GetChildren()) do
            child:Destroy()
        end
        
        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, 0, 1, 0)
        scroll.BackgroundTransparency = 1
        scroll.ScrollBarThickness = 8
        scroll.Parent = contentFrame
        
        local items = {}
        for id, item in pairs(data) do
            table.insert(items, {id = id, item = item})
        end
        
        -- Sort by timestamp if available
        table.sort(items, function(a, b)
            return (a.item.timestamp or 0) > (b.item.timestamp or 0)
        end)
        
        local startIndex = (page - 1) * itemsPerPage + 1
        local endIndex = math.min(startIndex + itemsPerPage - 1, #items)
        
        for i = startIndex, endIndex do
            createItemFunc(scroll, items[i].id, items[i].item, i - startIndex + 1)
        end
        
        scroll.CanvasSize = UDim2.new(0, 0, 0, (endIndex - startIndex + 1) * 80)
        pageLabel.Text = "Page " .. page .. "/" .. totalPages
        currentPage = page
        
        prevButton.Visible = page > 1
        nextButton.Visible = page < totalPages
    end
    
    prevButton.MouseButton1Click:Connect(function()
        if currentPage > 1 then
            showPage(currentPage - 1)
        end
    end)
    
    nextButton.MouseButton1Click:Connect(function()
        if currentPage < totalPages then
            showPage(currentPage + 1)
        end
    end)
    
    showPage(1)
end

-- =========================================
-- 7. SEARCH ENHANCEMENTS
-- =========================================

function UniversalLuaStateViewer:performSearch(query, resultsFrame)
    for _, child in ipairs(resultsFrame:GetChildren()) do
        child:Destroy()
    end
    
    if query == "" then
        local placeholder = Instance.new("TextLabel")
        placeholder.Size = UDim2.new(1, 0, 1, 0)
        placeholder.BackgroundTransparency = 1
        placeholder.TextColor3 = colors.textSecondary
        placeholder.Text = "Enter search terms to find closures, tables, modules..."
        placeholder.Font = Enum.Font.Gotham
        placeholder.TextSize = 14
        placeholder.Parent = resultsFrame
        return
    end
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = resultsFrame
    
    local categories = {
        {name = "Closures", data = state.closures, getDisplayName = function(item) return item.name end},
        {name = "Tables", data = state.tables, getDisplayName = function(item) return item.name end},
        {name = "Modules", data = state.modules, getDisplayName = function(item) return item.name end},
        {name = "Metatables", data = state.metatables, getDisplayName = function(item) return "Metatable for " .. (item.attachedTo or "unknown") end},
        {name = "Upvalues", data = state.upvalues, getDisplayName = function(item) return "Upvalue set" end}
    }
    
    local results = {}
    local queryLower = string.lower(query)
    
    for _, category in ipairs(categories) do
        for id, item in pairs(category.data) do
            local searchText = string.lower(tostring(category.getDisplayName and category.getDisplayName(item) or id))
            if string.find(searchText, queryLower) then
                table.insert(results, {
                    type = category.name,
                    data = item,
                    id = id,
                    displayName = category.getDisplayName and category.getDisplayName(item) or id
                })
            end
        end
    end
    
    -- Sort by relevance (simple string distance)
    table.sort(results, function(a, b)
        local aDist = string.len(a.displayName) - string.len(query)
        local bDist = string.len(b.displayName) - string.len(query)
        return math.abs(aDist) < math.abs(bDist)
    end)
    
    -- Display results
    for i, result in ipairs(results) do
        if i > 100 then break end -- Limit results
        
        local resultFrame = Instance.new("Frame")
        resultFrame.Size = UDim2.new(1, 0, 0, 60)
        resultFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
        resultFrame.BorderSizePixel = 0
        resultFrame.Parent = resultsFrame
        
        local typeLabel = Instance.new("TextLabel")
        typeLabel.Size = UDim2.new(0.2, 0, 0.5, 0)
        typeLabel.Position = UDim2.new(0, 10, 0, 5)
        typeLabel.BackgroundTransparency = 1
        typeLabel.TextColor3 = colors.accent
        typeLabel.Text = result.type
        typeLabel.Font = Enum.Font.GothamBold
        typeLabel.TextSize = 12
        typeLabel.TextXAlignment = Enum.TextXAlignment.Left
        typeLabel.Parent = resultFrame
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.8, -10, 0.5, 0)
        nameLabel.Position = UDim2.new(0.2, 0, 0, 5)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = colors.text
        nameLabel.Text = result.displayName
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextSize = 14
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = resultFrame
        
        local infoLabel = Instance.new("TextLabel")
        infoLabel.Size = UDim2.new(1, -20, 0.5, 0)
        infoLabel.Position = UDim2.new(0, 10, 0.5, 0)
        infoLabel.BackgroundTransparency = 1
        infoLabel.TextColor3 = colors.textSecondary
        infoLabel.Text = "ID: " .. tostring(result.id):sub(1, 20) .. "..."
        infoLabel.Font = Enum.Font.Gotham
        infoLabel.TextSize = 11
        infoLabel.TextXAlignment = Enum.TextXAlignment.Left
        infoLabel.Parent = resultFrame
    end
    
    resultsFrame.CanvasSize = UDim2.new(0, 0, 0, math.min(#results, 100) * 65)
end

-- =========================================
-- 9. SAFE HOOK OVERRIDES
-- =========================================

function UniversalLuaStateViewer:installHooks()
    if self.enabled then return end
    
    -- Store original functions
    originalFunctions.loadstring = loadstring or load
    originalFunctions.setmetatable = setmetatable
    originalFunctions.require = require
    
    self:installClosureHook()
    self:installTableHook()
    self:installRequireHook()
    self:installExecutionHook()
    self:installGlobalHook()
    
    self.enabled = true
end

function UniversalLuaStateViewer:restoreHooks()
    if originalFunctions.loadstring then
        loadstring = originalFunctions.loadstring
    end
    if originalFunctions.setmetatable then
        setmetatable = originalFunctions.setmetatable
    end
    if originalFunctions.require then
        require = originalFunctions.require
    end
end

-- =========================================
-- CORE HOOKING SYSTEM (Safe for Executor)
-- =========================================

function UniversalLuaStateViewer:installClosureHook()
    local success, err = pcall(function()
        local originalLoadstring = originalFunctions.loadstring
        if originalLoadstring then
            loadstring = function(str, chunkname)
                local func, loadErr = originalLoadstring(str, chunkname)
                if func then
                    pcall(function() self:captureClosure(func, chunkname or "loadstring", str) end)
                end
                return func, loadErr
            end
        end
        
        pcall(function() self:hookFunctionDefinitions() end)
    end)
    
    if not success then
        warn("Closure hook installation failed: " .. tostring(err))
    end
end

function UniversalLuaStateViewer:hookFunctionDefinitions()
    local originalG = getfenv and getfenv(2) or _G
    local meta = getmetatable(originalG) or {}
    local originalIndex = meta.__index or function(t, k) return rawget(t, k) end
    
    meta.__index = function(t, k)
        local value = originalIndex(t, k)
        if type(value) == "function" then
            pcall(function() self:captureClosure(value, k, "global_function") end)
        end
        return value
    end
    
    setmetatable(originalG, meta)
end

function UniversalLuaStateViewer:captureClosure(func, name, source)
    local closureId = tostring(func):gsub("function: ", "")
    
    if not state.closures[closureId] then
        state.closures[closureId] = {
            id = closureId,
            name = name or "anonymous",
            source = source or "unknown",
            upvalues = {},
            environment = {},
            proto = self:getPrototypeInfo(func),
            constants = self:getConstants(func),
            timestamp = tick()
        }
        
        self:captureUpvalues(func, closureId)
    end
    
    return closureId
end

function UniversalLuaStateViewer:captureUpvalues(func, closureId)
    local upvalueInfo = {}
    
    for i = 1, math.huge do
        local success, name, value = pcall(debug.getupvalue, func, i)
        if not success or not name then break end
        
        upvalueInfo[name] = {
            name = name,
            value = value,
            type = type(value),
            closureId = closureId,
            index = i
        }
        
        if type(value) == "table" then
            self:captureTable(value, name .. "_upvalue")
        end
    end
    
    state.closures[closureId].upvalues = upvalueInfo
    state.upvalues[closureId] = upvalueInfo
end

function UniversalLuaStateViewer:installTableHook()
    local success, err = pcall(function()
        local originalSetMetatable = originalFunctions.setmetatable
        setmetatable = function(t, mt)
            if type(t) == "table" then
                pcall(function() self:captureTable(t, "table_with_metatable") end)
                if mt then
                    pcall(function() self:captureMetatable(mt, t) end)
                end
            end
            return originalSetMetatable(t, mt)
        end
    end)
    
    if not success then
        warn("Table hook installation failed: " .. tostring(err))
    end
end

function UniversalLuaStateViewer:monitorTableChanges(tbl, tableId)
    local originalMeta = getmetatable(tbl) or {}
    local newMeta = {
        __newindex = function(t, key, value)
            self:recordTableChange(tableId, key, value, "set")
            rawset(t, key, value)
        end,
        __index = originalMeta.__index,
        __call = originalMeta.__call,
        __metatable = originalMeta.__metatable
    }
    
    setmetatable(tbl, newMeta)
end

function UniversalLuaStateViewer:recordTableChange(tableId, key, value, operation)
    if not state.tables[tableId] then return end
    
    local change = {
        tableId = tableId,
        key = key,
        value = value,
        operation = operation,
        timestamp = tick(),
        stack = self:getStackTrace()
    }
    
    table.insert(state.execution, change)
end

function UniversalLuaStateViewer:installRequireHook()
    local success, err = pcall(function()
        local originalRequire = originalFunctions.require
        require = function(module)
            local success, result = pcall(originalRequire, module)
            
            pcall(function()
                state.modules[module] = {
                    name = module,
                    result = result,
                    success = success,
                    timestamp = tick(),
                    type = type(result)
                }
                
                if success and type(result) == "table" then
                    self:captureTable(result, "module_" .. module)
                end
            end)
            
            return result
        end
    end)
    
    if not success then
        warn("Require hook installation failed: " .. tostring(err))
    end
end

function UniversalLuaStateViewer:installExecutionHook()
    pcall(function()
        debug.sethook(function(event, line)
            if event == "call" then
                self:recordFunctionCall(2)
            elseif event == "return" then
                self:recordFunctionReturn(2)
            end
        end, "cr", 0)
    end)
end

function UniversalLuaStateViewer:installGlobalHook()
    self:monitorGlobalEnvironment()
end

function UniversalLuaStateViewer:monitorGlobalEnvironment()
    local env = getfenv and getfenv(2) or _G
    self:captureTable(env, "_G")
end

function UniversalLuaStateViewer:captureMetatable(mt, originalTable)
    local mtId = tostring(mt)
    
    state.metatables[mtId] = {
        id = mtId,
        attachedTo = tostring(originalTable),
        methods = {},
        timestamp = tick()
    }
    
    for method, func in pairs(mt) do
        if type(func) == "function" then
            state.metatables[mtId].methods[method] = {
                name = method,
                closureId = self:captureClosure(func, method .. "_metamethod")
            }
        end
    end
end

-- =========================================
-- UTILITY FUNCTIONS
-- =========================================

function UniversalLuaStateViewer:getPrototypeInfo(func)
    local info = debug.getinfo(func, "S")
    return {
        source = info.source,
        linedefined = info.linedefined,
        lastlinedefined = info.lastdefined,
        what = info.what,
        nups = info.nups
    }
end

function UniversalLuaStateViewer:getConstants(func)
    local constants = {}
    local i = 1
    while true do
        local success, k, v = pcall(debug.getconstant, func, i)
        if not success then break end
        if k == nil then break end
        constants[i] = {index = i, value = v, type = type(v)}
        i = i + 1
    end
    return constants
end

function UniversalLuaStateViewer:getStackTrace()
    local stack = {}
    for i = 3, 10 do
        local info = debug.getinfo(i, "nSl")
        if not info then break end
        table.insert(stack, {
            name = info.name or "?",
            source = info.source,
            currentline = info.currentline
        })
    end
    return stack
end

function UniversalLuaStateViewer:countTable(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

-- =========================================
-- PROFESSIONAL GUI CREATION (Auto-Open)
-- =========================================

function UniversalLuaStateViewer:createGUI()
    if self.gui then self.gui:Destroy() end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "UniversalLuaStateViewer"
    screenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    
    -- Main Container
    local mainContainer = Instance.new("Frame")
    mainContainer.Size = UDim2.new(0.85, 0, 0.8, 0)
    mainContainer.Position = UDim2.new(0.075, 0, 0.1, 0)
    mainContainer.BackgroundColor3 = colors.background
    mainContainer.BorderSizePixel = 0
    mainContainer.ClipsDescendants = true
    mainContainer.Parent = screenGui
    
    -- Header
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = colors.header
    header.BorderSizePixel = 0
    header.Parent = mainContainer
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.6, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = colors.text
    title.Text = "Universal Lua State Viewer"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
    
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 15)
    padding.Parent = title
    
    -- Control Buttons
    local controlFrame = Instance.new("Frame")
    controlFrame.Size = UDim2.new(0.4, 0, 1, 0)
    controlFrame.Position = UDim2.new(0.6, 0, 0, 0)
    controlFrame.BackgroundTransparency = 1
    controlFrame.Parent = header
    
    local minimizeBtn = self:createControlButton("−", controlFrame, 0, function()
        self:toggleMinimize()
    end)
    
    local closeBtn = self:createControlButton("×", controlFrame, 1, function()
        self:stop()
    end)
    
    -- Status Bar
    local statusBar = Instance.new("Frame")
    statusBar.Size = UDim2.new(1, 0, 0, 25)
    statusBar.Position = UDim2.new(0, 0, 0, 40)
    statusBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    statusBar.BorderSizePixel = 0
    statusBar.Parent = mainContainer
    
    local statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1, -20, 1, 0)
    statusText.Position = UDim2.new(0, 10, 0, 0)
    statusText.BackgroundTransparency = 1
    statusText.TextColor3 = colors.textSecondary
    statusText.Text = "Ready - Monitoring VM State"
    statusText.Font = Enum.Font.Gotham
    statusText.TextSize = 12
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.Parent = statusBar
    
    -- Main Content Area
    local contentArea = Instance.new("Frame")
    contentArea.Size = UDim2.new(1, 0, 1, -65)
    contentArea.Position = UDim2.new(0, 0, 0, 65)
    contentArea.BackgroundTransparency = 1
    contentArea.Parent = mainContainer
    
    -- Sidebar
    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0.2, 0, 1, 0)
    sidebar.BackgroundColor3 = colors.sidebar
    sidebar.BorderSizePixel = 0
    sidebar.Parent = contentArea
    
    -- Content Frame
    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(0.8, 0, 1, 0)
    contentFrame.Position = UDim2.new(0.2, 0, 0, 0)
    contentFrame.BackgroundColor3 = colors.background
    contentFrame.BorderSizePixel = 0
    contentFrame.Parent = contentArea
    
    -- Create Tabs
    self:createSidebarTabs(sidebar, contentFrame)
    
    -- Make window draggable
    self:makeDraggable(mainContainer, header)
    
    self.gui = screenGui
    self.mainContainer = mainContainer
    self.statusText = statusText
    self.originalSize = mainContainer.Size
    self.originalPosition = mainContainer.Position
end

function UniversalLuaStateViewer:createControlButton(symbol, parent, index, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 30, 0.7, 0)
    button.Position = UDim2.new(1, -(index + 1) * 35, 0.15, 0)
    button.BackgroundColor3 = colors.accent
    button.TextColor3 = colors.text
    button.Text = symbol
    button.Font = Enum.Font.GothamBold
    button.TextSize = 16
    button.Parent = parent
    
    button.MouseButton1Click:Connect(callback)
    
    return button
end

function UniversalLuaStateViewer:createSidebarTabs(sidebar, contentFrame)
    local tabs = {
        {"Closures", "📋", "View all captured functions"},
        {"Upvalues", "🔗", "Inspect closure upvalues"},
        {"Tables", "🗂️", "Monitor table mutations"},
        {"Modules", "📦", "Require calls and results"},
        {"Metatables", "⚙️", "Metatable configurations"},
        {"Globals", "🌐", "Global environment changes"},
        {"Constants", "🔢", "Function constants"},
        {"Diff", "🔄", "Compare snapshots"},
        {"Search", "🔍", "Search across all data"}
    }
    
    local tabButtons = Instance.new("ScrollingFrame")
    tabButtons.Size = UDim2.new(1, 0, 1, 0)
    tabButtons.BackgroundTransparency = 1
    tabButtons.ScrollBarThickness = 4
    tabButtons.Parent = sidebar
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = tabButtons
    
    for i, tabData in ipairs(tabs) do
        local tabName, icon, description = tabData[1], tabData[2], tabData[3]
        
        local tabButton = Instance.new("TextButton")
        tabButton.Size = UDim2.new(1, -20, 0, 50)
        tabButton.Position = UDim2.new(0, 10, 0, (i-1) * 55)
        tabButton.BackgroundColor3 = colors.sidebar
        tabButton.BorderSizePixel = 0
        tabButton.Text = ""
        tabButton.Parent = tabButtons
        
        local iconLabel = Instance.new("TextLabel")
        iconLabel.Size = UDim2.new(0, 30, 1, 0)
        iconLabel.BackgroundTransparency = 1
        iconLabel.TextColor3 = colors.textSecondary
        iconLabel.Text = icon
        iconLabel.Font = Enum.Font.Gotham
        iconLabel.TextSize = 16
        iconLabel.Parent = tabButton
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -40, 0.6, 0)
        nameLabel.Position = UDim2.new(0, 30, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = colors.text
        nameLabel.Text = tabName
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 14
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = tabButton
        
        local descLabel = Instance.new("TextLabel")
        descLabel.Size = UDim2.new(1, -40, 0.4, 0)
        descLabel.Position = UDim2.new(0, 30, 0.6, 0)
        descLabel.BackgroundTransparency = 1
        descLabel.TextColor3 = colors.textSecondary
        descLabel.Text = description
        descLabel.Font = Enum.Font.Gotham
        descLabel.TextSize = 10
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.Parent = tabButton
        
        -- Hover effects
        tabButton.MouseEnter:Connect(function()
            tabButton.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        end)
        
        tabButton.MouseLeave:Connect(function()
            tabButton.BackgroundColor3 = colors.sidebar
        end)
        
        tabButton.MouseButton1Click:Connect(function()
            self:showTabContent(tabName, contentFrame)
        end)
    end
    
    tabButtons.CanvasSize = UDim2.new(0, 0, 0, #tabs * 55)
    
    -- Show first tab by default
    self:showTabContent("Closures", contentFrame)
end

function UniversalLuaStateViewer:showTabContent(tabName, contentFrame)
    -- Clear existing content
    for _, child in ipairs(contentFrame:GetChildren()) do
        child:Destroy()
    end
    
    -- Tab Header
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = colors.header
    header.BorderSizePixel = 0
    header.Parent = contentFrame
    
    local headerText = Instance.new("TextLabel")
    headerText.Size = UDim2.new(1, -20, 1, 0)
    headerText.Position = UDim2.new(0, 15, 0, 0)
    headerText.BackgroundTransparency = 1
    headerText.TextColor3 = colors.text
    headerText.Text = tabName
    headerText.Font = Enum.Font.GothamBold
    headerText.TextSize = 18
    headerText.TextXAlignment = Enum.TextXAlignment.Left
    headerText.Parent = header
    
    -- Content Area
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 1, -40)
    content.Position = UDim2.new(0, 0, 0, 40)
    content.BackgroundTransparency = 1
    content.Parent = contentFrame
    
    -- Tab-specific content
    if tabName == "Closures" then
        self:createPaginatedView(content, state.closures, function(scroll, id, closure, index)
            local closureFrame = Instance.new("Frame")
            closureFrame.Size = UDim2.new(1, -20, 0, 80)
            closureFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
            closureFrame.BorderSizePixel = 0
            closureFrame.Parent = scroll
            
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, -20, 0.4, 0)
            nameLabel.Position = UDim2.new(0, 10, 0, 5)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextColor3 = colors.accent
            nameLabel.Text = closure.name .. "  •  " .. id:sub(1, 8) .. "..."
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextSize = 14
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = closureFrame
            
            local sourceLabel = Instance.new("TextLabel")
            sourceLabel.Size = UDim2.new(1, -20, 0.3, 0)
            sourceLabel.Position = UDim2.new(0, 10, 0.4, 0)
            sourceLabel.BackgroundTransparency = 1
            sourceLabel.TextColor3 = colors.textSecondary
            sourceLabel.Text = "Source: " .. (closure.source:sub(1, 50) .. (closure.source:len() > 50 and "..." or ""))
            sourceLabel.Font = Enum.Font.Gotham
            sourceLabel.TextSize = 11
            sourceLabel.TextXAlignment = Enum.TextXAlignment.Left
            sourceLabel.Parent = closureFrame
            
            local upvalueLabel = Instance.new("TextLabel")
            upvalueLabel.Size = UDim2.new(0.5, -10, 0.3, 0)
            upvalueLabel.Position = UDim2.new(0, 10, 0.7, 0)
            upvalueLabel.BackgroundTransparency = 1
            upvalueLabel.TextColor3 = colors.textSecondary
            upvalueLabel.Text = "Upvalues: " .. self:countTable(closure.upvalues)
            upvalueLabel.Font = Enum.Font.Gotham
            upvalueLabel.TextSize = 11
            upvalueLabel.TextXAlignment = Enum.TextXAlignment.Left
            upvalueLabel.Parent = closureFrame
            
            local timeLabel = Instance.new("TextLabel")
            timeLabel.Size = UDim2.new(0.5, -10, 0.3, 0)
            timeLabel.Position = UDim2.new(0.5, 0, 0.7, 0)
            timeLabel.BackgroundTransparency = 1
            timeLabel.TextColor3 = colors.textSecondary
            timeLabel.Text = "Captured: " .. os.date("%H:%M:%S", closure.timestamp)
            timeLabel.Font = Enum.Font.Gotham
            timeLabel.TextSize = 11
            timeLabel.TextXAlignment = Enum.TextXAlignment.Right
            timeLabel.Parent = closureFrame
        end, 25)
    elseif tabName == "Upvalues" then
        self:createUpvalueView(content)
    elseif tabName == "Tables" then
        self:createPaginatedView(content, state.tables, function(scroll, id, tbl, index)
            local tableFrame = Instance.new("Frame")
            tableFrame.Size = UDim2.new(1, -20, 0, 60)
            tableFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
            tableFrame.BorderSizePixel = 0
            tableFrame.Parent = scroll
            
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, -20, 0.5, 0)
            nameLabel.Position = UDim2.new(0, 10, 0, 5)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextColor3 = colors.accent
            nameLabel.Text = tbl.name .. "  •  " .. id:sub(1, 8) .. "..."
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextSize = 14
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = tableFrame
            
            local sizeLabel = Instance.new("TextLabel")
            sizeLabel.Size = UDim2.new(0.5, -10, 0.5, 0)
            sizeLabel.Position = UDim2.new(0, 10, 0.5, 0)
            sizeLabel.BackgroundTransparency = 1
            sizeLabel.TextColor3 = colors.textSecondary
            sizeLabel.Text = "Size: " .. tbl.size .. " elements"
            sizeLabel.Font = Enum.Font.Gotham
            sizeLabel.TextSize = 11
            sizeLabel.TextXAlignment = Enum.TextXAlignment.Left
            sizeLabel.Parent = tableFrame
            
            local timeLabel = Instance.new("TextLabel")
            timeLabel.Size = UDim2.new(0.5, -10, 0.5, 0)
            timeLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
            timeLabel.BackgroundTransparency = 1
            timeLabel.TextColor3 = colors.textSecondary
            timeLabel.Text = "Created: " .. os.date("%H:%M:%S", tbl.timestamp)
            timeLabel.Font = Enum.Font.Gotham
            timeLabel.TextSize = 11
            timeLabel.TextXAlignment = Enum.TextXAlignment.Right
            timeLabel.Parent = tableFrame
        end, 25)
    elseif tabName == "Modules" then
        self:createModuleView(content)
    elseif tabName == "Metatables" then
        self:createMetatableView(content)
    elseif tabName == "Globals" then
        self:createGlobalsView(content)
    elseif tabName == "Constants" then
        self:createConstantsView(content)
    elseif tabName == "Diff" then
        self:createDiffView(content)
    elseif tabName == "Search" then
        self:createSearchView(content)
    end
end

function UniversalLuaStateViewer:createDiffView(parent)
    local controlBar = Instance.new("Frame")
    controlBar.Size = UDim2.new(1, 0, 0, 50)
    controlBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    controlBar.BorderSizePixel = 0
    controlBar.Parent = parent
    
    local snapshotButton = Instance.new("TextButton")
    snapshotButton.Size = UDim2.new(0.2, 0, 0.6, 0)
    snapshotButton.Position = UDim2.new(0.05, 0, 0.2, 0)
    snapshotButton.BackgroundColor3 = colors.accent
    snapshotButton.TextColor3 = colors.text
    snapshotButton.Text = "Take Snapshot"
    snapshotButton.Font = Enum.Font.GothamBold
    snapshotButton.TextSize = 12
    snapshotButton.Parent = controlBar
    
    local snapshotCount = Instance.new("TextLabel")
    snapshotCount.Size = UDim2.new(0.2, 0, 1, 0)
    snapshotCount.Position = UDim2.new(0.3, 0, 0, 0)
    snapshotCount.BackgroundTransparency = 1
    snapshotCount.TextColor3 = colors.text
    snapshotCount.Text = "Snapshots: " .. #state.snapshots
    snapshotCount.Font = Enum.Font.Gotham
    snapshotCount.TextSize = 12
    snapshotCount.Parent = controlBar
    
    local diffDisplay = Instance.new("ScrollingFrame")
    diffDisplay.Size = UDim2.new(1, -20, 1, -60)
    diffDisplay.Position = UDim2.new(0, 10, 0, 50)
    diffDisplay.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    diffDisplay.Parent = parent
    
    snapshotButton.MouseButton1Click:Connect(function()
        self:takeSnapshot("Manual_" .. os.time())
        snapshotCount.Text = "Snapshots: " .. #state.snapshots
        self:updateDiffDisplay(diffDisplay)
    end)
    
    self:updateDiffDisplay(diffDisplay)
end

function UniversalLuaStateViewer:updateDiffDisplay(display)
    for _, child in ipairs(display:GetChildren()) do
        child:Destroy()
    end
    
    if #state.snapshots < 2 then
        local noDiff = Instance.new("TextLabel")
        noDiff.Size = UDim2.new(1, 0, 1, 0)
        noDiff.BackgroundTransparency = 1
        noDiff.TextColor3 = colors.textSecondary
        noDiff.Text = "Take at least 2 snapshots to see differences"
        noDiff.Font = Enum.Font.Gotham
        noDiff.TextSize = 14
        noDiff.Parent = display
        return
    end
    
    local latest = state.snapshots[#state.snapshots]
    local previous = state.snapshots[#state.snapshots - 1]
    local diff = self:diffSnapshots(previous, latest)
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = display
    
    self:addDiffSection(display, "🆕 New Closures", diff.closures.added, colors.success)
    self:addDiffSection(display, "🗑️ Removed Closures", diff.closures.removed, colors.error)
    self:addDiffSection(display, "🆕 New Tables", diff.tables.added, colors.success)
    self:addDiffSection(display, "🗑️ Removed Tables", diff.tables.removed, colors.error)
    self:addDiffSection(display, "📦 New Modules", diff.modules.added, colors.success)
    self:addDiffSection(display, "📦 Removed Modules", diff.modules.removed, colors.error)
    
    display.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
end

function UniversalLuaStateViewer:addDiffSection(parent, title, data, color)
    if not next(data) then return end
    
    local section = Instance.new("Frame")
    section.Size = UDim2.new(1, 0, 0, 40)
    section.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
    section.BorderSizePixel = 0
    section.Parent = parent
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0.5, 0)
    titleLabel.Position = UDim2.new(0, 10, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = color
    titleLabel.Text = title .. " (" .. self:countTable(data) .. ")"
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = section
    
    local count = 0
    for id, item in pairs(data) do
        count = count + 1
        if count > 10 then break end
        
        local itemLabel = Instance.new("TextLabel")
        itemLabel.Size = UDim2.new(1, -20, 0, 20)
        itemLabel.Position = UDim2.new(0, 10, 0, 20 + (count * 20))
        itemLabel.BackgroundTransparency = 1
        itemLabel.TextColor3 = colors.text
        itemLabel.Text = "• " .. tostring(item.name or id)
        itemLabel.Font = Enum.Font.Gotham
        itemLabel.TextSize = 12
        itemLabel.TextXAlignment = Enum.TextXAlignment.Left
        itemLabel.Parent = section
        
        section.Size = UDim2.new(1, 0, 0, 40 + (count * 20))
    end
end

function UniversalLuaStateViewer:createSearchView(parent)
    local searchContainer = Instance.new("Frame")
    searchContainer.Size = UDim2.new(1, 0, 0, 60)
    searchContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    searchContainer.BorderSizePixel = 0
    searchContainer.Parent = parent
    
    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(0.8, 0, 0.5, 0)
    searchBox.Position = UDim2.new(0.1, 0, 0.25, 0)
    searchBox.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
    searchBox.TextColor3 = colors.text
    searchBox.PlaceholderText = "🔍 Search across all VM state..."
    searchBox.PlaceholderColor3 = colors.textSecondary
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 14
    searchBox.Parent = searchContainer
    
    local resultsFrame = Instance.new("ScrollingFrame")
    resultsFrame.Size = UDim2.new(1, -20, 1, -70)
    resultsFrame.Position = UDim2.new(0, 10, 0, 60)
    resultsFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    resultsFrame.Parent = parent
    
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        self:performSearch(searchBox.Text, resultsFrame)
    end)
end

-- =========================================
-- UTILITY FUNCTIONS
-- =========================================

function UniversalLuaStateViewer:makeDraggable(frame, handle)
    local dragging = false
    local dragInput, dragStart, startPos
    
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

function UniversalLuaStateViewer:toggleMinimize()
    if self.isMinimized then
        -- Restore
        self.mainContainer.Size = self.originalSize
        self.isMinimized = false
    else
        -- Minimize
        self.originalSize = self.mainContainer.Size
        self.mainContainer.Size = UDim2.new(0.3, 0, 0, 65)
        self.isMinimized = true
    end
end

function UniversalLuaStateViewer:diffSnapshots(snap1, snap2)
    local differences = {}
    
    differences.closures = self:compareClosures(snap1.closures, snap2.closures)
    differences.tables = self:compareTables(snap1.tables, snap2.tables)
    differences.modules = self:compareModules(snap1.modules, snap2.modules)
    differences.upvalues = self:compareUpvalues(snap1.upvalues, snap2.upvalues)
    differences.metatables = self:compareMetatables(snap1.metatables, snap2.metatables)
    differences.globals = self:compareGlobals(snap1.globals, snap2.globals)
    differences.constants = self:compareConstants(snap1.constants, snap2.constants)
    
    return differences
end

function UniversalLuaStateViewer:compareClosures(old, new)
    local diff = {added = {}, removed = {}, modified = {}}
    
    for id, closure in pairs(new) do
        if not old[id] then
            diff.added[id] = closure
        end
    end
    
    for id, closure in pairs(old) do
        if not new[id] then
            diff.removed[id] = closure
        end
    end
    
    return diff
end

function UniversalLuaStateViewer:compareTables(old, new)
    local diff = {added = {}, removed = {}, modified = {}}
    
    for id, tbl in pairs(new) do
        if not old[id] then
            diff.added[id] = tbl
        elseif tbl.size ~= old[id].size then
            diff.modified[id] = {old = old[id], new = tbl}
        end
    end
    
    for id, tbl in pairs(old) do
        if not new[id] then
            diff.removed[id] = tbl
        end
    end
    
    return diff
end

function UniversalLuaStateViewer:compareModules(old, new)
    local diff = {added = {}, removed = {}, modified = {}}
    
    for name, module in pairs(new) do
        if not old[name] then
            diff.added[name] = module
        end
    end
    
    for name, module in pairs(old) do
        if not new[name] then
            diff.removed[name] = module
        end
    end
    
    return diff
end

-- =========================================
-- PUBLIC API
-- =========================================

function UniversalLuaStateViewer:start()
    local success, err = pcall(function()
        self:installHooks()
        self:createGUI() -- AUTO-OPENS GUI!
        self:takeSnapshot("Initial")
        
        if self.statusText then
            self.statusText.Text = "Monitoring VM State - " .. os.date("%H:%M:%S")
        end
        
        print("Universal Lua State Viewer Started")
        print("GUI automatically opened in PlayerGui")
        print("Enhanced features: Circular ref prevention, Complete GUI tabs, Deep copy, Performance optimizations")
    end)
    
    if not success then
        warn("Failed to start Universal Lua State Viewer: " .. tostring(err))
    end
end

function UniversalLuaStateViewer:stop()
    self.enabled = false
    self:restoreHooks()
    
    if self.gui then
        self.gui:Destroy()
        self.gui = nil
    end
end

function UniversalLuaStateViewer:getData()
    return state
end

function UniversalLuaStateViewer:clearData()
    table.clear(state.closures)
    table.clear(state.upvalues)
    table.clear(state.tables)
    table.clear(state.modules)
    table.clear(state.metatables)
    table.clear(state.globals)
    table.clear(state.execution)
end

function UniversalLuaStateViewer:getStateSummary()
    return {
        closures = self:countTable(state.closures),
        upvalues = self:countTable(state.upvalues),
        tables = self:countTable(state.tables),
        modules = self:countTable(state.modules),
        metatables = self:countTable(state.metatables),
        snapshots = #state.snapshots,
        executionEvents = #state.execution
    }
end

-- =========================================
-- AUTO-START THE VIEWER WHEN SCRIPT LOADS
-- =========================================

-- Create and start the viewer immediately
local viewer = UniversalLuaStateViewer.new()
viewer:start()

-- Return the viewer instance for manual control
return viewer
