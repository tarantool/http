local fs = require('http.router.fs')
local middleware = require('http.router.middleware')
local matching = require('http.router.matching')

local bless_request = require('http.router.request').bless

local utils = require('http.utils')
local tsgi = require('http.tsgi')

local checks = require('checks')

local function uri_file_extension(s, default)
    -- cut from last dot till the end
    local ext = string.match(s, '[.]([^.]+)$')
    if ext ~= nil then
        return ext
    end
    return default
end

-- TODO: move to router.request?
local function url_for_helper(tx, name, args, query)
    return tx:url_for(name, args, query)
end

local function main_endpoint_middleware(request)
    local self = request:router()
    local format = uri_file_extension(request:path(), 'html')
    local r = request[tsgi.KEY_ROUTE]

    if r == nil then
        return fs.static_file(self, request, format)
    end
    local stash = utils.extend(r.stash, { format = format })
    request.endpoint = r.endpoint  -- THIS IS ROUTE, BUT IS NAMED `ENDPOINT`! OH-MY-GOD!
    request.tstash   = stash
    return r.endpoint.handler(request)
end

local function populate_chain_with_middleware(env, middleware_obj)
    local filter = matching.transform_filter({
        path = env:path(),
        method = env:method()
    })
    for _, m in pairs(middleware_obj:ordered()) do
        if matching.matches(m, filter) then
            tsgi.push_back_handler(env, m.handler)
        end
    end
end

local function dispatch_middleware(req)
    local self = req:router()

    local r = self:match(req:method(), req:path())
    req[tsgi.KEY_ROUTE] = r

    populate_chain_with_middleware(req, self.middleware)

    -- finally, add user specified handler
    tsgi.push_back_handler(req, main_endpoint_middleware)

    return req:next()
end

local function router_handler(self, env)
    -- attach a metatable with helper methods
    -- to otherwise raw TSGI table
    -- (e.g. to be able to write request:path() instead of request['PATH_INFO'])
    local request = bless_request(env, self)

    request:set_router(self)

    -- set-up middleware chain
    tsgi.init_handlers(request)

    populate_chain_with_middleware(request, self.preroute_middleware)

    -- add routing
    tsgi.push_back_handler(request, dispatch_middleware)

    -- execute middleware chain from first
    return request:next()
end

-- TODO: `route` is not route, but path...
local function match_route(self, method, route)
    local filter = matching.transform_filter({
        method = method,
        path = route
    })

    local best_match = nil
    for _, r in pairs(self.routes) do
        local ok, match = matching.matches(r, filter)
        if ok and matching.better_than(match, best_match) then
            best_match = match
        end
    end

    if best_match == nil or best_match.route == nil then
        return nil
    end

    local resstash = {}
    for i = 1, #best_match.route.stash do
        resstash[best_match.route.stash[i]] = best_match.stash[i]
    end
    return {endpoint = best_match.route, stash = resstash}
end

local function set_helper(self, name, handler)
    if handler == nil or type(handler) == 'function' then
        self.helpers[ name ] = handler
        return self
    end
    utils.errorf("Wrong type for helper function: %s", type(handler))
end

local function set_hook(self, name, handler)
    if handler == nil or type(handler) == 'function' then
        self.hooks[ name ] = handler
        return self
    end
    utils.errorf("Wrong type for hook function: %s", type(handler))
end

local function url_for_route(r, args, query)
    if args == nil then
        args = {}
    end
    local name = r.path
    for _, sn in pairs(r.stash) do
        local sv = args[sn]
        if sv == nil then
            sv = ''
        end
        name = string.gsub(name, '[*:]' .. sn, sv, 1)
    end

    if query ~= nil then
        if type(query) == 'table' then
            local sep = '?'
            for k, v in pairs(query) do
                name = name .. sep .. utils.uri_escape(k) .. '=' .. utils.uri_escape(v)
                sep = '&'
            end
        else
            name = name .. '?' .. query
        end
    end

    if string.match(name, '^/') == nil then
        return '/' .. name
    else
        return name
    end
end

local possible_methods = {
    GET    = 'GET',
    HEAD   = 'HEAD',
    POST   = 'POST',
    PUT    = 'PUT',
    DELETE = 'DELETE',
    PATCH  = 'PATCH',
}

