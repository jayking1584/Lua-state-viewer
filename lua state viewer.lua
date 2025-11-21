-- Universal Lua State Viewer for Roblox - Intrusive Edition
-- Uses metatable bypasses and aggressive hooking to capture everything

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

-- Store original functions
local originalFunctions = {
    loadstring = loadstring or load,
    setmetatable = setmetatable,
    require = require,
    getmetatable = getmetatable,
    setreadonly = setreadonly or function() end,
    isreadonly = isreadonly or function() return false end
}

-- Bypass protected metatables
local function bypassProtectedMetatable(tbl)
    local success, mt = pcall(getmetatable, tbl)
    if success and mt then
        -- Try to bypass protection
        local bypassed = false
        pcall(function()
            local raw_mt = debug.getmetatable(tbl)
            if raw_mt then
                setmetatable(tbl, nil)
                setmetatable(tbl, raw_mt)
                bypassed = true
            end
        end)
        return bypassed
    end
    return false
end

-- Aggressive table monitoring
local function createAggressiveMetatable(tableId, viewer)
    return {
        __newindex = function(t, key, value)
            viewer:recordTableChange(tableId, key, value, "set")
            rawset(t, key, value)
        end,
        __index = function(t, key)
            local val = rawget(t, key)
            viewer:recordTableChange(tableId, key, val, "get")
            return val
        end,
        __metatable = "Protected"
    }
end

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
-- AGGRESSIVE HOOKING SYSTEM
-- =========================================

function UniversalLuaStateViewer:installHooks()
    if self.enabled then return end
    
    print("Installing aggressive hooks...")
    
    -- Hook loadstring/load
    self:installClosureHook()
    
    -- Hook setmetatable aggressively
    self:installTableHook()
    
    -- Hook require
    self:installRequireHook()
    
    -- Install execution hook
    self:installExecutionHook()
    
    -- Install global hook
    self:installGlobalHook()
    
    -- Capture initial state aggressively
    self:captureInitialState()
    
    self.enabled = true
    print("Aggressive hooks installed successfully!")
end

function UniversalLuaStateViewer:installClosureHook()
    -- Hook loadstring
    loadstring = function(str, chunkname)
        local func, err = originalFunctions.loadstring(str, chunkname)
        if func then
            self:captureClosure(func, chunkname or "loadstring", str)
        end
        return func, err
    end
    
    -- Hook function environment access
    self:hookFunctionEnvironments()
end

function UniversalLuaStateViewer:hookFunctionEnvironments()
    -- Hook debug library to capture function environments
    local originalDebugGetInfo = debug.getinfo
    debug.getinfo = function(func, ...)
        local info = originalDebugGetInfo(func, ...)
        if info and info.func then
            self:captureClosure(info.func, info.name or "debug_getinfo", "debug")
        end
        return info
    end
end

function UniversalLuaStateViewer:installTableHook()
    -- Aggressive setmetatable hook
    setmetatable = function(t, mt)
        if type(t) == "table" then
            -- Capture table before setting metatable
            self:captureTable(t, "table_with_metatable")
            
            -- Try to bypass protection
            bypassProtectedMetatable(t)
            
            -- Set monitoring metatable
            local tableId = tostring(t)
            local success = pcall(function()
                local monitoringMt = createAggressiveMetatable(tableId, self)
                if mt then
                    -- Combine with existing metatable
                    setmetatable(t, monitoringMt)
                    self:captureMetatable(mt, t)
                else
                    setmetatable(t, monitoringMt)
                end
            end)
            
            if not success then
                -- Fallback: just use original
                return originalFunctions.setmetatable(t, mt)
            end
        end
        return originalFunctions.setmetatable(t, mt)
    end
end

