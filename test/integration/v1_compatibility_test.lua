local t = require('luatest')
local g = t.group()
local http_server = require('http.server')
local http_router = require('http.router')
local helper = require('test.helper')
local http_client = require('http.client')
local API_VERSIONS = require('http.api_versions')

g.server = nil
local function set_server(options)
    g.server = http_server.new(helper.base_host, helper.base_port, options)
    g.server:start()
end

g.after_each(function()
    if g.server ~= nil and g.server.__v2_server.is_run then
        g.server:stop()
    end
end)

g.test_handler_option_on_server_creation = function()
    set_server({handler = function() return {status = 200, body = 'Universal handler'} end})
    g.server:route({ path = '/get', method = 'GET' }, function() return { status = 200, body = 'GET' } end)
    g.server:route({ path = '/post', method = 'POST' }, function() return { status = 200, body = 'POST' } end)
    g.server:route({ path = '/put', method = 'PUT' }, function() return { status = 200, body = 'PUT' } end)
    g.server:route({ path = '/', mathod = 'ANY'}, function() return { status = 200, body = 'ANY' } end)

    t.assert_equals(http_client.get(helper.base_uri .. 'get').body, 'Universal handler')
    t.assert_equals(http_client.get(helper.base_uri .. 'post').body, 'Universal handler')
    t.assert_equals(http_client.get(helper.base_uri .. 'put').body, 'Universal handler')
    t.assert_equals(http_client.get(helper.base_uri).body, 'Universal handler')
end

g.test_handler_option_on_option_set = function()
    set_server()
    g.server:route({ path = '/get', method = 'GET' }, function() return { status = 200, body = 'GET' } end)
    g.server:route({ path = '/post', method = 'POST' }, function() return { status = 200, body = 'POST' } end)
    g.server:route({ path = '/put', method = 'PUT' }, function() return { status = 200, body = 'PUT' } end)
    g.server:route({ path = '/', mathod = 'ANY'}, function() return { status = 200, body = 'ANY' } end)

    g.server.options.handler = function() return {status = 200, body = 'Universal handler'} end

    t.assert_equals(http_client.get(helper.base_uri .. 'get').body, 'Universal handler')
    t.assert_equals(http_client.get(helper.base_uri .. 'post').body, 'Universal handler')
    t.assert_equals(http_client.get(helper.base_uri .. 'put').body, 'Universal handler')
    t.assert_equals(http_client.get(helper.base_uri).body, 'Universal handler')
end

g.test_set_version_by_creation = function()
    local function check_version_by_creation(options, desired_version)
        local httpd = http_server.new(helper.base_host, helper.base_port, options)
        t.assert_equals(httpd.__api_version, desired_version)
    end

    check_version_by_creation({max_header_size = 42}, API_VERSIONS.V1)
    check_version_by_creation({handler = function() end}, API_VERSIONS.V1)
    check_version_by_creation({app_dir = 'test'}, API_VERSIONS.V1)
    check_version_by_creation({charset = 'utf-8'}, API_VERSIONS.V1)
    check_version_by_creation({cache_templates = true}, API_VERSIONS.V1)
    check_version_by_creation({cache_controllers = false}, API_VERSIONS.V1)
    check_version_by_creation({cache_static = true}, API_VERSIONS.V1)
    check_version_by_creation({log_requests = true}, API_VERSIONS.UNKNOWN)
    check_version_by_creation({log_errors = true}, API_VERSIONS.UNKNOWN)
    check_version_by_creation({display_errors = false}, API_VERSIONS.UNKNOWN)
    check_version_by_creation({
        display_errors = false,
        log_errors = true,
        max_header_size = 9000
    }, API_VERSIONS.V1)
end

g.test_set_version_by_option_set = function()
    local function check_version_by_option_set(old_options, new_options, desired_version)
        local httpd = http_server.new(helper.base_host, helper.base_port, old_options)
        for option_name, option in pairs(new_options) do
            httpd.options[option_name] = option
        end
        t.assert_equals(httpd.__api_version, desired_version)
    end
    check_version_by_option_set({}, {max_header_size = 42}, API_VERSIONS.V1)
    check_version_by_option_set({log_errors = true}, {handler = function() end}, API_VERSIONS.V1)
    check_version_by_option_set(
        {display_errors = false, log_errors = true}, {log_requests = true}, API_VERSIONS.UNKNOWN
    )
    check_version_by_option_set({}, {router = function() end}, API_VERSIONS.V2)
    check_version_by_option_set({max_header_size = 42}, {router = function() end}, API_VERSIONS.V1)
    check_version_by_option_set(
        {display_errors = true, log_errors = true, log_requests = true}, {max_header_size = 42}, API_VERSIONS.V1
    )
