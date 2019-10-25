local fs = require('http.router.fs')
local response = require('http.router.response')
local utils = require('http.utils')
local lib = require('http.lib')
local tsgi = require('http.tsgi')

local json = require('json')

local function request_set_router(self, router)
    self[tsgi.KEY_ROUTER] = router
end

local function request_router(self)
    return self[tsgi.KEY_ROUTER]
end

local function cached_query_param(self, name)
    if name == nil then
        return self.query_params
    end
    return self.query_params[ name ]
end

local function cached_post_param(self, name)
    if name == nil then
        return self.post_params
    end
    return self.post_params[ name ]
end

local function request_tostring(self)
    local res = self:request_line() .. "\r\n"

    for hn, hv in pairs(tsgi.headers(self.env)) do
        res = utils.sprintf("%s%s: %s\r\n", res, utils.ucfirst(hn), hv)
    end

    return utils.sprintf("%s\r\n%s", res, self:read_cached())
end

local function request_line(self)
    local rstr = self:path()

    local query_string = self:query()
    if  query_string ~= nil and query_string ~= '' then
        rstr = rstr .. '?' .. query_string
    end

    return utils.sprintf("%s %s %s",
        self['REQUEST_METHOD'],
        rstr,
        self['SERVER_PROTOCOL'] or 'HTTP/?')
end

local function query_param(self, name)
    if self:query() ~= nil and string.len(self:query()) == 0 then
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

local function request_content_type(self)
    -- returns content type without encoding string
    if self['HEADER_CONTENT-TYPE'] == nil then
        return nil
    end

    return string.match(self['HEADER_CONTENT-TYPE'],
                        '^([^;]*)$') or
        string.match(self['HEADER_CONTENT-TYPE'],
                     '^(.*);.*')
end

local function post_param(self, name)
    local content_type = self:content_type()
    if content_type == 'multipart/form-data' then
        -- TODO: do that!
        rawset(self, 'post_params', {})
    elseif content_type == 'application/json' then
        local params = self:json()
        rawset(self, 'post_params', params)
    elseif content_type == 'application/x-www-form-urlencoded' then
        local params = lib.params(self:read_cached())
        local pres = {}
        for k, v in pairs(params) do
            pres[ utils.uri_unescape(k) ] = utils.uri_unescape(v, true)
        end
        rawset(self, 'post_params', pres)
    else
        local params = lib.params(self:read_cached())
        local pres = {}
        for k, v in pairs(params) do
            pres[ utils.uri_unescape(k) ] = utils.uri_unescape(v)
        end
        rawset(self, 'post_params', pres)
    end

    rawset(self, 'post_param', cached_post_param)
    return self:post_param(name)
end


local function param(self, name)
    if name ~= nil then
        local v = self:post_param(name)
        if v ~= nil then
            return v
        end
        return self:query_param(name)
    end

    local post = self:post_param()
    local query = self:query_param()
    return utils.extend(post, query, false)
end

local function cookie(self, cookiename)
    if self:header('cookie') == nil then
        return nil
    end
    for k, v in string.gmatch(
        self:header('cookie'), "([^=,; \t]+)=([^,; \t]+)") do
        if k == cookiename then
            return utils.uri_unescape(v)
        end
    end
    return nil
end

local function iterate(_, gen, gen_param, state)
    return setmetatable({ body = { gen = gen, param = gen_param, state = state } },
        response.metatable)
end

local function redirect_to(self, name, args, query)
    local location = self:url_for(name, args, query)
    return setmetatable({ status = 302, headers = { location = location } },
        response.metatable)
end

local function access_stash(self, name, ...)
    if type(self) ~= 'table' then
        error("usage: request:stash('name'[, 'value'])")
    end
    if select('#', ...) > 0 then
        self.tstash[ name ] = select(1, ...)
    end

    return self.tstash[ name ]
end

local function url_for_request(self, name, args, query)
    if name == 'current' then
        return self.endpoint:url_for(args, query)
    end
    return self.router:url_for(name, args, query)
end


local function request_json(req)
    local data = req:read_cached()
    local s, json_data = pcall(json.decode, data)
    if s then
        return json_data
    else
        error(utils.sprintf("Can't decode json in request '%s': %s",
                            data, tostring(json_data)))
        return nil
    end
end

local function request_read(self, opts, timeout)
    return self['tsgi.input']:read(opts, timeout)  -- TODO: TSGI spec is violated
end

local function request_read_cached(self)
    if self.cached_data == nil then
        local data = self['tsgi.input']:read()
        rawset(self, 'cached_data', data)
        return data
    else
        return self.cached_data
    end
end

-------------------------------------
local function request_peer(self)
    return self[tsgi.KEY_PEER]
end

local function request_method(self)
    return self['REQUEST_METHOD']
end

local function request_path(self)
    return self['PATH_INFO']
end

local function request_query(self)
    return self['QUERY_STRING']
end

local function request_proto(self)
    -- parse SERVER_PROTOCOL which is 'HTTP/<maj>.<min>'
    local maj = self['SERVER_PROTOCOL']:sub(-3, -3)
    local min = self['SERVER_PROTOCOL']:sub(-1, -1)
    return {
        [1] = tonumber(maj),
        [2] = tonumber(min),
    }
end

local function request_headers(self)
    local headers = {}
    for name, value in pairs(tsgi.headers(self)) do
        -- strip HEADER_ part and convert to lowercase
        local converted_name = name:sub(8):lower()
        headers[converted_name] = value
    end
    return headers
end

local function request_header(self, name)
    name = 'HEADER_' .. name:upper()
    return self[name]
end

----------------------------------

local function request_next(self)
    return tsgi.next(self)
end

local function request_hijack(self)
    return self['tsgi.hijack']()
end

local metatable = {
    __index = {
        router      = request_router,
        set_router  = request_set_router,

        render      = fs.render,
        cookie      = cookie,
        redirect_to = redirect_to,
        iterate     = iterate,
        stash       = access_stash,
        url_for     = url_for_request,
        content_type= request_content_type,
        request_line= request_line,
        read_cached = request_read_cached,

        query_param = query_param,
        post_param  = post_param,
        param       = param,

        read        = request_read,
        json        = request_json,

        peer        = request_peer,
        method      = request_method,
        path        = request_path,
        query       = request_query,
        proto       = request_proto,
        headers     = request_headers,
        header      = request_header,

        next        = request_next,
        hijack      = request_hijack,
    },
    __tostring = request_tostring;
}

local function bless(request)
    local mt = getmetatable(request)
    if mt == nil then
        return setmetatable(request, metatable)
    end

    -- merge to existing metatable
    for name, value in pairs(metatable) do
        if mt[name] ~= nil then
            require('log').info('merge_metatable: name already set: ' .. name)
        end
        assert(mt[name] == nil)
        mt[name] = value
    end
    return request
end

return {bless = bless}