function UniversalLuaStateViewer:installRequireHook()
    require = function(module)
        local success, result = pcall(originalFunctions.require, module)
        
        state.modules[module] = {
            name = module,
            result = result,
            success = success,
            timestamp = tick(),
            type = type(result)
        }
        
        if success and type(result) == "table" then
            self:captureTable(result, "module_" .. module)
            
            -- Also capture all functions in the module
            for k, v in pairs(result) do
                if type(v) == "function" then
                    self:captureClosure(v, k, "module_function")
                elseif type(v) == "table" then
                    self:captureTable(v, "module_subtable_" .. k)
                end
            end
        end
        
        return result
    end
end

function UniversalLuaStateViewer:installExecutionHook()
    -- Install very aggressive execution hook
    debug.sethook(function(event, line)
        if event == "call" then
            self:recordFunctionCall(2)
        elseif event == "return" then
            self:recordFunctionReturn(2)
        elseif event == "line" then
            self:recordLineExecution(line)
        end
    end, "crl", 0)
end

function UniversalLuaStateViewer:installGlobalHook()
    -- Aggressively monitor _G
    self:monitorGlobalEnvironment()
    
    -- Also hook global assignments
    self:hookGlobalAssignments()
end

function UniversalLuaStateViewer:hookGlobalAssignments()
    -- Create a wrapper for _G
    local globalEnv = getfenv and getfenv(2) or _G
    local globalMeta = getmetatable(globalEnv) or {}
    local originalNewIndex = globalMeta.__newindex
    
    globalMeta.__newindex = function(t, k, v)
        self:recordGlobalChange(k, v, "assignment")
        if originalNewIndex then
            originalNewIndex(t, k, v)
        else
            rawset(t, k, v)
        end
    end
    
    -- Try to set the metatable aggressively
    pcall(function()
        setmetatable(globalEnv, globalMeta)
    end)
end

function UniversalLuaStateViewer:monitorGlobalEnvironment()
    local globalEnv = getfenv and getfenv(2) or _G
    self:captureTable(globalEnv, "_G")
    
    -- Monitor all existing globals
    for k, v in pairs(globalEnv) do
        if type(v) == "function" then
            self:captureClosure(v, k, "global_function")
        elseif type(v) == "table" then
            self:captureTable(v, "global_table_" .. k)
        end
    end
end

function UniversalLuaStateViewer:captureInitialState()
    print("Capturing initial VM state...")
    
    -- Capture all loaded modules
    self:captureLoadedModules()
    
    -- Capture all existing functions in environment
    self:captureExistingFunctions()
    
    -- Capture all known tables
    self:captureKnownTables()
end

function UniversalLuaStateViewer:captureLoadedModules()
    -- Try to find and capture already loaded modules
    local globalEnv = getfenv and getfenv(2) or _G
    for k, v in pairs(globalEnv) do
        if type(v) == "table" and string.find(k:lower(), "module") then
            state.modules[k] = {
                name = k,
                result = v,
                success = true,
                timestamp = tick(),
                type = "table"
            }
            self:captureTable(v, "preloaded_module_" .. k)
        end
    end
end

function UniversalLuaStateViewer:captureExistingFunctions()
    -- Use debug.getregistry to find functions
    local success, registry = pcall(function()
        return debug.getregistry()
    end)
    
    if success and type(registry) == "table" then
        for k, v in pairs(registry) do
            if type(v) == "function" then
                self:captureClosure(v, "registry_function_" .. tostring(k), "debug_registry")
            end
        end
    end
end

function UniversalLuaStateViewer:captureKnownTables()
    -- Capture common Roblox tables
    local importantTables = {
        "workspace", "game", "script", "shared", 
        "ReplicatedStorage", "ServerScriptService", "ServerStorage",
        "Players", "Lighting", "SoundService"
    }
    
    for _, name in ipairs(importantTables) do
        local success, value = pcall(function()
            return game:GetService(name)
        end)
        if success and value then
            self:captureTable(value, "service_" .. name)
        end
    end
end

-- =========================================
-- AGGRESSIVE CAPTURE FUNCTIONS
-- =========================================

