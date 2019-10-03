local tsgi = require('http.tsgi')

local checks = require('checks')
local json = require('json')
local log = require('log')

local KEY_BODY = 'tsgi.http.nginx_server.body'

local function convert_headername(name)
    return 'HEADER_' .. string.upper(name)
end

local function tsgi_input_read(self, n)
    checks('table', '?number')

    local start = self._pos
    local last

    if n ~= nil then
        last = start + n
        self._pos = last
    else
        last = #self._env[KEY_BODY]
        self._pos = last
    end

    return self._env[KEY_BODY]:sub(start, last)
end

local function tsgi_input_rewind(self)
    self._pos = 0
end

local function make_env(server, req)
    -- NGINX Tarantool Upstream `parse_query` option must NOT be set.
    local uriparts = string.split(req.uri, '?')
    local path_info, query_string = uriparts[1], uriparts[2]

    local body = ''
    if type(req.body) == 'string' then
        body = json.decode(req.body).params
    end

    local hostport = box.session.peer(box.session.id())
    local hostport_parts = string.split(hostport, ':')
    local peer_host, peer_port = hostport_parts[1], tonumber(hostport_parts[2])

    local env = {
        ['tsgi.version'] = '1',
        ['tsgi.url_scheme'] = 'http',     -- no support for https
        ['tsgi.input'] = {
            _pos = 0,                     -- last unread char in body
            read = tsgi_input_read,
            rewind = tsgi_input_rewind,
        },
        ['tsgi.hijack'] = nil,            -- no support for hijack with nginx
        ['REQUEST_METHOD'] = string.upper(req.method),
        ['SERVER_NAME'] = server.host,
        ['SERVER_PORT'] = server.port,
        ['PATH_INFO'] = path_info,
        ['QUERY_STRING'] = query_string,
        ['SERVER_PROTOCOL'] = req.proto,
        [tsgi.KEY_PEER] = {
            host = peer_host,
            port = peer_port,
            family = 'AF_INET',
            type = 'SOCK_STREAM',
            protocol = 'tcp',
        },

        [KEY_BODY] = body,            -- http body string; used in `tsgi_input_read`
    }

    -- Pass through `env` to env['tsgi.*']:read() functions
    env['tsgi.input']._env = env

    for name, value in pairs(req.headers) do
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

local function generic_entrypoint(server, req, ...)
    local env = make_env(server, req, ...)

    local ok, resp = pcall(server.router_obj, env)

    local status = resp.status or 200
    local headers = resp.headers or {}
    local body = resp.body or ''

    if not ok then
        status = 500
        headers = {}
        local trace = debug.traceback()

        -- TODO: copypaste
        -- TODO: env could be changed. we need to save a copy of it
        log.error('unhandled error: %s\n%s\nrequest:\n%s',
                 tostring(resp), trace, tsgi.serialize_request(env))

        if server.display_errors then
            body =
                "Unhandled error: " .. tostring(resp) .. "\n"
                .. trace .. "\n\n"
                .. "\n\nRequest:\n"
                .. tsgi.serialize_request(env)
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

local function ngxserver_set_router(self, router)
    checks('table', 'function|table')

    self.router_obj = router
end

local function ngxserver_router(self)
    return self.router_obj
end

local function ngxserver_start(self)
    checks('table')

    rawset(_G, self.tnt_method, function(...)
        return generic_entrypoint(self, ...)
    end)
end

local function ngxserver_stop(self)
    checks('table')

    rawset(_G, self.tnt_method, nil)
end

local function new(opts)
    checks({
        host = 'string',
        port = 'number',
        tnt_method = 'string',
        display_errors = '?boolean',
        log_errors = '?boolean',
        log_requests = '?boolean',
    })

    local self = {
        host = opts.host,
        port = opts.port,
        tnt_method = opts.tnt_method,
        display_errors = opts.display_errors or true,
        log_errors = opts.log_errors or true,
        log_requests = opts.log_requests or true,

        set_router = ngxserver_set_router,
        router = ngxserver_router,
        start = ngxserver_start,
        stop = ngxserver_stop,
    }
    return self
end

return {
    new = new,
}
