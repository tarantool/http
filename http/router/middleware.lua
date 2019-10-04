local COLOR_NOT_VISITED = 0
local COLOR_IN_PROGRESS   = 1
local COLOR_VISITED     = 2

local function dfs(self, v, colors, reverse_order)
    if colors[v] == COLOR_VISITED then
        -- already traversed v
        return true
    elseif colors[v] == COLOR_IN_PROGRESS then
        -- loop detected
        return false
    end
    colors[v] = COLOR_IN_PROGRESS

    for _, to in ipairs(self.edges[v]) do
        local ok = self:dfs(to, colors, reverse_order)
        if not ok then
            return false
        end
    end

    table.insert(reverse_order, v)
    colors[v] = COLOR_VISITED
    return true
end

local function prepare_graph(self)
    local numvertices = #self.nodes

    self.edges = {}
    for v = 1, numvertices do
        self.edges[v] = {}
    end

    for v, node in pairs(self.nodes) do
        for _, from_name in pairs(node.after) do
            local from = self.id_by_name[from_name]
            if from ~= nil then
                table.insert(self.edges[from], v)
            end
        end

        for _, to_name in pairs(node.before) do
            local to = self.id_by_name[to_name]
            if to ~= nil then
                table.insert(self.edges[v], to)
            end
        end
    end
end

local function find_order(self)
    self:prepare_graph()

    local numvertices = #self.nodes

    local reverse_order = {}
    local colors = {}
    for v = 1, numvertices do
        colors[v] = COLOR_NOT_VISITED
    end

    local conflict = false
    for v = 1, numvertices do
        if colors[v] == COLOR_NOT_VISITED then
            local ok = self:dfs(v, colors, reverse_order)
            if not ok then
                conflict = true
                break
            end
        end
    end
    if conflict then
        return false
    end

    assert(#reverse_order, numvertices, 'ordered every node')

    self.order = {}
    for i = numvertices, 1, -1 do
        table.insert(self.order, reverse_order[i])
    end

    return true
end

local function listify(val)
    return type(val) == 'table' and val or {val}
end

local function ordered(self)
    local ret = {}
    for _, v in ipairs(self.order) do
        table.insert(ret, self.nodes[v])
    end
    return ret
end

-- TODO: error-handling
local function use(self, m)
    m.after = listify(m.after)
    m.before = listify(m.before)

    table.insert(self.nodes, m)
    self.id_by_name[m.name] = #self.nodes

    local ok = self:find_order()
    if not ok then
        -- rollback
        table.remove(self.nodes)

        ok = self:find_order()
        assert(ok, 'rollback failed!')
        return false
    end
    return true
end

local function clear(self)
    self.nodes = {}
    self.id_by_name = {}
    self.order = {}
end

local function new()
    return {
        nodes = {},
        id_by_name = {},
        order = {},

        use = use,
        clear = clear,
        ordered = ordered,

        -- private
        prepare_graph = prepare_graph,
        find_order = find_order,
        dfs = dfs,
    }
end

return {
    new = new,
}
