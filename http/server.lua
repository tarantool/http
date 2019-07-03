-- http.server

local lib = require('http.lib')

local io = io
local require = require
local package = package
local sprintf = string.format
local mime_types = require('http.mime_types')
local codes = require('http.codes')

local log = require('log')
local fun = require('fun')
local socket = require('socket')
local json = require('json')
local errno = require("errno")

local DETACHED = 101

local function errorf(fmt, ...)
    error(sprintf(fmt, ...))
end

local function uri_escape(str)
    local res = {}
    if type(str) == 'table' then
        fun.each(
            function(v)
                table.insert(res, uri_escape(v))
            end,
            str
        )

        return res
    end

    res = str:gsub(
        '[^a-zA-Z0-9_]',
        function(c)
            return sprintf('%%%02X', string.byte(c))
        end
    )

    return res
end

local function uri_unescape(str, unescape_plus_sign)
    local res = {}

    if type(str) == 'table' then
        fun.each(
            function(v)
                table.insert(res, uri_unescape(v, unescape_plus_sign))
            end,
            str
        )

        return res
    end

    res = str:gsub(
            '%%([0-9a-fA-F][0-9a-fA-F])',
            function(c)
                return string.char(tonumber(c, 16))
            end
        )

    -- unescaped pluses are "%2", so gsub didn't match those before
    if unescape_plus_sign then
        res = res:gsub('+', ' ')
    end

    return res
end

local function extend(tbl, tblu, raise)
    local res = table.deepcopy(tbl)

    fun.each(
        function(k, v)
            if raise and res[k] == nil then
                errorf("Unknown option %q", k)
            end
            rawset(res, k, v)
        end,
        tblu
    )

    return res
end

local function type_by_format(fmt)
    return mime_types[fmt] or 'application/octet-stream'
end

local function reason_by_code(code)
    return codes[tonumber(code)] or sprintf('Unknown code %d', code)
end

local function ucfirst(str)
    return str:gsub("^%l", string.upper, 1)
end

local function cached_query_param(self, name)
    return self.query_params[name] or self.query_params
end

local function cached_post_param(self, name)
    return self.post_params[name] or self.post_params
end

local function request_tostring(self)
    local res = self:request_line() .. "\r\n"

    fun.each(
        function(hn, hv)
            res = sprintf("%s%s: %s\r\n", res, ucfirst(hn), hv)
        end,
        self.req.headers
    )

    return sprintf("%s\r\n%s", res, self.req.body)
end

local function request_line(self)
    local rstr = self.req.path

    if self.req.query and #self.req.query > 0 then
        rstr = sprintf("%s?%s", rstr, self.req.query)
    end

    return sprintf(
        "%s %s HTTP/%d.%d",
        self.req.method,
        rstr,
        self.req.proto[1],
        self.req.proto[2]
    )
end

local function query_param(self, name)
    if self.req.query == nil or #self.req.query == 0 then
        rawset(self, 'query_params', {})
    else
        local params = lib.params(self.req.query)
        local pres = {}

        fun.each(
            function(k, v)
                rawset(pres, uri_unescape(k), uri_unescape(v))
            end,
            params
        )
        rawset(self, 'query_params', pres)
    end

    rawset(self, 'query_param', cached_query_param)
    return self:query_param(name)
end

local function request_content_type(self)
    -- returns content type without encoding string
    if self.req.headers['content-type'] == nil then
        return nil
    end

    return string.match(
        self.req.headers['content-type'],
        '^([^;]*)$') or
        string.match(
            self.req.headers['content-type'],
            '^(.*);.*'
        )
end

local function post_param(self, name)
    local content_type = self:content_type()

    if content_type == 'multipart/form-data' then
        -- TODO: do that!
        rawset(self, 'post_params', {})
    elseif content_type == 'application/json' then
        local params = self:json()
        rawset(self, 'post_params', params)
    else
        local params = lib.params(self:read_cached())
        local pres = {}

        -- escape plus signs if x-www-form-urlencoded and do not otherwise
        local escape = (content_type == 'application/x-www-form-urlencoded')

        fun.each(
            function(k, v)
                rawset(pres, uri_unescape(k), uri_unescape(v, escape))
            end,
            params
        )

        rawset(self, 'post_params', pres)
    end

    rawset(self, 'post_param', cached_post_param)
    return self:post_param(name)