end

g.test_set_version_by_method = function()
    local function check_set_version_by_method(options, method_name, method_args, desired_version)
        local httpd = http_server.new(helper.base_host, helper.base_port, options)
        t.assert_equals(httpd.__api_version,  API_VERSIONS.UNKNOWN)
        httpd[method_name](httpd, unpack(method_args))
        t.assert_equals(httpd.__api_version,  desired_version)
    end

    check_set_version_by_method({}, 'set_router', {http_router.new()}, API_VERSIONS.V2)
    check_set_version_by_method({log_errors = true}, 'set_router', {http_router.new()}, API_VERSIONS.V2)
    check_set_version_by_method(
        {display_errors = true, log_errors = true, log_requests = true},
        'set_router', {http_router.new()}, API_VERSIONS.V2
    )
    check_set_version_by_method({}, 'router', {},  API_VERSIONS.V2)
    check_set_version_by_method(
        {display_errors = true, log_errors = true, log_requests = true}, 'router', {}, API_VERSIONS.V2
    )

    check_set_version_by_method({}, 'route', {{path = '/'}, function() end}, API_VERSIONS.V1)
    check_set_version_by_method({}, 'match', {'GET', '/'}, API_VERSIONS.V1)
    check_set_version_by_method({}, 'helper', {'helper', function() end}, API_VERSIONS.V1)
    check_set_version_by_method({}, 'hook', {'hook', function() end}, API_VERSIONS.V1)
    check_set_version_by_method({}, 'url_for', {'/'}, API_VERSIONS.V1)
end

g.test_v2_method_on_v1_api = function()
    local function check_error_on_v2_method_call(method_name, method_args, error_string)
        local httpd = http_server.new(helper.base_host, helper.base_port, {max_header_size = 9000})
        local ok, err = pcall(httpd[method_name], httpd, unpack(method_args))
        t.assert_not(ok)
        t.assert_str_contains(err, error_string)
    end
    check_error_on_v2_method_call(
        'set_router', {http_router.new()},
        '":set_router" method does not supported. Use http-v1 api https://github.com/tarantool/http/tree/1.1.0'
    )
    check_error_on_v2_method_call(
        'router', {},
        '":router" method does not supported. Use http-v1 api https://github.com/tarantool/http/tree/1.1.0'
    )
end

g.test_v1_method_on_v2_api = function()
    local function check_error_on_v1_method_call(method_name, method_args, error_string)
        local httpd = http_server.new(helper.base_host, helper.base_port)
        httpd:set_router(http_router.new())
        local ok, err = pcall(httpd[method_name], httpd, unpack(method_args))
        t.assert_not(ok)
        t.assert_str_contains(err, error_string)
    end
    check_error_on_v1_method_call('route', {{path = '/'}, function() end},
        ':route" method does not supported. Use http-v2 api https://github.com/tarantool/http/tree/master'
    )
    check_error_on_v1_method_call('match', {'GET', '/'},
        ':match" method does not supported. Use http-v2 api https://github.com/tarantool/http/tree/master'
    )
    check_error_on_v1_method_call(
        'helper', {'helper', function() end},
        ':helper" method does not supported. Use http-v2 api https://github.com/tarantool/http/tree/master'
    )
    check_error_on_v1_method_call(
        'hook', {'hook', function() end},
        ':hook" method does not supported. Use http-v2 api https://github.com/tarantool/http/tree/master'
    )
    check_error_on_v1_method_call(
        'url_for', {'/'},
        ':url_for" method does not supported. Use http-v2 api https://github.com/tarantool/http/tree/master'
    )
end

