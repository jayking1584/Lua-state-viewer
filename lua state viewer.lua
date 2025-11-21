-- Universal Lua State Viewer for Roblox
-- Captures: Closures, Upvalues, Tables, Modules, Metatables, Globals, Execution Flow, and more

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

-- Hook Management
local hooks = {
    closure = nil,
    upvalue = nil,
    table = nil,
    require = nil,
    execution = nil
}

function UniversalLuaStateViewer.new()
    local self = setmetatable({}, UniversalLuaStateViewer)
    self.enabled = false
    self.gui = nil
    return self
end

-- Core Hooking System
function UniversalLuaStateViewer:installHooks()
    if self.enabled then return end
    
    self:installClosureHook()
    self:installUpvalueHook()
    self:installTableHook()
    self:installRequireHook()
    self:installExecutionHook()
    self:installGlobalHook()
    
    self.enabled = true
end

function UniversalLuaStateViewer:installClosureHook()
    -- Hook function creation by overriding loadstring and similar functions
    local originalLoadstring = loadstring or load
    if originalLoadstring then
        loadstring = function(str, chunkname)
            local func = originalLoadstring(str, chunkname)
            if func then
                self:captureClosure(func, chunkname or "loadstring", str)
            end
            return func
        end
    end
    
    -- Hook function definitions by setting metatable on _G
    self:hookFunctionDefinitions()
end

function UniversalLuaStateViewer:hookFunctionDefinitions()
    local originalG = getfenv and getfenv(2) or _G
    local meta = getmetatable(originalG) or {}
    local originalIndex = meta.__index or function(t, k) return rawget(t, k) end
    
    meta.__index = function(t, k)
        local value = originalIndex(t, k)
        if type(value) == "function" then
            self:captureClosure(value, k, "global_function")
        end
        return value
    end
    
    setmetatable(originalG, meta)
end

function UniversalLuaStateViewer:captureClosure(func, name, source)
    local closureId = tostring(func):gsub("function: ", "")
    
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
    
    -- Capture upvalues
    self:captureUpvalues(func, closureId)
    
    return closureId
end

function UniversalLuaStateViewer:installUpvalueHook()
    -- Upvalue monitoring happens during closure capture
    -- Additional runtime upvalue tracking can be added here
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
        
        -- Recursively capture table upvalues
        if type(value) == "table" then
            self:captureTable(value, name .. "_upvalue")
        end
    end
    
    state.closures[closureId].upvalues = upvalueInfo
    state.upvalues[closureId] = upvalueInfo
end

function UniversalLuaStateViewer:installTableHook()
    local originalSetMetatable = setmetatable
    setmetatable = function(t, mt)
        if type(t) == "table" then
            self:captureTable(t, "table_with_metatable")
            if mt then
                self:captureMetatable(mt, t)
            end
        end
        return originalSetMetatable(t, mt)
    end
end

function UniversalLuaStateViewer:captureTable(tbl, name)
    local tableId = tostring(tbl)
    
    if not state.tables[tableId] then
        state.tables[tableId] = {
            id = tableId,
            name = name or "anonymous_table",
            elements = {},
            metatable = nil,
            size = 0,
            timestamp = tick()
        }
        
        -- Capture initial contents
        self:captureTableContents(tbl, tableId)
        
        -- Set up metatable for monitoring changes
        self:monitorTableChanges(tbl, tableId)
    end
    
    return tableId
end

function UniversalLuaStateViewer:captureTableContents(tbl, tableId)
    local elements = {}
    local count = 0
    
    for k, v in pairs(tbl) do
        count = count + 1
        elements[tostring(k)] = {
            key = k,
            value = v,
            keyType = type(k),
            valueType = type(v)
        }
        
        -- Recursively capture nested tables
        if type(v) == "table" then
            self:captureTable(v, "nested_table_" .. tableId)
        end
    end
    
    state.tables[tableId].elements = elements
    state.tables[tableId].size = count
end

