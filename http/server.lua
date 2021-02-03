local v2_server = require('http.server.init')
local v2_router = require('http.router')
local v1_server_adapter = require('http.v1_server_adapter')
local log = require('log')
local API_VERSIONS = require('http.api_versions')

local function httpd_stop(self)
    return self.__v2_server:stop()
end

local function httpd_set_router(self, router)
    return self.__v2_server:set_router(router)
end

local function httpd_router(self)
    return self.__v2_server:router()
end

local function __set_v1_handler(self, handler)
    return self.__v1_server_adapter:set_handler(handler)
end

local function server_route(self, opts, handler)
    self.__v1_server_adapter:route(opts, handler)
    return self
end

local function server_match(self, method, route)
    return self.__v1_server_adapter:match(method, route)
end

local function server_helper(self, name, handler)
    self.__v1_server_adapter:helper(name, handler)
    return self
end

local function server_hook(self, name, handler)
    self.__v1_server_adapter:hook(name, handler)
    return self
end

local function server_url_for(self, name, args, query)
    return self.__v1_server_adapter:url_for(name, args, query)
end

local server_fields_set = {
    host        = true,
    port        = true,
    tcp_server  = true,
    is_run      = true,
}

local router_fields_set = {
    routes      = true,
    iroutes     = true,
    helpers     = true,
    hooks       = true,
    cache       = true,
}

local v1_server_options_set = {
    log_requests        = true,
    log_errors          = true,
    display_errors      = true,
}

local v1_router_options_set = {
    max_header_size     = true,
    header_timeout      = true,
    app_dir             = true,
    charset             = true,
    cache_templates     = true,
    cache_controllers   = true,
    cache_static        = true,
}

local function is_v1_only_option(option_name)
    return v1_router_options_set[option_name] ~= nil or option_name == 'handler'
end

local function is_v2_only_option(option_name)
    return option_name == 'router'
end

local function get_router_options_for_v1(options)
    local result = {}
    for option_name, _ in pairs(v1_router_options_set) do
        result[option_name] = options[option_name]
    end
    return result
end

local function get_v2_server_options(options)
    return {
        router              = options.router,
        log_requests        = options.log_requests,
        log_errors          = options.log_errors,
        display_errors      = options.display_errors,
    }
end

local function httpd_start(self)
    if self.__api_version == API_VERSIONS.UNKNOWN then
        local router = v2_router.new(get_router_options_for_v1(self.options))
        self.__api_version = API_VERSIONS.V1
        self.__v2_server:set_router(router)
    end
    return self.__v2_server:start()
end

local function v1_method_decorator(method, method_name)
    return function(self, ...)
        if self.__api_version == API_VERSIONS.V1 then
            return method(self, ...)
        elseif self.__api_version == API_VERSIONS.V2 then
            error(
                ('":%s" method does not supported. Use http-v2 api https://github.com/tarantool/http/tree/master.'):
                format(method_name)
            )
        elseif self.__api_version == API_VERSIONS.UNKNOWN then
            log.warn("You are using v1 API")
            local router = v2_router.new(get_router_options_for_v1(self.options))
            -- self.__api_version = API_VERSIONS.V1 should be below because it would try get option from router,
            -- but it not created yet
            self.__api_version = API_VERSIONS.V1
            self.__v2_server:set_router(router)
            return method(self, ...)
        end
    end
end

local function v2_method_decorator(method, method_name)
    return function(self, ...)
        if self.__api_version == API_VERSIONS.V1 then
            error(
                ('":%s" method does not supported. Use http-v1 api https://github.com/tarantool/http/tree/1.1.0.'):
                format(method_name)
            )
        elseif self.__api_version == API_VERSIONS.V2 then
            return method(self, ...)
        elseif self.__api_version == API_VERSIONS.UNKNOWN then
            self.__api_version = API_VERSIONS.V2
            return method(self, ...)
        end
    end
end