end

local function param(self, name)
    if name ~= nil then
        return self:post_param(name) or self:query_param(name)
    end

    local post = self:post_param()
    local query = self:query_param()
    return extend(post, query, false)
end

local function catfile(...)
    local sp = { ... }

    local path

    if #sp == 0 then
        return
    end

    fun.each(
        function(pe)
            if path == nil then
                path = pe
            elseif string.match(path, '.$') ~= '/' then
                path = (string.match(pe, '^.') ~= '/') and
                    (path .. '/' .. pe) or path .. pe
            else
                path = (string.match(pe, '^.') == '/') and
                    (path .. string.gsub(pe, '^/', '', 1)) or path .. pe
            end
        end,
        sp
    )

    return path
end

local request_mt

local function expires_str(str)
    local gmtnow = os.date("!*t", os.time())
    local fmt = '%a, %d-%b-%Y %H:%M:%S GMT'

    if str == 'now' or tonumber(str) == 0 then
        return os.date(fmt, os.time(gmtnow))
    end

    local diff, period = str:match('^[+]?(%d+)([hdmy])$')
    if not period then
        return str
    end

    if period == 'h' then
        gmtnow.hour = gmtnow.hour + diff
    elseif period == 'd' then
        gmtnow.day = gmtnow.day + diff
    elseif period == 'm' then
        gmtnow.month = gmtnow.month + diff
    else
        gmtnow.year = gmtnow.year + 1
    end

    return os.date(fmt, os.time(gmtnow))
end

local function setcookie(ctx, cookie)
    local name = cookie.name
    local value = cookie.value

    if name == nil then
        error('cookie.name is undefined')
    end
    if value == nil then
        error('cookie.value is undefined')
    end

    local str = sprintf('%s=%s', name, uri_escape(value))
    if cookie.path ~= nil then
        str = sprintf('%s;path=%s', str, cookie.path)
    end
    if cookie.domain ~= nil then
        str = sprintf('%s;domain=%s', str, cookie.domain)
    end

    if cookie.expires ~= nil then
        str = sprintf('%s;expires=%s', str, expires_str(cookie.expires))
    end

    if not ctx.res then
        ctx.res = {}
    end

    if not ctx.res.headers then
        ctx.res.headers = {}
    end

    if ctx.res.headers['set-cookie'] == nil then
        ctx.res.headers['set-cookie'] = { str }
    elseif type(ctx.res.headers['set-cookie']) == 'string' then
        ctx.res.headers['set-cookie'] = {
            ctx.res.headers['set-cookie'],
            str
        }
    else
        table.insert(ctx.res.headers['set-cookie'], str)
    end

    return
end

local function cookie(ctx, c)
    if ctx.req.headers.cookie == nil then
        return nil
    end

    for k, v in ctx.req.headers.cookie:gmatch("([^=,; \t]+)=([^,; \t]+)") do
        if k == c then
            return uri_unescape(v)
        end
    end

    return
end

local function url_for_helper(tx, name, args, query)
    return tx:url_for(name, args, query)
end

local function load_template(self, r, format)
    if r.template ~= nil then
        return
    end

    format = format or "html"

    local file

    if r.file ~= nil then
        file = r.file
    elseif r.controller ~= nil and r.action ~= nil then
        file = catfile(
            string.gsub(r.controller, '[.]', '/'),
            sprintf("%s.%s.el", r.action, format)
        )
    else
        errorf("Can not find template for %q", r.path)
    end

    if self.options.cache_templates then
        if self.cache.tpl[ file ] ~= nil then
            return self.cache.tpl[ file ]
        end
    end

    local tpl = catfile(self.options.app_dir, 'templates', file)
    local fh = io.input(tpl)
    local template = fh:read('*a')
    fh:close()

    if self.options.cache_templates then
        self.cache.tpl[ file ] = template
    end

    return template
end