function UniversalLuaStateViewer:captureClosure(func, name, source)
    local closureId = tostring(func):gsub("function: ", "")
    
    if not state.closures[closureId] then
        print("Capturing closure:", name, closureId)
        
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
        self:captureEnvironment(func, closureId)
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
        elseif type(value) == "function" then
            self:captureClosure(value, name .. "_upvalue_func", "upvalue")
        end
    end
    
    state.closures[closureId].upvalues = upvalueInfo
    state.upvalues[closureId] = upvalueInfo
end

function UniversalLuaStateViewer:captureEnvironment(func, closureId)
    local success, env = pcall(getfenv, func)
    if success and env then
        state.closures[closureId].environment = {
            type = type(env),
            value = tostring(env)
        }
        self:captureTable(env, "env_" .. closureId)
    end
end

function UniversalLuaStateViewer:captureTable(tbl, name, visited, depth)
    visited = visited or {}
    depth = depth or 1
    
    -- Prevent circular references
    if visited[tbl] then
        return visited[tbl].id
    end
    
    -- Depth limit
    if depth > 5 then
        return "depth_limit"
    end
    
    local tableId = tostring(tbl)
    
    if not state.tables[tableId] then
        print("Capturing table:", name, tableId)
        
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
        
        -- Try to capture metatable aggressively
        pcall(function()
            local mt = getmetatable(tbl)
            if mt then
                self:captureMetatable(mt, tbl)
            end
        end)
    end
    
    return tableId
end

function UniversalLuaStateViewer:captureTableContents(tbl, tableId, visited, depth)
    local elements = {}
    local count = 0
    
    -- Use aggressive iteration
    for k, v in pairs(tbl) do
        count = count + 1
        local keyStr = tostring(k)
        elements[keyStr] = {
            key = k,
            value = v,
            keyType = type(k),
            valueType = type(v),
            captured = false
        }
        
        -- Recursively capture
        if type(v) == "table" then
            elements[keyStr].captured = true
            self:captureTable(v, "nested_" .. tableId, visited, depth + 1)
        elseif type(v) == "function" then
            self:captureClosure(v, "table_func_" .. keyStr, "table_element")
        end
    end
    
    state.tables[tableId].elements = elements
    state.tables[tableId].size = count
end

function UniversalLuaStateViewer:captureMetatable(mt, originalTable)
    local mtId = tostring(mt)
    
    state.metatables[mtId] = {
        id = mtId,
        attachedTo = tostring(originalTable),
        methods = {},
        timestamp = tick()
    }
    
    -- Aggressively capture metamethods
    for method, func in pairs(mt) do
        if type(func) == "function" then
            state.metatables[mtId].methods[method] = {
                name = method,
                closureId = self:captureClosure(func, method .. "_metamethod", "metatable")
            }
        end
    end
end

-- =========================================
-- EXECUTION TRACING
-- =========================================

function UniversalLuaStateViewer:recordFunctionCall(level)
    local info = debug.getinfo(level, "nS")
    if info then
        local call = {
            type = "call",
            name = info.name or "anonymous",
            source = info.source,
            linedefined = info.linedefined,
            timestamp = tick(),
            stack = self:getStackTrace()
        }
        table.insert(state.execution, call)
        
        -- Capture the function if it's new
        if info.func then
            self:captureClosure(info.func, info.name or "call_capture", "execution_trace")
        end
    end
end

function UniversalLuaStateViewer:recordFunctionReturn(level)
    local info = debug.getinfo(level, "nS")
    if info then
        local returnRecord = {
            type = "return",
            name = info.name or "anonymous",
            source = info.source,
            timestamp = tick(),
            stack = self:getStackTrace()
        }
        table.insert(state.execution, returnRecord)
    end
end

function UniversalLuaStateViewer:recordLineExecution(line)
    local executionRecord = {
        type = "line",
        line = line,
        timestamp = tick(),
        stack = self:getStackTrace()
    }
    table.insert(state.execution, executionRecord)
end

function UniversalLuaStateViewer:recordTableChange(tableId, key, value, operation)
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

