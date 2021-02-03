local lib = require('http.lib')
local utils = require('http.utils')

local function cached_query_param(self, name)
    if name == nil then
        return self.query_params
    end
    return self.query_params[ name ]
end

local function request_line(self)
    local rstr = self.path

    local query_string = self.query
    if  query_string ~= nil and query_string ~= '' then
        rstr = rstr .. '?' .. query_string
    end

    return utils.sprintf("%s %s %s",
        self['REQUEST_METHOD'],
        rstr,
        self['SERVER_PROTOCOL'] or 'HTTP/?')
end

local function query_param(self, name)
    if self.query ~= nil and string.len(self.query) == 0 then
        rawset(self, 'query_params', {})
    else
        local params = lib.params(self['QUERY_STRING'])
        local pres = {}
        for k, v in pairs(params) do
            pres[ utils.uri_unescape(k) ] = utils.uri_unescape(v)
        end
        rawset(self, 'query_params', pres)
    end

    rawset(self, 'query_param', cached_query_param)
    return self:query_param(name)
end

local function cookie(self, cookiename)
    if self.headers.cookie == nil then
        return nil
    end
    for k, v in string.gmatch(
        self.headers.cookie, "([^=,; \t]+)=([^,; \t]+)") do
        if k == cookiename then
            return utils.uri_unescape(v)
        end
    end
    return nil
end

local function create_http_v1_request(request)
    local new_request = table.copy(request)

    local new_request_mt = table.deepcopy(getmetatable(request))
    local mt_index_table = new_request_mt.__index

    new_request.headers = request:headers()
    new_request.path = request:path()
    new_request.peer = request:peer()
    new_request.method = request:method()
    new_request.proto = request:proto()
    new_request.query = request:query()

    -- redefine methods, which have conflicts with http-v1
    mt_index_table.request_line = request_line
    mt_index_table.query_param = query_param
    mt_index_table.cookie = cookie

    setmetatable(new_request, new_request_mt)
    return new_request
end

local function server_route(self, opts, handler)
    -- todo handle handler option
    local decorated_handler = handler
    if type(handler) == 'function'then
        decorated_handler = function(req)
            local hooks = self.server:router().hooks
            if hooks.before_dispatch ~= nil then
                hooks.before_dispatch(self, req)
            end

            local resp = handler(create_http_v1_request(req))

            if hooks.after_dispatch ~= nil then
                hooks.after_dispatch(req, resp)
            end

            return resp
        end
    end
    self.server:router():route(opts, decorated_handler)
    return self.server
end

local function server_match(self, method, route)
    return self.server:router():match(method, route)
end

local function server_helper(self, name, handler)
    self.server:router():helper(name, handler)
    return self.server
end

local function server_hook(self, name, handler)
    self.server:router():hook(name, handler)
    return self.server
end

local function server_url_for(self, name, args, query)
    return self.server:router():url_for(name, args, query)
end

local function set_handler(self, handler)
    setmetatable(self.server:router(), {__call = handler})
end

local function new(server)
    local server_adapter = {
        server  = server,
        -- v1 methods
        route   = server_route,
        match   = server_match,
        helper  = server_helper,
        hook    = server_hook,
        url_for = server_url_for,
        set_handler = set_handler,
    }

    return server_adapter
end

return {
    new = new,
}
