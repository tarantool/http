local tsgi_adapter = require('http.server.tsgi_adapter')

local tsgi = require('http.tsgi')
local lib = require('http.lib')
local utils = require('http.utils')

local log = require('log')
local socket = require('socket')
local errno = require('errno')

local DETACHED = 101

local VERSION = 'unknown'
if package.search('http.VERSION') then
    VERSION = require('http.VERSION')
end

---------
-- Utils
---------

local function normalize_headers(hdrs)
    local res = {}
    for h, v in pairs(hdrs) do
        res[ string.lower(h) ] = v
    end
    return res
end

local function headers_ended(hdrs)
    return string.endswith(hdrs, "\n\n")
        or string.endswith(hdrs, "\r\n\r\n")
end

----------
-- Server
----------

local function parse_request(req)
    local p = lib._parse_request(req)
    if p.error then
        return p
    end
    p.path = utils.uri_unescape(p.path)
    if p.path:sub(1, 1) ~= "/" or p.path:find("./", nil, true) ~= nil then
        p.error = "invalid uri"
        return p
    end
    return p
end

local function process_client(self, s, peer)
    while true do
        -- read headers, until double CRLF
        local hdrs = ''

        local is_eof = false
        while true do
            local chunk = s:read{
                delimiter = { "\n\n", "\r\n\r\n" }
            }

            if chunk == '' then
                is_eof = true
                break -- eof
            elseif chunk == nil then
                log.error('failed to read request: %s', errno.strerror())
                return
            end

            hdrs = hdrs .. chunk

            if headers_ended(hdrs) then
                break
            end
        end

        if is_eof then
            break
        end

        -- parse headers
        log.debug("request:\n%s", hdrs)
        local p = parse_request(hdrs)
        if p.error ~= nil then
            log.error('failed to parse request: %s', p.error)
            s:write(utils.sprintf("HTTP/1.0 400 Bad request\r\n\r\n%s", p.error))
            break
        end

        local env = tsgi_adapter.make_env({
            parsed_request = p,
            sock = s,
            httpd = self,
            peer = peer,
        })

        if env['HEADER_EXPECT'] == '100-continue' then
            s:write('HTTP/1.0 100 Continue\r\n\r\n')
        end

        local logreq = self.options.log_requests and log.info or log.debug
        logreq("%s %s%s", p.method, p.path,
            p.query ~= "" and "?"..p.query or "")

        local ok, resp = pcall(self.options.router, env)
        env['tsgi.input']:read() -- skip remaining bytes of request body
        local status, body

        -- DETACHED: dont close socket, but quit processing HTTP
        if env[tsgi.KEY_IS_HIJACKED] == true then
            break
        end

        -- set response headers
        if not ok then
            status = 500
            hdrs = {}
            local trace = debug.traceback()
            local logerror = self.options.log_errors and log.error or log.debug

            -- TODO: copypaste
            logerror('unhandled error: %s\n%s\nrequest:\n%s',
                tostring(resp), trace, tsgi.serialize_request(env))
            if self.options.display_errors then
            -- TODO: env could be changed. we need to save a copy of it
            body =
                  "Unhandled error: " .. tostring(resp) .. "\n"
                .. trace .. "\n\n"
                .. "\n\nRequest:\n"
                .. tsgi.serialize_request(env)
            else
                body = "Internal Error"
            end
       elseif type(resp) == 'table' then
            if resp.status == nil then
                status = 200
            elseif type(resp.status) == 'number' then
                status = resp.status
            else
                error('response.status must be a number')
            end
            if resp.headers == nil then
                hdrs = {}
            elseif type(resp.headers) == 'table' then
                hdrs = normalize_headers(resp.headers)
            else
                error('response.headers must be a table')
            end
            body = resp.body
        elseif resp == nil then
            status = 200
            hdrs = {}
        elseif type(resp) == 'number' then
            if resp == DETACHED then
                break
            end
        else
            error('invalid response')
        end

        -- set more response headers
        local gen, param, state
        if type(body) == 'string' then
            -- Plain string
            hdrs['content-length'] = #body
        elseif type(body) == 'function' then
            -- Generating function
            gen = body
            hdrs['transfer-encoding'] = 'chunked'
        elseif type(body) == 'table' and body.gen then
            -- Iterator
            gen, param, state = body.gen, body.param, body.state
            hdrs['transfer-encoding'] = 'chunked'
        elseif body == nil then
            -- Empty body
            hdrs['content-length'] = 0
        else
            body = tostring(body)
            hdrs['content-length'] = #body
        end

        if hdrs.server == nil then
            hdrs.server = utils.sprintf('Tarantool http (tarantool v%s)', _TARANTOOL)
        end

        -- handle even more response headers
        if p.proto[1] ~= 1 then
            hdrs.connection = 'close'
        elseif p.broken then
            hdrs.connection = 'close'
        elseif rawget(p, 'body') == nil then
            hdrs.connection = 'close'
        elseif p.proto[2] == 1 then
            if p.headers.connection == nil then
                hdrs.connection = 'keep-alive'
            elseif string.lower(p.headers.connection) ~= 'keep-alive' then
                hdrs.connection = 'close'
            else
                hdrs.connection = 'keep-alive'
            end
        elseif p.proto[2] == 0 then
            if p.headers.connection == nil then
                hdrs.connection = 'close'
            elseif string.lower(p.headers.connection) == 'keep-alive' then
                hdrs.connection = 'keep-alive'
            else
                hdrs.connection = 'close'
            end
        end

        -- generate response {{{
        local response = {
            "HTTP/1.1 ";
            status;
            " ";
            utils.reason_by_code(status);
            "\r\n";
        };
        for k, v in pairs(hdrs) do
            if type(v) == 'table' then
                for _, sv in pairs(v) do
                    table.insert(response, utils.sprintf("%s: %s\r\n", utils.ucfirst(k), sv))
                end
            else
                table.insert(response, utils.sprintf("%s: %s\r\n", utils.ucfirst(k), v))
            end
        end
        table.insert(response, "\r\n")

        if type(body) == 'string' then
            table.insert(response, body)
            response = table.concat(response)
            if not s:write(response) then
                break
            end
        elseif gen then
            response = table.concat(response)
            if not s:write(response) then
                break
            end
            -- Transfer-Encoding: chunked
            for _, part in gen, param, state do
                part = tostring(part)
                if not s:write(utils.sprintf("%x\r\n%s\r\n", #part, part)) then
                    break
                end
            end
            if not s:write("0\r\n\r\n") then
                break
            end
        else
            response = table.concat(response)
            if not s:write(response) then
                break
            end
        end
        -- }}}

        if p.proto[1] ~= 1 then
            break
        end

        if hdrs.connection ~= 'keep-alive' then
            break
        end
    end
end

local function httpd_stop(self)
    if type(self) ~= 'table' then
        error("httpd: usage: httpd:stop()")
    end
    if self.is_run then
        self.is_run = false
    else
        error("server is already stopped")
    end

    if self.tcp_server ~= nil then
        self.tcp_server:close()
        self.tcp_server = nil
    end
    return self
end


local function httpd_start(self)
    if type(self) ~= 'table' then
        error("httpd: usage: httpd:start()")
    end

    assert(self.options.router ~= nil, 'Router must be set before calling server:start()')

    local server = socket.tcp_server(self.host, self.port,
                                     { name = 'http',
                                       handler = function(...)
                                           local _ = process_client(self, ...)
    end})
    if server == nil then
        error(utils.sprintf("Can't create tcp_server: %s", errno.strerror()))
    end

    rawset(self, 'is_run', true)
    rawset(self, 'tcp_server', server)
    rawset(self, 'stop', httpd_stop)

    return self
end

local function httpd_set_router(self, router)
    self.options.router = router
end

local function httpd_router(self)
    return self.options.router
end

local new = function(host, port, options)
    if options == nil then
        options = {}
    end
    if type(options) ~= 'table' then
        utils.errorf("options must be table not '%s'", type(options))
    end

    local default = {
        router              = nil,   -- no router set-up initially
        log_requests        = true,
        log_errors          = true,
        display_errors      = true,
    }

    local self = {
        host       = host,
        port       = port,
        is_run     = false,
        stop       = httpd_stop,
        start      = httpd_start,
        set_router = httpd_set_router,
        router     = httpd_router,
        options    = utils.extend(default, options, true),
    }

    return self
end

return {
    VERSION = VERSION,
    DETACHED = DETACHED,
    new = new,
}