function UniversalLuaStateViewer:recordGlobalChange(key, value, operation)
    local change = {
        type = "global",
        key = key,
        value = value,
        operation = operation,
        timestamp = tick(),
        stack = self:getStackTrace()
    }
    table.insert(state.execution, change)
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
    for i = 3, 15 do
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
-- SNAPSHOT SYSTEM
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
-- GUI CREATION (Auto-Open)
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
    title.Text = "Universal Lua State Viewer - INTRUSIVE MODE"
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
    
    local refreshBtn = self:createControlButton("↻", controlFrame, 1, function()
        self:refreshCapture()
    end)
    
    local closeBtn = self:createControlButton("×", controlFrame, 2, function()
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
    statusText.TextColor3 = colors.success
    statusText.Text = "INTRUSIVE MODE - Aggressively capturing VM state"
    statusText.Font = Enum.Font.Gotham
    statusText.TextSize = 12
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.Parent = statusBar
    
    -- Stats Bar
    local statsBar = Instance.new("Frame")
    statsBar.Size = UDim2.new(1, 0, 0, 25)
    statsBar.Position = UDim2.new(0, 0, 0, 65)
    statsBar.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    statsBar.BorderSizePixel = 0
    statsBar.Parent = mainContainer
    
    local statsText = Instance.new("TextLabel")
    statsText.Size = UDim2.new(1, -20, 1, 0)
    statsText.Position = UDim2.new(0, 10, 0, 0)
    statsText.BackgroundTransparency = 1
    statsText.TextColor3 = colors.textSecondary
    statsText.Text = "Closures: 0 | Tables: 0 | Modules: 0 | Executions: 0"
    statsText.Font = Enum.Font.Gotham
    statsText.TextSize = 11
    statsText.TextXAlignment = Enum.TextXAlignment.Left
    statsText.Parent = statsBar
    
    -- Main Content Area
    local contentArea = Instance.new("Frame")
    contentArea.Size = UDim2.new(1, 0, 1, -90)
    contentArea.Position = UDim2.new(0, 0, 0, 90)
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
    self.statsText = statsText
    self.originalSize = mainContainer.Size
    self.originalPosition = mainContainer.Position
    
    -- Start stats update loop
    self:startStatsUpdate()
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
        {"Dashboard", "📊", "VM State Overview"},
        {"Closures", "📋", "All captured functions"},
        {"Tables", "🗂️", "Table mutations"},
        {"Modules", "📦", "Require calls"},
        {"Execution", "⚡", "Function calls & returns"},
        {"Search", "🔍", "Search everything"}
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
    
    -- Show dashboard by default
    self:showTabContent("Dashboard", contentFrame)
end

function UniversalLuaStateViewer:showTabContent(tabName, contentFrame)
    for _, child in ipairs(contentFrame:GetChildren()) do
        child:Destroy()
    end
    
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
    
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 1, -40)
    content.Position = UDim2.new(0, 0, 0, 40)
    content.BackgroundTransparency = 1
    content.Parent = contentFrame
    
    if tabName == "Dashboard" then
        self:createDashboardView(content)
    elseif tabName == "Closures" then
        self:createClosuresView(content)
    elseif tabName == "Tables" then
        self:createTablesView(content)
    elseif tabName == "Modules" then
        self:createModulesView(content)
    elseif tabName == "Execution" then
        self:createExecutionView(content)
    elseif tabName == "Search" then
        self:createSearchView(content)
    end
end