function UniversalLuaStateViewer:monitorTableChanges(tbl, tableId)
    local originalMeta = getmetatable(tbl) or {}
    local newMeta = {
        __newindex = function(t, key, value)
            -- Capture the change
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
    local originalRequire = require
    require = function(module)
        local success, result = pcall(originalRequire, module)
        
        state.modules[module] = {
            name = module,
            result = result,
            success = success,
            timestamp = tick(),
            type = type(result)
        }
        
        -- Capture the module's table if it's a table
        if success and type(result) == "table" then
            self:captureTable(result, "module_" .. module)
        end
        
        return result
    end
end

function UniversalLuaStateViewer:installExecutionHook()
    -- Hook function calls and returns
    debug.sethook(function(event, line)
        if event == "call" then
            self:recordFunctionCall(2) -- Skip hook frame
        elseif event == "return" then
            self:recordFunctionReturn(2)
        end
    end, "cr", 0)
end

function UniversalLuaStateViewer:recordFunctionCall(level)
    local info = debug.getinfo(level, "nS")
    if info then
        local call = {
            type = "call",
            name = info.name or "anonymous",
            source = info.source,
            linedefined = info.linedefined,
            timestamp = tick()
        }
        table.insert(state.execution, call)
    end
end

function UniversalLuaStateViewer:recordFunctionReturn(level)
    local info = debug.getinfo(level, "nS")
    if info then
        local returnRecord = {
            type = "return",
            name = info.name or "anonymous",
            source = info.source,
            timestamp = tick()
        }
        table.insert(state.execution, returnRecord)
    end
end

function UniversalLuaStateViewer:installGlobalHook()
    -- Monitor _G changes
    self:monitorGlobalEnvironment()
end

function UniversalLuaStateViewer:monitorGlobalEnvironment()
    local env = getfenv and getfenv(2) or _G
    self:captureTable(env, "_G")
end

-- Analysis Functions
function UniversalLuaStateViewer:getPrototypeInfo(func)
    -- Extract prototype information from function
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
    -- Extract constants from function bytecode (limited in Roblox)
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
    for i = 3, 10 do -- Limit depth
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

function UniversalLuaStateViewer:captureMetatable(mt, originalTable)
    local mtId = tostring(mt)
    
    state.metatables[mtId] = {
        id = mtId,
        attachedTo = tostring(originalTable),
        methods = {},
        timestamp = tick()
    }
    
    -- Capture metamethods
    for method, func in pairs(mt) do
        if type(func) == "function" then
            state.metatables[mtId].methods[method] = {
                name = method,
                closureId = self:captureClosure(func, method .. "_metamethod")
            }
        end
    end
end

-- Snapshot System
function UniversalLuaStateViewer:takeSnapshot(name)
    local snapshot = {
        name = name or "Snapshot_" .. state.currentSnapshot,
        timestamp = tick(),
        closures = table.clone(state.closures),
        upvalues = table.clone(state.upvalues),
        tables = table.clone(state.tables),
        modules = table.clone(state.modules),
        metatables = table.clone(state.metatables),
        globals = table.clone(state.globals),
        execution = table.clone(state.execution)
    }
    
    state.snapshots[state.currentSnapshot] = snapshot
    state.currentSnapshot = state.currentSnapshot + 1
    
    return #state.snapshots
end

function UniversalLuaStateViewer:diffSnapshots(snap1, snap2)
    local differences = {}
    
    -- Compare closures
    differences.closures = self:compareClosures(snap1.closures, snap2.closures)
    differences.tables = self:compareTables(snap1.tables, snap2.tables)
    differences.modules = self:compareModules(snap1.modules, snap2.modules)
    
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

-- GUI Creation
function UniversalLuaStateViewer:createGUI()
    if self.gui then self.gui:Destroy() end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "UniversalLuaStateViewer"
    screenGui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0.9, 0, 0.9, 0)
    mainFrame.Position = UDim2.new(0.05, 0, 0.05, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0.05, 0)
    title.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Text = "Universal Lua State Viewer"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = mainFrame
    
    -- Tab System
    local tabContainer = Instance.new("Frame")
    tabContainer.Size = UDim2.new(1, 0, 0.95, 0)
    tabContainer.Position = UDim2.new(0, 0, 0.05, 0)
    tabContainer.BackgroundTransparency = 1
    tabContainer.Parent = mainFrame
    
    self:createTabs(tabContainer)
    self.gui = screenGui
end