local function render(tx, opts)
    if tx == nil then
        error("Usage: self:render({ ... })")
    end

    local resp = {headers = tx.headers or {}}

    local vars = {}
    if opts then
        -- so you may set or add headers and status right through resp:render()
        if opts.headers then
            if next(resp.headers) then
                fun.each(
                    function(n, val)
                        rawset(resp.headers, n, val)
                    end,
                    opts.headers
                )
            else
                resp.headers = opts.headers
            end
        end

        resp.status  = opts.status

        if opts.text then
            resp.headers['content-type'] = 'text/plain'
            if tx.httpd.options.charset then
                resp.headers['content-type'] =
                    sprintf("%s; charset=%s",
                        resp.headers['content-type'],
                        tx.httpd.options.charset
                    )
            end

            resp.body = tostring(opts.text)
            tx.res = resp

            return
        end

        if opts.json then
            resp.headers['content-type'] = 'application/json'
            if tx.httpd.options.charset then
                resp.headers['content-type'] =
                    sprintf('%s; charset=%s',
                        resp.headers['content-type'],
                        tx.httpd.options.charset
                    )
            end

            resp.body = json.encode(opts.json)
            tx.res = resp

            return
        end

        if opts.data ~= nil then
            resp.body = tostring(opts.data)

            tx.res = resp
            return
        end

        vars = extend(tx.tstash, opts, false)
    end

    local tpl

    local format = tx.tstash.format or "html"

    if tx.endpoint.template then
        tpl = tx.endpoint.template
    else
        tpl = load_template(tx.httpd, tx.endpoint, format)
        if tpl == nil then
            errorf('template is not defined for the route')
        end
    end

    if type(tpl) == 'function' then
        tpl = tpl()
    end

    fun.each(
        function(hname, sub)
            rawset(vars, hname, function(...) return sub(tx, ...) end)
        end,
        tx.httpd.helpers
    )

    vars.action = tx.endpoint.action
    vars.controller = tx.endpoint.controller
    vars.format = format

    resp.body = lib.template(tpl, vars)
    resp.headers['content-type'] = type_by_format(format)

    if tx.httpd.options.charset ~= nil then
        if format == 'html' or format == 'js' or format == 'json' then
            resp.headers['content-type'] = resp.headers['content-type']
                .. '; charset=' .. tx.httpd.options.charset
        end
    end

    tx.res = resp
    return
end

local function iterate(tx, gen, params, state)
    tx.res = { body = { gen = gen, param = params, state = state } }

    return
end

local function redirect_to(tx, name, args, query)
    local location = tx:url_for(name, args, query)
    tx.res = { status = 302, headers = { location = location } }

    return
end

local function access_stash(tx, name, ...)
    if type(tx) ~= 'table' then
        error("usage: ctx:stash('name'[, 'value'])")
    end

    if select('#', ...) > 0 then
        tx.tstash[ name ] = select(1, ...)
    end

    return tx.tstash[ name ]
end

local function url_for_tx(tx, name, args, query)
    if name == 'current' then
        return tx.endpoint:url_for(args, query)
    end

    return tx.httpd:url_for(name, args, query)
end

local function request_json(req)
    local data = req:read_cached()
    local s, result = pcall(json.decode, data)

    if not s then
        errorf(
            "Can't decode json in request %q: %s",
            data,
            tostring(result)
        )
        return
    end

    return result
end

local function request_read(ctx, opts, timeout)
    local remaining = ctx.req._remaining

    if not remaining then
        remaining = tonumber(ctx.req.headers['content-length'])
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

    local buf = ctx.s:read(opts, timeout)
    if buf == nil then
        ctx.req._remaining = 0
        return ''
    end
    remaining = remaining - #buf
    assert(remaining >= 0)
    ctx.req._remaining = remaining
    return buf
end

local function request_read_cached(self)
    if self.cached_data == nil then
        local data = self:read()
        rawset(self, 'cached_data', data)
        return data
    end

    return self.cached_data
end