function UniversalLuaStateViewer:createDashboardView(parent)
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.Parent = parent
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    -- Summary Cards
    local cards = {
        {title = "Closures", count = self:countTable(state.closures), color = colors.success, icon = "📋"},
        {title = "Tables", count = self:countTable(state.tables), color = colors.accent, icon = "🗂️"},
        {title = "Modules", count = self:countTable(state.modules), color = colors.warning, icon = "📦"},
        {title = "Executions", count = #state.execution, color = colors.error, icon = "⚡"},
        {title = "Upvalues", count = self:countTable(state.upvalues), color = colors.success, icon = "🔗"},
        {title = "Metatables", count = self:countTable(state.metatables), color = colors.accent, icon = "⚙️"}
    }
    
    for i, card in ipairs(cards) do
        local cardFrame = Instance.new("Frame")
        cardFrame.Size = UDim2.new(0.45, 0, 0, 80)
        cardFrame.Position = UDim2.new((i-1) % 2 * 0.5, 10, math.floor((i-1)/2) * 0.25, 10)
        cardFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
        cardFrame.BorderSizePixel = 0
        cardFrame.Parent = scroll
        
        local iconLabel = Instance.new("TextLabel")
        iconLabel.Size = UDim2.new(0.2, 0, 1, 0)
        iconLabel.BackgroundTransparency = 1
        iconLabel.TextColor3 = card.color
        iconLabel.Text = card.icon
        iconLabel.Font = Enum.Font.Gotham
        iconLabel.TextSize = 24
        iconLabel.Parent = cardFrame
        
        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(0.8, 0, 0.5, 0)
        titleLabel.Position = UDim2.new(0.2, 0, 0, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.TextColor3 = colors.text
        titleLabel.Text = card.title
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextSize = 16
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Parent = cardFrame
        
        local countLabel = Instance.new("TextLabel")
        countLabel.Size = UDim2.new(0.8, 0, 0.5, 0)
        countLabel.Position = UDim2.new(0.2, 0, 0.5, 0)
        countLabel.BackgroundTransparency = 1
        countLabel.TextColor3 = card.color
        countLabel.Text = tostring(card.count)
        countLabel.Font = Enum.Font.GothamBold
        countLabel.TextSize = 20
        countLabel.TextXAlignment = Enum.TextXAlignment.Left
        countLabel.Parent = cardFrame
    end
    
    -- Recent Activity
    local activityFrame = Instance.new("Frame")
    activityFrame.Size = UDim2.new(1, -20, 0, 200)
    activityFrame.Position = UDim2.new(0, 10, 0, 250)
    activityFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
    activityFrame.BorderSizePixel = 0
    activityFrame.Parent = scroll
    
    local activityTitle = Instance.new("TextLabel")
    activityTitle.Size = UDim2.new(1, 0, 0, 30)
    activityTitle.BackgroundTransparency = 1
    activityTitle.TextColor3 = colors.text
    activityTitle.Text = "Recent Activity"
    activityTitle.Font = Enum.Font.GothamBold
    activityTitle.TextSize = 16
    activityTitle.Parent = activityFrame
    
    local activityScroll = Instance.new("ScrollingFrame")
    activityScroll.Size = UDim2.new(1, -10, 1, -40)
    activityScroll.Position = UDim2.new(0, 5, 0, 35)
    activityScroll.BackgroundTransparency = 1
    activityScroll.ScrollBarThickness = 4
    activityScroll.Parent = activityFrame
    
    local activityLayout = Instance.new("UIListLayout")
    activityLayout.Parent = activityScroll
    
    -- Show recent executions
    for i = math.max(1, #state.execution - 10), #state.execution do
        local exec = state.execution[i]
        if exec then
            local execFrame = Instance.new("Frame")
            execFrame.Size = UDim2.new(1, 0, 0, 25)
            execFrame.BackgroundTransparency = 1
            execFrame.Parent = activityScroll
            
            local typeLabel = Instance.new("TextLabel")
            typeLabel.Size = UDim2.new(0.2, 0, 1, 0)
            typeLabel.BackgroundTransparency = 1
            typeLabel.TextColor3 = colors.accent
            typeLabel.Text = exec.type
            typeLabel.Font = Enum.Font.Gotham
            typeLabel.TextSize = 12
            typeLabel.TextXAlignment = Enum.TextXAlignment.Left
            typeLabel.Parent = execFrame
            
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
            nameLabel.Position = UDim2.new(0.2, 0, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextColor3 = colors.text
            nameLabel.Text = exec.name or "anonymous"
            nameLabel.Font = Enum.Font.Gotham
            nameLabel.TextSize = 12
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = execFrame
            
            local timeLabel = Instance.new("TextLabel")
            timeLabel.Size = UDim2.new(0.2, 0, 1, 0)
            timeLabel.Position = UDim2.new(0.8, 0, 0, 0)
            timeLabel.BackgroundTransparency = 1
            timeLabel.TextColor3 = colors.textSecondary
            timeLabel.Text = os.date("%H:%M:%S", exec.timestamp)
            timeLabel.Font = Enum.Font.Gotham
            timeLabel.TextSize = 10
            timeLabel.TextXAlignment = Enum.TextXAlignment.Right
            timeLabel.Parent = execFrame
        end
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, 500)
end

function UniversalLuaStateViewer:createClosuresView(parent)
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.Parent = parent
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    local count = 0
    for id, closure in pairs(state.closures) do
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
        nameLabel.Text = closure.name .. "  •  " .. id:sub(1, 12) .. "..."
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
        
        count = count + 1
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 85)
end

function UniversalLuaStateViewer:createTablesView(parent)
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.Parent = parent
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    local count = 0
    for id, tbl in pairs(state.tables) do
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
        nameLabel.Text = tbl.name .. "  •  " .. id:sub(1, 12) .. "..."
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
        
        count = count + 1
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 65)
end

function UniversalLuaStateViewer:createModulesView(parent)
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
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

function UniversalLuaStateViewer:createExecutionView(parent)
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 8
    scroll.Parent = parent
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = scroll
    
    for i, exec in ipairs(state.execution) do
        local execFrame = Instance.new("Frame")
        execFrame.Size = UDim2.new(1, -20, 0, 40)
        execFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
        execFrame.BorderSizePixel = 0
        execFrame.Parent = scroll
        
        local typeLabel = Instance.new("TextLabel")
        typeLabel.Size = UDim2.new(0.15, 0, 1, 0)
        typeLabel.BackgroundTransparency = 1
        typeLabel.TextColor3 = colors.accent
        typeLabel.Text = exec.type
        typeLabel.Font = Enum.Font.GothamBold
        typeLabel.TextSize = 12
        typeLabel.TextXAlignment = Enum.TextXAlignment.Left
        typeLabel.Parent = execFrame
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
        nameLabel.Position = UDim2.new(0.15, 0, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = colors.text
        nameLabel.Text = exec.name or "anonymous"
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextSize = 12
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = execFrame
        
        local timeLabel = Instance.new("TextLabel")
        timeLabel.Size = UDim2.new(0.25, 0, 1, 0)
        timeLabel.Position = UDim2.new(0.75, 0, 0, 0)
        timeLabel.BackgroundTransparency = 1
        timeLabel.TextColor3 = colors.textSecondary
        timeLabel.Text = os.date("%H:%M:%S", exec.timestamp)
        timeLabel.Font = Enum.Font.Gotham
        timeLabel.TextSize = 10
        timeLabel.TextXAlignment = Enum.TextXAlignment.Right
        timeLabel.Parent = execFrame
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, #state.execution * 45)
end

function UniversalLuaStateViewer:createSearchView(parent)
    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(0.8, 0, 0, 40)
    searchBox.Position = UDim2.new(0.1, 0, 0, 10)
    searchBox.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
    searchBox.TextColor3 = colors.text
    searchBox.PlaceholderText = "🔍 Search closures, tables, modules..."
    searchBox.PlaceholderColor3 = colors.textSecondary
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 14
    searchBox.Parent = parent
    
    local resultsFrame = Instance.new("ScrollingFrame")
    resultsFrame.Size = UDim2.new(1, -20, 1, -60)
    resultsFrame.Position = UDim2.new(0, 10, 0, 50)
    resultsFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    resultsFrame.Parent = parent
    
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        for _, child in ipairs(resultsFrame:GetChildren()) do
            child:Destroy()
        end
        
        local query = searchBox.Text:lower()
        if query == "" then return end
        
        local results = {}
        
        -- Search closures
        for id, closure in pairs(state.closures) do
            if string.find(closure.name:lower(), query) or string.find(tostring(closure.source):lower(), query) then
                table.insert(results, {type = "Closure", name = closure.name, id = id})
            end
        end
        
        -- Search tables
        for id, tbl in pairs(state.tables) do
            if string.find(tbl.name:lower(), query) then
                table.insert(results, {type = "Table", name = tbl.name, id = id})
            end
        end
        
        -- Search modules
        for name, module in pairs(state.modules) do
            if string.find(name:lower(), query) then
                table.insert(results, {type = "Module", name = name, id = name})
            end
        end
        
        -- Display results
        for i, result in ipairs(results) do
            local resultFrame = Instance.new("Frame")
            resultFrame.Size = UDim2.new(1, 0, 0, 40)
            resultFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
            resultFrame.BorderSizePixel = 0
            resultFrame.Parent = resultsFrame
            
            local typeLabel = Instance.new("TextLabel")
            typeLabel.Size = UDim2.new(0.2, 0, 1, 0)
            typeLabel.BackgroundTransparency = 1
            typeLabel.TextColor3 = colors.accent
            typeLabel.Text = result.type
            typeLabel.Font = Enum.Font.GothamBold
            typeLabel.TextSize = 12
            typeLabel.TextXAlignment = Enum.TextXAlignment.Left
            typeLabel.Parent = resultFrame
            
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(0.8, 0, 1, 0)
            nameLabel.Position = UDim2.new(0.2, 0, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextColor3 = colors.text
            nameLabel.Text = result.name
            nameLabel.Font = Enum.Font.Gotham
            nameLabel.TextSize = 14
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = resultFrame
        end
        
        resultsFrame.CanvasSize = UDim2.new(0, 0, 0, #results * 45)
    end)
end

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
        self.mainContainer.Size = self.originalSize
        self.isMinimized = false
    else
        self.originalSize = self.mainContainer.Size
        self.mainContainer.Size = UDim2.new(0.3, 0, 0, 90)
        self.isMinimized = true
    end
end

function UniversalLuaStateViewer:refreshCapture()
    print("Refreshing capture...")
    self:captureInitialState()
    self:updateStats()
end

function UniversalLuaStateViewer:startStatsUpdate()
    spawn(function()
        while self.enabled and self.statsText do
            self:updateStats()
            wait(2) -- Update every 2 seconds
        end
    end)
end

function UniversalLuaStateViewer:updateStats()
    if self.statsText then
        self.statsText.Text = string.format(
            "Closures: %d | Tables: %d | Modules: %d | Executions: %d | Upvalues: %d | Metatables: %d",
            self:countTable(state.closures),
            self:countTable(state.tables),
            self:countTable(state.modules),
            #state.execution,
            self:countTable(state.upvalues),
            self:countTable(state.metatables)
        )
    end
end

-- =========================================
-- PUBLIC API
-- =========================================

function UniversalLuaStateViewer:start()
    print("Starting Universal Lua State Viewer - INTRUSIVE MODE")
    self:installHooks()
    self:createGUI()
    self:takeSnapshot("Initial")
    
    print("Intrusive mode activated!")
    print("Capturing: ALL closures, tables, modules, executions, metatables")
end

function UniversalLuaStateViewer:stop()
    self.enabled = false
    
    -- Restore original functions
    if originalFunctions.loadstring then
        loadstring = originalFunctions.loadstring
    end
    if originalFunctions.setmetatable then
        setmetatable = originalFunctions.setmetatable
    end
    if originalFunctions.require then
        require = originalFunctions.require
    end
    
    if self.gui then
        self.gui:Destroy()
        self.gui = nil
    end
    
    print("Universal Lua State Viewer stopped")
end

function UniversalLuaStateViewer:getData()
    return state
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
-- AUTO-START
-- =========================================

local viewer = UniversalLuaStateViewer.new()
viewer:start()

return viewer
