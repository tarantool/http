local json = require('json')

local codes = {
    parse = {
        code = -32700, message = "Parse error"
    },
    request = {
        code = -32600, message = "Invalid Request"
    },
    method = {
        code = -32601, message = "Method not found"
    },
    params = {
        code = -32602, message = "Invalid params"
    },
    error = {
        code = -32603, message = "Internal error"
    }
}

local methods = {}

local function rpc_encode(self, opts)
    local data = opts['jsonrpc']
    if data.error or data.id == nil then
        data.id = json.NULL
    end
    data.jsonrpc = "2.0"
    return {
        headers = {
          ['content-type'] = 'application/json'
        },
        body = json.encode(data),
    }
end

local function rpc_decode(self)
    local data   = self:read()
    local parsed = {}
    if data == nil then
        parsed.error = codes.parse
        return parsed
    end

    local s, rpc = pcall(json.decode, data)

    if not s or rpc == nil then
        parsed.error = codes.parse
        return parsed
    end

    if rpc.id == nil then
        parsed.error = codes.request
        return parsed
    end

    if rpc.jsonrpc == nil or type(rpc.jsonrpc) ~= 'string' then
        parsed.error = codes.request
        return parsed
    end

    if rpc.method == nil or type(rpc.method) ~= 'string' then
        parsed.error = codes.request
        return parsed
    end
    return rpc
end

local function call_method(self, rpc)
    local command = methods[self.path][rpc.method]
    local resp    = {}
    if type(command) ~= 'function' then
        resp.error = codes.method
        return self:render{jsonrpc=resp}
    end
    local result = command(self, codes, rpc.params)

    -- Can not return false result, because LUA hide table keys if
    -- key equal false. We always return -32603 error if method
    -- returned false.
    if not result.result or result.error then
        resp.error = result.error
        if not resp.error then
            resp.error = codes.error
        end
        return self:render{jsonrpc=resp}
    end

    resp.result = result.result
    resp.id = rpc.id
    return self:render{jsonrpc=resp}
end

local function rpc_function(self)
    local rpc  = self:jsonrpc()

    if rpc.error then
        return self:render{jsonrpc = rpc}
    end

    return call_method(self, rpc)
end

local function rpc_server(self, opts, callbacks)
    self:route({path = opts.path}, rpc_function)
    methods[opts.path] = callbacks
    return self
end

local function plugin(self, opts)
    return {
        render = {
            name = 'jsonrpc',
            ext  = rpc_encode,
        },
        request = {
            name = 'jsonrpc',
            ext  = rpc_decode,
        },
        server = {
            name = 'jsonrpc',
            ext  = rpc_server,
        }
    }
end

return plugin
