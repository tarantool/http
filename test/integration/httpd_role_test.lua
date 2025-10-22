local t = require('luatest')
local treegen = require('luatest.treegen')
local server = require('luatest.server')
local fun = require('fun')
local yaml = require('yaml')
local fio = require('fio')
local http_client = require('http.client').new()


local helpers = require('test.helpers')

local LOG_LEVELS = {
    INFO = 5,
    VERBOSE = 6,
    DEBUG = 7,
}

local g = t.group(nil, t.helpers.matrix({
    use_tls = {true, false},
}))

local ssl_data_dir = fio.abspath(fio.pathjoin(helpers.get_testdir_path(), "ssl_data"))

local config = {
    credentials = {
        users = {
            guest = {
                roles = {'super'},
            },
        },
    },
    iproto = {
        listen = {{uri = 'unix/:./{{ instance_name }}.iproto'}},
    },
    groups = {
        ['group-001'] = {
            replicasets = {
                ['replicaset-001'] = {
                    roles = {
                        'roles.httpd',
                        'test.mocks.mock_role',
                    },
                    roles_cfg = {
                        ['roles.httpd'] = {
                            default = {
                                listen = 13000,
                                log_requests = 'info',
                            },
                            additional = {
                                listen = 13001,
                                log_requests = 'verbose',
                            },
                            additional_debug = {
                                listen = 13002,
                                log_requests = 'debug',
                            },
                        },
                        ['test.mocks.mock_role'] = {
                            {
                                id = 1,
                            },
                            {
                                id = 2,
                                name = 'additional',
                            },
                            {
                                id = 3,
                                name = 'additional_debug',
                            }
                        },
                    },
                    instances = {
                        ['instance-001'] = {},
                    },
                },
            },
        },
    },
}

local tls_config = table.deepcopy(config)
tls_config.groups['group-001'].replicasets['replicaset-001'].roles_cfg['roles.httpd'].default
    .ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt')

tls_config.groups['group-001'].replicasets['replicaset-001'].roles_cfg['roles.httpd'].default
    .ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.enc.key')

tls_config.groups['group-001'].replicasets['replicaset-001'].roles_cfg['roles.httpd'].default
    .ssl_password_file = fio.pathjoin(ssl_data_dir, 'passwords')

g.before_each(function(cg)
    helpers.skip_if_not_tarantool3()

    local dir = treegen.prepare_directory({}, {})

    local cfg = config
    if cg.params.use_tls then
        cfg = tls_config
    end

    local config_file = treegen.write_file(dir, 'config.yaml',
        yaml.encode(cfg))
    local opts = {config_file = config_file, chdir = dir}
    cg.server = server:new(fun.chain(opts, {alias = 'instance-001'}):tomap())
    helpers.update_lua_env_variables(cg.server)

    cg.server:start()
end)

g.after_each(function(cg)
    helpers.teardown(cg.server)
end)

g.test_httpd_role_usage = function(cg)
    if cg.params.use_tls then
        local resp = http_client:get('https://localhost:13000/ping', {
            ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt')
        })
        t.assert_equals(resp.status, 200, 'response not 200')
        t.assert_equals(resp.body, 'pong')
    end

    -- We can use https only for one endpoind due to we haven't publish separate
    -- certificates for it.
    local resp = http_client:get('http://localhost:13001/ping')
    t.assert_equals(resp.status, 200, 'response not 200')
    t.assert_equals(resp.body, 'pong')

    t.assert_equals(cg.server:eval(
        'return require("test.mocks.mock_role").get_server_port(1)'
    ), 13000)
    t.assert_equals(cg.server:eval(
        'return require("test.mocks.mock_role").get_server_port(2)'
    ), 13001)
end

g.test_stop_server_after_remove = function(cg)
    local protocol = cg.params.use_tls and 'https' or 'http'

    t.assert(helpers.tcp_connection_exists('localhost', 13000))
    local resp = http_client:get(protocol .. '://localhost:13000/ping', {
        ca_file = cg.params.use_tls and fio.pathjoin(ssl_data_dir, 'ca.crt'),
    })
    t.assert_equals(resp.status, 200, 'response not 200')
    t.assert_equals(resp.body, 'pong')

    local cfg = table.deepcopy(config)
    cfg.groups['group-001'].replicasets['replicaset-001'].roles_cfg['roles.httpd'].default = nil
    treegen.write_file(cg.server.chdir, 'config.yaml', yaml.encode(cfg))
    local _, err = cg.server:eval("require('config'):reload()")
    t.assert_not(err)

    t.assert_not(helpers.tcp_connection_exists('localhost', 13000))