function UniversalLuaStateViewer:createTabs(container)
    local tabs = {
        "Closures", "Upvalues", "Tables", "Modules", 
        "Metatables", "Globals", "Constants", "Diff", "Search"
    }
    
    local tabButtons = Instance.new("Frame")
    tabButtons.Size = UDim2.new(1, 0, 0.08, 0)
    tabButtons.BackgroundTransparency = 1
    tabButtons.Parent = container
    
    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, 0, 0.92, 0)
    contentFrame.Position = UDim2.new(0, 0, 0.08, 0)
    contentFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    contentFrame.Parent = container
    
    for i, tabName in ipairs(tabs) do
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1 / #tabs, 0, 1, 0)
        button.Position = UDim2.new((i-1) / #tabs, 0, 0, 0)
        button.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.Text = tabName
        button.Font = Enum.Font.Gotham
        button.TextSize = 14
        button.Parent = tabButtons
        
        button.MouseButton1Click:Connect(function()
            self:showTabContent(tabName, contentFrame)
        end)
    end
    
    -- Show first tab by default
    self:showTabContent("Closures", contentFrame)
end

function UniversalLuaStateViewer:showTabContent(tabName, contentFrame)
    -- Clear existing content
    for _, child in ipairs(contentFrame:GetChildren()) do
        child:Destroy()
    end
    
    if tabName == "Closures" then
        self:createClosureView(contentFrame)
    elseif tabName == "Tables" then
        self:createTableView(contentFrame)
    elseif tabName == "Diff" then
        self:createDiffView(contentFrame)
    elseif tabName == "Search" then
        self:createSearchView(contentFrame)
    end
end

function UniversalLuaStateViewer:createClosureView(parent)
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
        closureFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        closureFrame.BorderSizePixel = 0
        closureFrame.Parent = scroll
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0.3, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.Text = closure.name .. " (" .. id .. ")"
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = closureFrame
        
        local sourceLabel = Instance.new("TextLabel")
        sourceLabel.Size = UDim2.new(1, 0, 0.3, 0)
        sourceLabel.Position = UDim2.new(0, 0, 0.3, 0)
        sourceLabel.BackgroundTransparency = 1
        sourceLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        sourceLabel.Text = "Source: " .. tostring(closure.source)
        sourceLabel.TextXAlignment = Enum.TextXAlignment.Left
        sourceLabel.Parent = closureFrame
        
        local upvalueLabel = Instance.new("TextLabel")
        upvalueLabel.Size = UDim2.new(1, 0, 0.4, 0)
        upvalueLabel.Position = UDim2.new(0, 0, 0.6, 0)
        upvalueLabel.BackgroundTransparency = 1
        upvalueLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
        upvalueLabel.Text = "Upvalues: " .. tostring(#closure.upvalues)
        upvalueLabel.TextXAlignment = Enum.TextXAlignment.Left
        upvalueLabel.Parent = closureFrame
        
        count = count + 1
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 85)
end

function UniversalLuaStateViewer:createTableView(parent)
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
        tableFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        tableFrame.BorderSizePixel = 0
        tableFrame.Parent = scroll
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.Text = tbl.name .. " (" .. id .. ")"
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = tableFrame
        
        local sizeLabel = Instance.new("TextLabel")
        sizeLabel.Size = UDim2.new(1, 0, 0.5, 0)
        sizeLabel.Position = UDim2.new(0, 0, 0.5, 0)
        sizeLabel.BackgroundTransparency = 1
        sizeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        sizeLabel.Text = "Size: " .. tbl.size .. " elements"
        sizeLabel.TextXAlignment = Enum.TextXAlignment.Left
        sizeLabel.Parent = tableFrame
        
        count = count + 1
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, count * 65)
end

function UniversalLuaStateViewer:createDiffView(parent)
    local snapshotButton = Instance.new("TextButton")
    snapshotButton.Size = UDim2.new(0.3, 0, 0.1, 0)
    snapshotButton.Position = UDim2.new(0.35, 0, 0.05, 0)
    snapshotButton.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
    snapshotButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    snapshotButton.Text = "Take Snapshot"
    snapshotButton.Font = Enum.Font.GothamBold
    snapshotButton.Parent = parent
    
    local diffDisplay = Instance.new("ScrollingFrame")
    diffDisplay.Size = UDim2.new(1, -20, 0.8, 0)
    diffDisplay.Position = UDim2.new(0, 10, 0.2, 0)
    diffDisplay.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    diffDisplay.Parent = parent
    
    snapshotButton.MouseButton1Click:Connect(function()
        self:takeSnapshot("Manual_" .. os.time())
        self:updateDiffDisplay(diffDisplay)
    end)
end

