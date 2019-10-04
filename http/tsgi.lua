-- TSGI helper functions

local utils = require('http.utils')

local KEY_HTTPD = 'tarantool.http.httpd'
local KEY_SOCK = 'tarantool.http.sock'
local KEY_REMAINING = 'tarantool.http.sock_remaining_len'
local KEY_PARSED_REQUEST = 'tarantool.http.parsed_request'
local KEY_PEER = 'tarantool.http.peer'
local KEY_ROUTE = 'tarantool.http.route'
local KEY_ROUTER = 'tarantool.http.router'
local KEY_IS_HIJACKED = 'tarantool.http.server.is_hijacked'

local KEY_MIDDLEWARE_CALLCHAIN_CURRENT = 'tarantool.middleware.callchain_current'
local KEY_MIDDLEWARE_CALLCHAIN_TABLE = 'tarantool.middleware.callchain_table'

-- XXX: do it with lua-iterators
local function headers(env)
    local map = {}
    for name, value in pairs(env) do
        if string.startswith(name, 'HEADER_') then
            map[name] = value
        end
    end
    return map
end

local function serialize_request(env)
    -- {{{
    -- TODO: copypaste from router/request.lua.
    -- maybe move it to tsgi.lua.

    local res = env['PATH_INFO']
    local query_string = env['QUERY_STRING']
    if query_string ~= nil and query_string ~= '' then
        res = res .. '?' .. query_string
    end

    res = utils.sprintf("%s %s %s",
                        env['REQUEST_METHOD'],
                        res,
                        env['SERVER_PROTOCOL'] or 'HTTP/?')
    res = res .. "\r\n"
    -- }}} end of request_line copypaste

    for hn, hv in pairs(headers(env)) do
        res = utils.sprintf("%s%s: %s\r\n", res, utils.ucfirst(hn), hv)
    end

    -- return utils.sprintf("%s\r\n%s", res, self:read_cached())
    -- NOTE: no body is logged.
    return res
end

local function middleware_init_handlers(env)
    env[KEY_MIDDLEWARE_CALLCHAIN_CURRENT] = 0
    env[KEY_MIDDLEWARE_CALLCHAIN_TABLE] = {}
end

local function middleware_invoke_next_handler(env)
    local callchain = env[KEY_MIDDLEWARE_CALLCHAIN_TABLE]
    local next_handler_id = env[KEY_MIDDLEWARE_CALLCHAIN_CURRENT] + 1
    local next_handler = callchain[next_handler_id]
    env[KEY_MIDDLEWARE_CALLCHAIN_CURRENT] = next_handler_id
    return next_handler(env)
end

local function middleware_push_back_handler(env, f)
    local callchain = env[KEY_MIDDLEWARE_CALLCHAIN_TABLE]
    table.insert(callchain, f)
end

return {
    KEY_HTTPD = KEY_HTTPD,
    KEY_SOCK = KEY_SOCK,
    KEY_REMAINING = KEY_REMAINING,
    KEY_PARSED_REQUEST = KEY_PARSED_REQUEST,
    KEY_PEER = KEY_PEER,
    KEY_IS_HIJACKED = KEY_IS_HIJACKED,

    headers = headers,
    serialize_request = serialize_request,

    -- middleware support
    KEY_MIDDLEWARE_CALLCHAIN_CURRENT = KEY_MIDDLEWARE_CALLCHAIN_CURRENT,
    KEY_MIDDLEWARE_CALLCHAIN_TABLE = KEY_MIDDLEWARE_CALLCHAIN_TABLE,
    KEY_ROUTE = KEY_ROUTE,
    KEY_ROUTER = KEY_ROUTER,

    init_handlers = middleware_init_handlers,
    next = middleware_invoke_next_handler,
    push_back_handler = middleware_push_back_handler,
}
