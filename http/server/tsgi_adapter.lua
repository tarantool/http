local tsgi = require('http.tsgi')

local checks = require('checks')

local function tsgi_hijack(env)
    env[tsgi.KEY_IS_HIJACKED] = true

    local sock = env[tsgi.KEY_SOCK]
    return sock
end

-- TODO: understand this. Maybe rewrite it to only follow
-- TSGI logic, and not router logic.
--
-- if opts is number, it specifies number of bytes to be read
-- if opts is a table, it specifies options
local function tsgi_input_read(self, opts, timeout)
    checks('table', '?number|string|table', '?number')
    local env = self._env

    local remaining = env[tsgi.KEY_REMAINING]
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

    local buf = env[tsgi.KEY_SOCK]:read(opts, timeout)
    if buf == nil then
        env[tsgi.KEY_REMAINING] = 0
        return ''
    end
    remaining = remaining - #buf
    assert(remaining >= 0)
    env[tsgi.KEY_REMAINING] = remaining
    return buf
end

local function convert_headername(name)
    return 'HEADER_' .. string.upper(name)  -- TODO: hyphens
end

local function make_env(opts)
    local p = opts.parsed_request

    local env = {
        [tsgi.KEY_SOCK] = opts.sock,
        [tsgi.KEY_HTTPD] = opts.httpd,
        [tsgi.KEY_PARSED_REQUEST] = p,          -- TODO: delete?
        [tsgi.KEY_PEER] = opts.peer,            -- TODO: delete?

        ['tsgi.version'] = '1',
        ['tsgi.url_scheme'] = 'http',      -- no support for https yet
        ['tsgi.input'] = {
            read = tsgi_input_read,
            rewind = nil,                  -- non-rewindable by default
        },

        ['REQUEST_METHOD'] = p.method,
        ['PATH_INFO'] = p.path,
        ['QUERY_STRING'] = p.query,
        ['SERVER_NAME'] = opts.httpd.host,
        ['SERVER_PORT'] = opts.httpd.port,
        ['SERVER_PROTOCOL'] = string.format('HTTP/%d.%d', p.proto[1], p.proto[2]),
    }

    -- Pass through `env` to env['tsgi.*']:*() functions
    env['tsgi.input']._env = env
    env['tsgi.hijack'] = setmetatable(env, {
        __call = tsgi_hijack,
    })

    -- set headers
    for name, value in pairs(p.headers) do
        env[convert_headername(name)] = value
    end

    -- SCRIPT_NAME is a virtual location of your app.
    --
    -- Imagine you want to serve your HTTP API under prefix /test
    -- and later move it to /.
    --
    -- Instead of rewriting endpoints to your application, you do:
    --
    -- location /test/ {
    --     proxy_pass http://127.0.0.1:8001/test/;
    --     proxy_redirect http://127.0.0.1:8001/test/ http://$host/test/;
    --     proxy_set_header SCRIPT_NAME /test;
    -- }
    --
    -- Application source code is not touched.
    env['SCRIPT_NAME'] = env['HTTP_SCRIPT_NAME'] or ''
    env['HTTP_SCRIPT_NAME'] = nil

    return env
end

return {
    make_env = make_env,
}