end

g.test_change_server_addr_on_the_run = function(cg)
    t.skip_if(cg.params.use_tls, 'no certs for testing addr')

    local resp = http_client:get('http://0.0.0.0:13001/ping')
    t.assert_equals(resp.status, 200, 'response not 200')
    t.assert_equals(resp.body, 'pong')

    local cfg = table.deepcopy(config)
    cfg.groups['group-001'].replicasets['replicaset-001'].roles_cfg['roles.httpd'].additional.listen = 'localhost:13001'
    treegen.write_file(cg.server.chdir, 'config.yaml', yaml.encode(cfg))
    local _, err = cg.server:eval("require('config'):reload()")
    t.assert_not(err)

    t.assert_not(helpers.tcp_connection_exists('0.0.0.0', 13001))
    resp = http_client:get('http://localhost:13001/ping')
    t.assert_equals(resp.status, 200, 'response not 200')
    t.assert_equals(resp.body, 'pong')
end

g.test_keep_existing_server_routes_on_config_reload = function(cg)
    local protocol = cg.params.use_tls and 'https' or 'http'

    local resp = http_client:get(protocol .. '://localhost:13000/ping_once', {
        ca_file = cg.params.use_tls and fio.pathjoin(ssl_data_dir, 'ca.crt'),
    })
    t.assert_equals(resp.status, 200, 'response not 200')
    t.assert_equals(resp.body, 'pong once')

    local cfg = table.deepcopy(config)
    cfg.credentials.users.testguest = { roles = {'super'} }
    treegen.write_file(cg.server.chdir, 'config.yaml', yaml.encode(cfg))
    local _, err = cg.server:eval("require('config'):reload()")
    t.assert_not(err)

    t.assert(helpers.tcp_connection_exists('localhost', 13000))
    resp = http_client:get(protocol .. '://localhost:13000/ping_once', {
        ca_file = cg.params.use_tls and fio.pathjoin(ssl_data_dir, 'ca.crt'),
    })
    t.assert_equals(resp.status, 200, 'response not 200')
    t.assert_equals(resp.body, 'pong once')
end

for log_name, log_lvl in pairs(LOG_LEVELS) do
    g.before_test('test_log_requests_' .. string.lower(log_name), function(cg)
        local cfg = table.copy(config)
        cfg.log = {level = log_lvl}
        treegen.write_file(cg.server.chdir, 'config.yaml', yaml.encode(cfg))
        local _, err = cg.server:eval("require('config'):reload()")
        t.assert_not(err)
    end)

    g['test_log_requests_' .. string.lower(log_name)] = function(cg)
        t.skip_if(cg.params.use_tls)

        local function make_request(address)
            local resp = http_client:get(string.format('http://%s/ping', address))
            t.assert_equals(resp.status, 200, 'response not 200')
        end

        local function assert_should_log(expected)
            local grep_res = cg.server:grep_log('GET /ping', math.huge)
            if expected then
                t.assert(grep_res)
            else
                t.assert_not(grep_res)
            end
        end

        local log_level = tonumber(log_lvl)

        make_request('localhost:13002')
        assert_should_log(log_level >= LOG_LEVELS.DEBUG)

        make_request('localhost:13001')
        assert_should_log(log_level >= LOG_LEVELS.VERBOSE)

        make_request('localhost:13000')
        assert_should_log(log_level >= LOG_LEVELS.INFO)
    end
end

g.test_enable_tls_on_config_reload = function(cg)
    -- We should start with no tls firstly.
    t.skip_if(cg.params.use_tls)

    local resp = http_client:get('http://localhost:13000/ping')
    t.assert_equals(resp.status, 200, 'response not 200')
    t.assert_equals(resp.body, 'pong')

    treegen.write_file(cg.server.chdir, 'config.yaml', yaml.encode(tls_config))
    local _, err = cg.server:eval("require('config'):reload()")
    t.assert_not(err)

    resp = http_client:get('https://localhost:13000/ping', {
        ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt')
    })
    t.assert_equals(resp.status, 200, 'response not 200')
    t.assert_equals(resp.body, 'pong')

    local resp = http_client:get('http://localhost:13000/ping')
    t.assert_equals(resp.status, 444, 'response not 444')
end
