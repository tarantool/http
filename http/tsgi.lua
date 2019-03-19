local log = require('log')

local KEY_HTTPD = 'tarantool.http.httpd'
local KEY_SOCK = 'tarantool.http.sock'
local KEY_REMAINING = 'tarantool.http.sock_remaining_len'
local KEY_PARSED_REQUEST = 'tarantool.http.parsed_request'
local KEY_PEER = 'tarantool.http.peer'

-- helpers

-- XXX: do it with lua-iterators
local function headers(env)
    local map = {}
    for name, value in pairs(env) do
        if string.startswith(name, 'HEADER_') then  -- luacheck: ignore
            map[name] = value
        end
    end
    return map
end

---

local function noop() end

local function tsgi_errors_write(env, msg)  -- luacheck: ignore
    log.error(msg)
end

local function tsgi_hijack(env)
    local httpd = env[KEY_HTTPD]
    local sock = env[KEY_SOCK]

    httpd.is_hijacked = true
    return sock
end

local function tsgi_input_read(env, opts, timeout)
    local remaining = env[KEY_REMAINING]
    if not remaining then
        remaining = tonumber(env['HEADER_CONTENT-LENGTH'])  -- TODO: hyphen
        if not remaining then
            return ''
        end
    end

    if opts == nil then
        opts = remaining
    elseif type(opts) == 'number' then
        if opts > remaining then
            opts = remaining
        end
    elseif type(opts) == 'string' then
        opts = { size = remaining, delimiter = opts }
    elseif type(opts) == 'table' then
        local size = opts.size or opts.chunk
        if size and size > remaining then
            opts.size = remaining
            opts.chunk = nil
        end
    end

    local buf = env[KEY_SOCK]:read(opts, timeout)
    if buf == nil then
        env[KEY_REMAINING] = 0
        return ''
    end
    remaining = remaining - #buf
    assert(remaining >= 0)
    env[KEY_REMAINING] = remaining
    return buf
end

local function convert_headername(name)
    return 'HEADER_' .. string.upper(name)  -- TODO: hyphens
end

local function make_env(opts)
    local p = opts.parsed_request

    local env = {
        [KEY_SOCK] = opts.sock,
        [KEY_HTTPD] = opts.httpd,
        [KEY_PARSED_REQUEST] = p,        -- TODO: delete?
        [KEY_PEER] = opts.peer,               -- TODO: delete?

        ['tsgi.version'] = '1',
        ['tsgi.url_scheme'] = 'http',     -- no support for https yet
        ['tsgi.input'] = {
            read = tsgi_input_read,
            rewind = nil,                  -- TODO
        },
        ['tsgi.errors'] = {
            write = tsgi_errors_write,
            flush = noop,
        },
        ['tsgi.hijack'] = tsgi_hijack,

        ['REQUEST_METHOD'] = p.method,
        ['SCRIPT_NAME'] = '',              -- TODO: what the heck is this?
        ['PATH_INFO'] = p.path,
        ['QUERY_STRING'] = p.query,
        ['SERVER_NAME'] = opts.httpd.host,
        ['SERVER_PORT'] = opts.httpd.port,
        ['SERVER_PROTOCOL'] = string.format('HTTP/%d.%d', p.proto[1], p.proto[2]),
    }

    -- set headers
    for name, value in pairs(p.headers) do
        env[convert_headername(name)] = value
    end

    return env
end

return {
    make_env = make_env,
    headers = headers,
    KEY_HTTPD = KEY_HTTPD,
    KEY_PARSED_REQUEST = KEY_PARSED_REQUEST,
    KEY_PEER = KEY_PEER,
}