local function __create_server_options(self)
    local options = {}

    local mt = {
        __newindex = function(_, key, value)
            if self.__api_version == API_VERSIONS.V1 then
                if v1_server_options_set[key] ~= nil then
                    self.__v2_server.options[key] = value
                elseif v1_router_options_set[key] ~= nil then
                    self.__v2_server:router().options[key] = value
                elseif key == 'handler' then
                    self:__set_v1_handler(value)
                else
                    options[key] = value
                end
            elseif self.__api_version == API_VERSIONS.V2 then
                self.__v2_server.options[key] = value
            elseif self.__api_version == API_VERSIONS.UNKNOWN then
                if is_v1_only_option(key) then
                    log.warn("You are using v1 API")
                    self.__api_version = API_VERSIONS.V1
                    options[key] = value
                    local router = v2_router.new(get_router_options_for_v1(options))
                    self.__v2_server:set_router(router)
                    if key == 'handler' then
                        self:__set_v1_handler(value)
                    end
                elseif is_v2_only_option(key) then
                    self.__api_version = API_VERSIONS.V2
                else
                    options[key] = value
                end
            end
        end,
        __index = function(_, key)
            if self.__api_version == API_VERSIONS.V1 then
                if v1_server_options_set[key] ~= nil then
                    return self.__v2_server.options[key]
                elseif v1_router_options_set[key] ~= nil then
                    return self.__v2_server:router().options[key]
                else
                    return options[key]
                end
            elseif self.__api_version == API_VERSIONS.V2 then
                return self.__v2_server.options[key]
            else
                return options[key]
            end
        end
    }
    return setmetatable({}, mt)
end

local function __set_options(self, options_from_user)
    local server_options = self:__create_server_options()
    for option_name, option_value in pairs(options_from_user) do
        server_options[option_name] = option_value
    end
    self.options = server_options
end

local function __set_server_metatable(self)
    local server = {}
    local server_mt = {
        __newindex = function(_, key, value)
            if self.__api_version == API_VERSIONS.V1 then
                if server_fields_set[key] then
                    self.__v2_server[key] = value
                elseif router_fields_set[key] then
                    self.__v2_server:router()[key] = value
                else
                    server[key] = value
                end
            elseif self.__api_version == API_VERSIONS.V2 then
                self.__v2_server[key] = value
            elseif self.__api_version == API_VERSIONS.UNKNOWN then
                if server_fields_set[key] then
                    self.__v2_server[key] = value
                else
                    error('API version is unknown, set version via method call or option set')
                end
            end
        end,
        __index = function(_, key)
            if self.__api_version == API_VERSIONS.V1 then
                if server_fields_set[key] then
                    return self.__v2_server[key]
                elseif router_fields_set[key] then
                    return self.__v2_server:router()[key]
                else
                    return server[key]
                end
            elseif self.__api_version == API_VERSIONS.V2 then
                return self.__v2_server[key]
            elseif self.__api_version == API_VERSIONS.UNKNOWN then
                if server_fields_set[key] then
                    return self.__v2_server[key]
                end
                error('API version is unknown, set version via method call or option set')
            end
        end
    }
    setmetatable(self, server_mt)
end

local function new(host, port, options)
    if options == nil then
        options = {}
    end

    local api_version = API_VERSIONS.UNKNOWN

    local server = v2_server.new(host, port, get_v2_server_options(options))

    local obj = {
        -- private
        __api_version = api_version,
        __v2_server = server,
        __set_v1_handler = __set_v1_handler,
        __v1_server_adapter = v1_server_adapter.new(server),
        __create_server_options = __create_server_options,
        __set_options = __set_options,
        __set_server_metatable = __set_server_metatable,

        -- common
        stop       = httpd_stop,
        start      = httpd_start,
        options    = nil,

        -- http 2 only
        set_router = v2_method_decorator(httpd_set_router, 'set_router'),
        router     = v2_method_decorator(httpd_router, 'router'),

        -- http1 only
        route = v1_method_decorator(server_route, 'route'),
        match = v1_method_decorator(server_match, 'match'),
        helper = v1_method_decorator(server_helper, 'helper'),
        hook = v1_method_decorator(server_hook, 'hook'),
        url_for = v1_method_decorator(server_url_for, 'url_for'),
    }
    obj:__set_options(options)
    obj:__set_server_metatable()
    return obj
end

return {
    VERSION = v2_server.VERSION,
    DETACHED = v2_server.DETACHED,
    new = new,
}