local function use_middleware(self, handler, opts)
    checks('table', 'function', {
        path = '?string',
        method = '?string|table',
        name = '?string',
        preroute = '?boolean',
        before = '?string|table',
        after = '?string|table',
    })
    opts = table.deepcopy(opts)
    opts.handler = handler

    local uuid = require('uuid')
    opts.path = opts.path or '/.*'
    opts.method = opts.method or 'ANY'
    opts.name = opts.name or uuid.str()
    opts.before = opts.before or {}
    opts.after = opts.after or {}

    for _, order_key in ipairs({'before', 'after'}) do
        local opt = opts[order_key]
        assert(type(opt) ~= 'string' or type(opt) ~= 'table',
               ('%s must be a table of strings or a string'):format(order_key))
        if type(opt) == 'table' then
            for _, name in ipairs(opt) do
                local fmt = ('%s of table type, must contain strings, got %s')
                    :format(order_key, type(opt[name]))
                assert(type(opt[name]) == 'string', fmt)
            end
        end
    end

    -- helpers for matching and retrieving pattern words
    opts.match, opts.stash = matching.transform_pattern(opts.path)

    if opts.preroute == true then
        return self.preroute_middleware:use(opts)
    end
    return self.middleware:use(opts)
end

local function add_route(self, opts, handler)
    if type(opts) ~= 'table' or type(self) ~= 'table' then
        error("Usage: router:route({ ... }, function(cx) ... end)")
    end

    opts = utils.extend({method = 'ANY'}, opts, false)

    local ctx
    local action

    if handler == nil then
        handler = fs.render
    elseif type(handler) == 'string' then

        ctx, action = string.match(handler, '(.+)#(.*)')

        if ctx == nil or action == nil then
            utils.errorf("Wrong controller format '%s', must be 'module#action'", handler)
        end

        handler = fs.ctx_action

    elseif type(handler) ~= 'function' then
        utils.errorf("wrong argument: expected function, but received %s",
            type(handler))
    end

    opts.method = possible_methods[string.upper(opts.method)] or 'ANY'

    if opts.path == nil then
        error("path is not defined")
    end

    opts.controller = ctx
    opts.action = action

    opts.match, opts.stash = matching.transform_pattern(opts.path)
    opts.handler = handler
    opts.url_for = url_for_route

    -- register new route in a router
    if opts.name ~= nil then
        if opts.name == 'current' then
            error("Route can not have name 'current'")
        end
        if self.iroutes[ opts.name ] ~= nil then
            utils.errorf("Route with name '%s' is already exists", opts.name)
        end
        table.insert(self.routes, opts)
        self.iroutes[ opts.name ] = #self.routes
    else
        table.insert(self.routes, opts)
    end

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

    return self
end

local function url_for(self, name, args, query)
    local idx = self.iroutes[ name ]
    if idx ~= nil then
        return self.routes[ idx ]:url_for(args, query)
    end

    if string.match(name, '^/') == nil then
        if string.match(name, '^https?://') ~= nil then
            return name
        else
            return '/' .. name
        end
    else
        return name
    end
end

local exports = {
    new = function(options)
        if options == nil then
            options = {}
        end
        if type(options) ~= 'table' then
            utils.errorf("options must be table not '%s'", type(options))
        end

        local default = {
            max_header_size     = 4096,
            header_timeout      = 100,
            app_dir             = '.',
            charset             = 'utf-8',
            cache_templates     = true,
            cache_controllers   = true,
            cache_static        = true,
        }

        local self = {
            options = utils.extend(default, options, true),

            routes      = {  },                      -- routes array
            iroutes     = {  },                      -- routes by name
            middleware = middleware.new(),           -- new middleware
            preroute_middleware = middleware.new(),  -- new middleware (preroute)
            helpers = {                              -- for use in templates
                url_for = url_for_helper,
            },
            hooks       = {  },                      -- middleware

            -- methods
            use     = use_middleware,                -- new middleware
            route   = add_route,                     -- add route
            helper  = set_helper,                    -- for use in templates
            hook    = set_hook,                      -- middleware
            url_for = url_for,

            -- private
            match   = match_route,

            -- caches
            cache   = {
                tpl         = {},
                ctx         = {},
                static      = {},
            },
        }

        -- make router object itself callable
        --
        -- BE AWARE:
        -- 1) router(env) is valid, but
        -- 2) type(router) == 'table':
        --
        return setmetatable(self, {
            __call = router_handler,
        })
    end
}

return exports