local function static_file(self, request, format)
    local file = catfile(self.options.app_dir, 'public', request.req.path)
    request.static = true

    if self.options.cache_static and self.cache.static[file] ~= nil then
        local resp = {
            code = 200,
            headers = {
                ['content-type'] = type_by_format(format),
            },
            body = self.cache.static[file]
        }
        request.res = resp

        return
    end

    local s, fh = pcall(io.input, file)

    if not s then
        local resp = { status = 404 }
        request.res = resp

        return
    end

    local body = fh:read('*a')
    io.close(fh)

    if self.options.cache_static then
        self.cache.static[file] = body
    end

    local resp = {
        status = 200,
        headers = {
            ['content-type'] = type_by_format(format),
        },
        body = body
    }

    request.res = resp

    return
end

request_mt = {
    __index = {
        render      = render,
        cookie      = cookie,
        redirect_to = redirect_to,
        iterate     = iterate,
        stash       = access_stash,
        url_for     = url_for_tx,
        content_type= request_content_type,
        request_line= request_line,
        read_cached = request_read_cached,
        query_param = query_param,
        post_param  = post_param,
        param       = param,
        read        = request_read,
        json        = request_json,
        setcookie   = setcookie;
    },
    __tostring = request_tostring;
}

local function is_function(obj)
    return type(obj) == 'function'
end

local function get_request_logger(server_opts, route_opts)
    if route_opts and route_opts.endpoint.log_requests ~= nil then
        if is_function(route_opts.endpoint.log_requests) then
            return route_opts.endpoint.log_requests
        elseif route_opts.endpoint.log_requests == false then
            return log.debug
        end
    end

    if server_opts.log_requests then
        if is_function(server_opts.log_requests) then
            return server_opts.log_requests
        end

        return log.info
    end

    return log.debug
end

local function get_error_logger(server_opts, route_opts)
    if route_opts and route_opts.endpoint.log_errors ~= nil then
        if is_function(route_opts.endpoint.log_errors) then
            return route_opts.endpoint.log_errors
        elseif route_opts.endpoint.log_errors == false then
            return log.debug
        end
    end

    if server_opts.log_errors then
        if is_function(server_opts.log_errors) then
            return server_opts.log_errors
        end

        return log.error
    end

    return log.debug
end

local function handler(self, ctx)
    local format = 'html'

    local pformat = string.match(ctx.req.path, '[.]([^.]+)$')

    if pformat ~= nil then
        format = pformat
    end

    local r = self:match(ctx.req.method, ctx.req.path)

    if r == nil then
        local _ = static_file(self, ctx, format)

        return ctx.res
    else
        local stash = extend(r.stash, { format = format })

        ctx.endpoint = r.endpoint
        ctx.tstash   = stash
    end

    if self.hooks.before_dispatch ~= nil then
        local _ = self.hooks.before_dispatch(ctx)

        if ctx.res then
            return ctx.res
        end
    end

    local resp = r.endpoint.sub(ctx)

    if not ctx.res and resp then
        ctx.res = resp
    end

    if self.hooks.after_dispatch ~= nil then
        self.hooks.after_dispatch(ctx)
    end

    return ctx.res or {}
end

local function normalize_headers(hdrs)
    local res = {}

    fun.each(
        function(h, v)
            rawset(res, h:lower(), v)
        end,
        hdrs
    )

    return res
end

local function parse_request(req)
    local p = lib._parse_request(req)
    if p.error then
        return p
    end
    p.path = uri_unescape(p.path)
    if not p.path:startswith("/") or p.path:find("./", nil, true) then
        p.error = "invalid uri"
        return p
    end
    return p
end

