local fs = require('http.router.fs')
local response = require('http.router.response')
local utils = require('http.utils')
local lib = require('http.lib')
local tsgi = require('http.tsgi')

local json = require('json')

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
    local rstr = self.env['PATH_INFO']
    if string.len(self.env['QUERY_STRING']) then
        rstr = rstr .. '?' .. self.env['QUERY_STRING']
    end
    return utils.sprintf("%s %s %s",
        self.env['REQUEST_METHOD'],
        rstr,
        self.env['SERVER_PROTOCOL'] or 'HTTP/?')
end

local function query_param(self, name)
    if self.env['QUERY_STRING'] == nil and string.len(self.env['QUERY_STRING']) == 0 then
        rawset(self, 'query_params', {})
    else
        local params = lib.params(self.env['QUERY_STRING'])
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
    if self.env['HEADER_CONTENT-TYPE'] == nil then
        return nil
    end

    return string.match(self.env['HEADER_CONTENT-TYPE'],
                        '^([^;]*)$') or
        string.match(self.env['HEADER_CONTENT-TYPE'],
                     '^(.*);.*')
end

local function post_param(self, name)
    local content_type = self:content_type()
    if self:content_type() == 'multipart/form-data' then
        -- TODO: do that!
        rawset(self, 'post_params', {})
    elseif self:content_type() == 'application/json' then
        local params = self:json()
        rawset(self, 'post_params', params)
    elseif self:content_type() == 'application/x-www-form-urlencoded' then
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
    if self.env['HEADER_COOKIE'] == nil then
        return nil
    end
    for k, v in string.gmatch(
        self.env['HEADER_COOKIE'], "([^=,; \t]+)=([^,; \t]+)") do
        if k == cookiename then
            return utils.uri_unescape(v)
        end
    end
    return nil
end

local function iterate(self, gen, param, state)
    return setmetatable({ body = { gen = gen, param = param, state = state } },
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
    local s, json = pcall(json.decode, data)
    if s then
        return json
    else
        error(utils.sprintf("Can't decode json in request '%s': %s",
                            data, tostring(json)))
        return nil
    end
end

local function request_read(self, opts, timeout)
    local env = self.env
    return env['tsgi.input'].read(env, opts, timeout)
end

local function request_read_cached(self)
    if self.cached_data == nil then
        local env = self.env
        local data = env['tsgi.input'].read(env)
        rawset(self, 'cached_data', data)
        return data
    else
        return self.cached_data
    end
end

local metatable = {
    __index = {
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
        json        = request_json
    },
    __tostring = request_tostring;
}
return {metatable = metatable}