function UniversalLuaStateViewer:updateDiffDisplay(display)
    for _, child in ipairs(display:GetChildren()) do
        child:Destroy()
    end
    
    if #state.snapshots < 2 then
        local noDiff = Instance.new("TextLabel")
        noDiff.Size = UDim2.new(1, 0, 1, 0)
        noDiff.BackgroundTransparency = 1
        noDiff.TextColor3 = Color3.fromRGB(255, 255, 255)
        noDiff.Text = "Take at least 2 snapshots to see differences"
        noDiff.Parent = display
        return
    end
    
    local latest = state.snapshots[#state.snapshots]
    local previous = state.snapshots[#state.snapshots - 1]
    local diff = self:diffSnapshots(previous, latest)
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = display
    
    -- Display differences
    self:addDiffSection(display, "New Closures", diff.closures.added)
    self:addDiffSection(display, "Removed Closures", diff.closures.removed)
    self:addDiffSection(display, "New Tables", diff.tables.added)
    self:addDiffSection(display, "Removed Tables", diff.tables.removed)
    
    display.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
end

function UniversalLuaStateViewer:addDiffSection(parent, title, data)
    if not next(data) then return end
    
    local section = Instance.new("Frame")
    section.Size = UDim2.new(1, 0, 0, 40)
    section.BackgroundColor3 = Color3.fromRGB(55, 55, 70)
    section.Parent = parent
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0.5, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.Text = title .. " (" .. self:countTable(data) .. ")"
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Parent = section
    
    local count = 0
    for id, item in pairs(data) do
        count = count + 1
        if count > 10 then break end -- Limit display
        
        local itemLabel = Instance.new("TextLabel")
        itemLabel.Size = UDim2.new(1, -20, 0, 20)
        itemLabel.Position = UDim2.new(0, 10, 0.5, count * 20)
        itemLabel.BackgroundTransparency = 1
        itemLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
        itemLabel.Text = tostring(item.name or id)
        itemLabel.TextXAlignment = Enum.TextXAlignment.Left
        itemLabel.Parent = section
        
        section.Size = UDim2.new(1, 0, 0, 40 + (count * 20))
    end
end

function UniversalLuaStateViewer:createSearchView(parent)
    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(0.8, 0, 0.1, 0)
    searchBox.Position = UDim2.new(0.1, 0, 0.05, 0)
    searchBox.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    searchBox.PlaceholderText = "Search across all VM state..."
    searchBox.Parent = parent
    
    local resultsFrame = Instance.new("ScrollingFrame")
    resultsFrame.Size = UDim2.new(1, -20, 0.8, 0)
    resultsFrame.Position = UDim2.new(0, 10, 0.2, 0)
    resultsFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    resultsFrame.Parent = parent
    
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        self:performSearch(searchBox.Text, resultsFrame)
    end)
end

function UniversalLuaStateViewer:performSearch(query, resultsFrame)
    for _, child in ipairs(resultsFrame:GetChildren()) do
        child:Destroy()
    end
    
    if query == "" then return end
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = resultsFrame
    
    local results = {}
    
    -- Search closures
    for id, closure in pairs(state.closures) do
        if string.find(closure.name:lower(), query:lower()) or
           string.find(tostring(closure.source):lower(), query:lower()) then
            table.insert(results, {type = "Closure", data = closure, id = id})
        end
    end
    
    -- Search tables
    for id, tbl in pairs(state.tables) do
        if string.find(tbl.name:lower(), query:lower()) then
            table.insert(results, {type = "Table", data = tbl, id = id})
        end
    end
    
    -- Display results
    for i, result in ipairs(results) do
        local resultFrame = Instance.new("Frame")
        resultFrame.Size = UDim2.new(1, 0, 0, 50)
        resultFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        resultFrame.Parent = resultsFrame
        
        local typeLabel = Instance.new("TextLabel")
        typeLabel.Size = UDim2.new(0.2, 0, 0.5, 0)
        typeLabel.BackgroundTransparency = 1
        typeLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
        typeLabel.Text = result.type
        typeLabel.TextXAlignment = Enum.TextXAlignment.Left
        typeLabel.Parent = resultFrame
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.8, 0, 0.5, 0)
        nameLabel.Position = UDim2.new(0.2, 0, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.Text = result.data.name or result.id
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = resultFrame
    end
    
    resultsFrame.CanvasSize = UDim2.new(0, 0, 0, #results * 55)
end

-- Utility Functions
function UniversalLuaStateViewer:countTable(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
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

-- Public API
function UniversalLuaStateViewer:start()
    self:installHooks()
    self:createGUI()
    self:takeSnapshot("Initial")
    
    print("Universal Lua State Viewer Started")
    print("Capturing: Closures, Upvalues, Tables, Modules, Metatables, Execution Flow")
end

function UniversalLuaStateViewer:stop()
    self.enabled = false
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

-- Initialize and return instance
local viewer = UniversalLuaStateViewer.new()
return viewer