local function process_client(self, s, peer)
    while true do
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

            if hdrs:endswith("\n\n") or hdrs:endswith("\r\n\r\n") then
                break
            end
        end

        if is_eof then
            break
        end

        log.debug("request:\n%s", hdrs)

        local req = parse_request(hdrs)
        local p = {req = req}

        if p.error ~= nil then
            log.error('failed to parse request: %s', p.error)
            s:write(sprintf("HTTP/1.0 400 Bad request\r\n\r\n%s", p.error))
            break
        end
        p.httpd = self
        p.s = s
        p.peer = peer
        setmetatable(p, request_mt)

        if p.req.headers['expect'] == '100-continue' then
            s:write('HTTP/1.0 100 Continue\r\n\r\n')
        end

        local route = self:match(p.req.method, p.req.path)
        local logreq = get_request_logger(self.options, route)
        logreq("%s %s%s", p.req.method, p.req.path,
               p.req.query ~= "" and "?"..p.req.query or "")

        local res, reason = pcall(self.options.handler, self, p)
        p:read() -- skip remaining bytes of request body
        local status, hdrs, body

        if not res then
            status = 500
            hdrs = {}
            local trace = debug.traceback()
            local logerror = get_error_logger(self.options, route)
            logerror('unhandled error: %s\n%s\nrequest:\n%s',
                tostring(reason), trace, tostring(p))
            if self.options.display_errors then
            body =
                  "Unhandled error: " .. tostring(reason) .. "\n"
                .. trace .. "\n\n"
                .. "\n\nRequest:\n"
                .. tostring(p)
            else
                body = "Internal Error"
            end
       elseif type(reason) == 'table' then
            if reason.status == nil then
                status = 200
            elseif type(reason.status) == 'number' then
                status = reason.status
            else
                error('response.status must be a number')
            end
            if reason.headers == nil then
                hdrs = {}
            elseif type(reason.headers) == 'table' then
                hdrs = normalize_headers(reason.headers)
            else
                error('response.headers must be a table')
            end
            body = reason.body
        elseif reason == nil then
            status = 200
            hdrs = {}
        elseif type(reason) == 'number' then
            if reason == DETACHED then
                break
            end
        else
            error('invalid response')
        end

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
            hdrs.server = sprintf('Tarantool http (tarantool v%s)', _TARANTOOL)
        end

        if p.req.proto[1] ~= 1 then
            hdrs.connection = 'close'
        elseif p.broken then
            hdrs.connection = 'close'
        elseif rawget(p.req, 'body') == nil then
            hdrs.connection = 'close'
        elseif p.req.proto[2] == 1 then
            if p.req.headers.connection == nil then
                hdrs.connection = 'keep-alive'
            elseif string.lower(p.req.headers.connection) ~= 'keep-alive' then
                hdrs.connection = 'close'
            else
                hdrs.connection = 'keep-alive'
            end
        elseif p.req.proto[2] == 0 then
            if p.req.headers.connection == nil then
                hdrs.connection = 'close'
            elseif string.lower(p.req.headers.connection) == 'keep-alive' then
                hdrs.connection = 'keep-alive'
            else
                hdrs.connection = 'close'
            end
        end

        local response = {
            "HTTP/1.1 ";
            status;
            " ";
            reason_by_code(status);
            "\r\n";
        };

        fun.each(
            function(k, v)
                if type(v) == 'table' then
                    fun.each(
                        function(sv)
                            table.insert(response, sprintf("%s: %s\r\n", ucfirst(k), sv))
                        end,
                        v
                    )
                else
                    table.insert(response, sprintf("%s: %s\r\n", ucfirst(k), v))
                end
            end,
            hdrs
        )

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
            response = nil
            -- Transfer-Encoding: chunked
            for _, part in gen, param, state do
                part = tostring(part)
                if not s:write(sprintf("%x\r\n%s\r\n", #part, part)) then
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

        if p.req.proto[1] ~= 1 then
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

local function match_route(self, method, route)
    -- route must have '/' at the begin and end
    if string.match(route, '.$') ~= '/' then
        route = route .. '/'
    end
    if string.match(route, '^.') ~= '/' then
        route = '/' .. route
    end

    method = string.upper(method)

    local fit
    local stash = {}

    fun.each(
        function(r)
            if r.method == method or r.method == 'ANY' then
                local m = { string.match(route, r.match) }
                local nfit

                if #m > 0 then
                    if #r.stash > 0 then
                        if #r.stash == #m then
                            nfit = r
                        end
                    else
                        nfit = r
                    end

                    if nfit ~= nil then
                        if fit == nil then
                            fit = nfit
                            stash = m
                        else
                            if #fit.stash > #nfit.stash then
                                fit = nfit
                                stash = m
                            elseif r.method ~= fit.method then
                                if fit.method == 'ANY' then
                                    fit = nfit
                                    stash = m
                                end
                            end
                        end
                    end
                end
            end
        end,
        self.routes
    )

    if fit == nil then
        return fit
    end
    local resstash = {}
    fun.each(
        function(i)
            rawset(resstash, fit.stash[i], stash[i])
        end,
        fun.range(#fit.stash)
    )

    return  { endpoint = fit, stash = resstash }
end

local function set_helper(self, name, sub)
    if sub and type(sub) ~= 'function' then
        errorf("Wrong type for helper function: %s", type(sub))
    end

    self.helpers[ name ] = sub
    return self
end

local function set_hook(self, name, sub)
    if sub and type(sub) ~= 'function' then
        errorf("Wrong type for hook function: %s", type(sub))
    end

    self.hooks[ name ] = sub
    return self
end

local function url_for_route(r, args, query)
    args = args or {}

    local name = r.path

    fun.each(
        function(sn)
            local sv = args[sn] or ''
            name = string.gsub(name, '[*:]' .. sn, sv, 1)
        end,
        r.stash
    )

    if query ~= nil then
        if type(query) == 'table' then
            local sep = '?'
            fun.each(
               function(k, v)
                   name = sprintf("%s%s%s=%s", name, sep, uri_escape(k), uri_escape(v))
                   sep  = '&'
               end,
                query
            )
        else
            name = sprintf("%s?%s", name, query)
        end
    end

    if string.match(name, '^/') == nil then
        return '/' .. name
    else
        return name
    end
end

local function ctx_action(tx)
    local ctx = tx.endpoint.controller
    local action = tx.endpoint.action
    if tx.httpd.options.cache_controllers then
        if tx.httpd.cache[ ctx ] ~= nil then
            if type(tx.httpd.cache[ ctx ][ action ]) ~= 'function' then
                errorf("Controller %q doesn't contain function %q",
                    ctx, action)
            end
            return tx.httpd.cache[ ctx ][ action ](tx)
        end
    end

    local ppath = package.path
    package.path = catfile(tx.httpd.options.app_dir, 'controllers', '?.lua')
                .. ';'
                .. catfile(tx.httpd.options.app_dir,
                    'controllers', '?/init.lua')
    if ppath ~= nil then
        package.path = package.path .. ';' .. ppath
    end

    local st, mod = pcall(require, ctx)
    package.path = ppath
    package.loaded[ ctx ] = nil

    if not st then
        errorf("Can't load module %q: %s", ctx, tostring(mod))
    end

    if type(mod) ~= 'table' then
        errorf("require %q didn't return table", ctx)
    end

    if type(mod[ action ]) ~= 'function' then
        errorf("Controller %q doesn't contain function %q", ctx, action)
    end

    if tx.httpd.options.cache_controllers then
        tx.httpd.cache[ ctx ] = mod
    end

    return mod[action](tx)
end

local possible_methods = {
    GET    = 'GET',
    HEAD   = 'HEAD',
    POST   = 'POST',
    PUT    = 'PUT',
    DELETE = 'DELETE',
    PATCH  = 'PATCH',
}

local function add_route(self, opts, sub)
    if type(opts) ~= 'table' or type(self) ~= 'table' then
        error("Usage: httpd:route({ ... }, function(cx) ... end)")
    end

    opts = extend({method = 'ANY'}, opts, false)

    local ctx
    local action

    if sub == nil then
        sub = render
    elseif type(sub) == 'string' then

        ctx, action = string.match(sub, '(.+)#(.*)')

        if ctx == nil or action == nil then
            errorf("Wrong controller format %q, must be 'module#action'", sub)
        end

        sub = ctx_action

    elseif type(sub) ~= 'function' then
        errorf("wrong argument: expected function, but received %s",
            type(sub))
    end

    opts.method = possible_methods[string.upper(opts.method)] or 'ANY'

    if opts.path == nil then
        error("path is not defined")
    end

    opts.controller = ctx
    opts.action = action
    opts.match = opts.path
    opts.match = string.gsub(opts.match, '[-]', "[-]")

    local estash = {  }
    local stash = {  }
    while true do
        local name = string.match(opts.match, ':([%a_][%w_]*)')
        if name == nil then
            break
        end
        if estash[name] then
            errorf("duplicate stash: %s", name)
        end
        estash[name] = true
        opts.match = string.gsub(opts.match, ':[%a_][%w_]*', '([^/]-)', 1)

        table.insert(stash, name)
    end
    while true do
        local name = string.match(opts.match, '[*]([%a_][%w_]*)')
        if name == nil then
            break
        end
        if estash[name] then
            errorf("duplicate stash: %s", name)
        end
        estash[name] = true
        opts.match = string.gsub(opts.match, '[*][%a_][%w_]*', '(.-)', 1)

        table.insert(stash, name)
    end

    if string.match(opts.match, '.$') ~= '/' then
        opts.match = opts.match .. '/'
    end
    if string.match(opts.match, '^.') ~= '/' then
        opts.match = '/' .. opts.match
    end

    opts.match = '^' .. opts.match .. '$'

    estash = nil

    opts.stash = stash
    opts.sub = sub
    opts.url_for = url_for_route

    if opts.log_requests ~= nil then
        if type(opts.log_requests) ~= 'function' and type(opts.log_requests) ~= 'boolean' then
            error("'log_requests' option should be a function or a boolean")
        end
    end

    if opts.log_errors ~= nil then
        if type(opts.log_errors) ~= 'function' and type(opts.log_errors) ~= 'boolean' then
            error("'log_errors' option should be a function or a boolean")
        end
    end

    if opts.name ~= nil then
        if opts.name == 'current' then
            error("Route can not have name 'current'")
        end
        if self.iroutes[ opts.name ] ~= nil then
            errorf("Route with name %q is already exists", opts.name)
        end
        table.insert(self.routes, opts)
        self.iroutes[ opts.name ] = #self.routes
    else
        table.insert(self.routes, opts)
    end
    return self
end

local function url_for_httpd(httpd, name, args, query)
    local idx = httpd.iroutes[ name ]

    if idx ~= nil then
        return httpd.routes[ idx ]:url_for(args, query)
    end

    if string.match(name, '^/') == nil then
        if string.match(name, '^https?://') ~= nil then
            return name
        else
            return '/' .. name
        end
    end

    return name
end

local function httpd_start(self)
    if type(self) ~= 'table' then
        error("httpd: usage: httpd:start()")
    end

    local server = socket.tcp_server(
        self.host,
        self.port,
        {
            name = 'http',
            handler = function(...)
                          local _ = process_client(self, ...)
                      end
        }
    )
    if server == nil then
        error(sprintf("Can't create tcp_server: %s", errno.strerror()))
    end

    rawset(self, 'is_run', true)
    rawset(self, 'tcp_server', server)
    rawset(self, 'stop', httpd_stop)

    return self
end

local exports = {
    DETACHED = DETACHED,

    new = function(host, port, options)
        if options == nil then
            options = {}
        end
        if type(options) ~= 'table' then
            errorf("options must be table not %q", type(options))
        end
        local default = {
            max_header_size     = 4096,
            header_timeout      = 100,
            handler             = handler,
            app_dir             = '.',
            charset             = 'utf-8',
            cache_templates     = true,
            cache_controllers   = true,
            cache_static        = true,
            log_requests        = true,
            log_errors          = true,
            display_errors      = true,
        }

        local self = {
            host    = host,
            port    = port,
            is_run  = false,
            stop    = httpd_stop,
            start   = httpd_start,
            options = extend(default, options, true),

            routes  = {  },
            iroutes = {  },
            helpers = {
                url_for = url_for_helper,
            },
            hooks   = {  },

            -- methods
            route   = add_route,
            match   = match_route,
            helper  = set_helper,
            hook    = set_hook,
            url_for = url_for_httpd,

            -- caches
            cache   = {
                tpl         = {},
                ctx         = {},
                static      = {},
            },
        }

        return self
    end
}

return exports
