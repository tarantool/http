local tsgi = require('http.tsgi')

local json = require('json')
local log = require('log')

local KEY_BODY = 'tsgi.http.nginx_server.body'

local self

local function noop() end

local function convert_headername(name)
    return 'HEADER_' .. string.upper(name)
end

local function tsgi_input_read(env)
    return env[KEY_BODY]
end

local function make_env(req)
    -- in nginx dont provide `parse_query` for this to work
    local uriparts = string.split(req.uri, '?')  -- luacheck: ignore
    local path_info, query_string = uriparts[1], uriparts[2]

    local body = ''
    if type(req.body) == 'string' then
        body = json.decode(req.body).params
    end

    local env = {
        ['tsgi.version'] = '1',
        ['tsgi.url_scheme'] = 'http',     -- no support for https
        ['tsgi.input'] = {
            read = tsgi_input_read,
            rewind = nil,                 -- TODO
        },
        ['tsgi.errors'] = {
            write = noop,
            flush = noop,
        },
        ['tsgi.hijack'] = nil,            -- no hijack with nginx
        ['REQUEST_METHOD'] = string.upper(req.method),
        ['SERVER_NAME'] = self.host,
        ['SERVER_PORT'] = self.port,
        ['SCRIPT_NAME'] = '',             -- TODO: what do we put here?
        ['PATH_INFO'] = path_info,
        ['QUERY_STRING'] = query_string,
        ['SERVER_PROTOCOL'] = req.proto,

        [tsgi.KEY_PEER] = {
            host = self.host,
            port = self.port,
        },

        [KEY_BODY] = body,            -- http body string; used in `tsgi_input_read`
    }

    for name, value in pairs(req.headers) do
        env[convert_headername(name)] = value
    end

    return env
end

function nginx_entrypoint(req, ...) -- luacheck: ignore
    local env = make_env(req, ...)

    local ok, resp = pcall(self.router, env)

    local status = resp.status or 200
    local headers = resp.headers or {}
    local body = resp.body or ''

    if not ok then
        status = 500
        headers = {}
        local trace = debug.traceback()
        local p = 'TODO_REQUEST_DESCRIPTION'  -- TODO

        log.error('unhandled error: %s\n%s\nrequest:\n%s',
                 tostring(resp), trace, tostring(p))  -- TODO: tostring(p)

        if self.display_errors then
            body =
                "Unhandled error: " .. tostring(resp) .. "\n"
                .. trace .. "\n\n"
                .. "\n\nRequest:\n"
                .. tostring(p)  -- TODO: tostring(p)
        else
            body = "Internal Error"
        end
    end

    -- handle iterable body
    local gen, param, state

    if type(body) == 'function' then
        -- Generating function
        gen = body
    elseif type(body) == 'table' and body.gen then
        -- Iterator
        gen, param, state = body.gen, body.param, body.state
    end

    if gen ~= nil then
        body = ''
        for _, part in gen, param, state do
            body = body .. tostring(part)
        end
    end

    return status, headers, body
end

local function ngxserver_set_router(_, router)
    self.router = router
end

local function init(opts)
    if not self then
        self = {
            host = opts.host,
            port = opts.port,
            display_errors = opts.display_errors or true,

            set_router = ngxserver_set_router,
            start = noop,  -- TODO: fix
            stop = noop    -- TODO: fix
        }
    end
    return self
end

return {
    init = init,
}