g.test_v1_fields_access_by_version = function()
    local function check_v1_field_get_from_v1(field_name)
        local httpd_v1 = http_server.new(helper.base_host, helper.base_port, {max_header_size = 42})
        httpd_v1:start()
        t.assert_is_not(httpd_v1[field_name], nil, ("tried to get %s"):format(field_name))
        httpd_v1:stop()
    end

    local function check_v1_field_get_from_v2(field_name, is_nil)
        local httpd_v2 = http_server.new(helper.base_host, helper.base_port)
        httpd_v2:set_router(http_router.new())
        httpd_v2:start()
        if is_nil then
            t.assert_is(httpd_v2[field_name], nil, ("tried to get %s"):format(field_name))
        else
            t.assert_is_not(httpd_v2[field_name], nil, ("tried to get %s"):format(field_name))
        end

        httpd_v2:stop()
    end

    local function check_v1_field_get_from_unknown(field_name, is_raise)
        local httpd_unknown = http_server.new(helper.base_host, helper.base_port)
        local ok, err = pcall(function() return httpd_unknown[field_name] end)
        if is_raise then
            t.assert_not(ok, ("tried to get %s"):format(field_name))
            t.assert_str_contains(err, "API version is unknown, set version via method call or option set")
        else
            t.assert(ok, ("tried to get %s"):format(field_name))
        end
    end

    local function check_v1_field_set_to_v1(field_name, field_value, is_server_field)
        local httpd_v1 = http_server.new(helper.base_host, helper.base_port, {max_header_size = 42})
        httpd_v1[field_name] = field_value
        if is_server_field then
            t.assert_equals(httpd_v1.__v2_server[field_name], field_value, ("tried to set %s"):format(field_name))
        else
            t.assert_equals(
                httpd_v1.__v2_server:router()[field_name], field_value, ("tried to set %s"):format(field_name)
            )
        end
    end

    local function check_v1_field_set_to_v2(field_name, field_value)
        local httpd_v2 = http_server.new(helper.base_host, helper.base_port)
        httpd_v2:set_router(http_router.new())
        httpd_v2[field_name] = field_value
        t.assert_equals(httpd_v2.__v2_server[field_name], field_value, ("tried to set %s"):format(field_name))
    end

    local function check_v1_field_set_to_unknown(field_name, field_value, is_raise)
        local httpd_unknown = http_server.new(helper.base_host, helper.base_port)
        local ok, err = pcall(function() httpd_unknown[field_name] = field_value end)
        if is_raise then
            t.assert_not(ok, ("tried to set %s"):format(field_name))
            t.assert_str_contains(err, "API version is unknown, set version via method call or option set")
        else
            t.assert(ok, ("tried to set %s"):format(field_name))
        end
    end

    local v1_only_fields = {'routes', 'iroutes', 'helpers', 'hooks', 'cache'}
    local v1_v2_fields = {'host', 'port', 'tcp_server', 'is_run'}

    for _, field_name in ipairs(v1_only_fields) do
        check_v1_field_get_from_v1(field_name)
    end
    for _, field_name in ipairs(v1_v2_fields) do
        check_v1_field_get_from_v1(field_name)
    end

    for _, field_name in ipairs(v1_only_fields) do
        check_v1_field_get_from_v2(field_name, true)
    end
    for _, field_name in ipairs(v1_v2_fields) do
        check_v1_field_get_from_v2(field_name, false)
    end

    for _, field_name in ipairs(v1_only_fields) do
        check_v1_field_get_from_unknown(field_name, true)
    end
    for _, field_name in ipairs(v1_v2_fields) do
        check_v1_field_get_from_unknown(field_name, false)
    end

    for _, field_name in ipairs(v1_only_fields) do
        check_v1_field_set_to_v1(field_name, 42, false)
    end
    for _, field_name in ipairs(v1_v2_fields) do
        check_v1_field_set_to_v1(field_name, 42, true)
    end

    for _, field_name in ipairs(v1_only_fields) do
        check_v1_field_set_to_v2(field_name, 42)
    end
    for _, field_name in ipairs(v1_v2_fields) do
        check_v1_field_set_to_v2(field_name, 42)
    end

    for _, field_name in ipairs(v1_only_fields) do
        check_v1_field_set_to_unknown(field_name, 42, true)
    end
    for _, field_name in ipairs(v1_v2_fields) do
        check_v1_field_set_to_unknown(field_name, 42, false)
    end
end

g.test_set_version_on_start = function()
    local function check_version_on_start(options, desired_version)
        set_server(options)
        t.assert_equals(g.server.__api_version, desired_version)
        g.server:stop()
    end
    check_version_on_start({}, API_VERSIONS.V1)
    check_version_on_start({display_errors = true}, API_VERSIONS.V1)
    check_version_on_start({log_errors = true}, API_VERSIONS.V1)
    check_version_on_start({max_header_size = 42}, API_VERSIONS.V1)
end
