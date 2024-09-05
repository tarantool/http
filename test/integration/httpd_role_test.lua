local t = require('luatest')
local treegen = require('luatest.treegen')
local server = require('luatest.server')
local fun = require('fun')
local yaml = require('yaml')

local helpers = require('test.helpers')

local g = t.group()

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
                            },
                            additional = {
                                listen = 13001,
                            }
                        },
                        ['test.mocks.mock_role'] = {
                            {
                                id = 1,
                            },
                            {
                                id = 2,
                                name = 'additional',
                            },
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

g.before_each(function()
    helpers.skip_if_not_tarantool3()

    local dir = treegen.prepare_directory({}, {})

    local config_file = treegen.write_file(dir, 'config.yaml',
        yaml.encode(config))
    local opts = {config_file = config_file, chdir = dir}
    g.server = server:new(fun.chain(opts, {alias = 'instance-001'}):tomap())
    helpers.update_lua_env_variables(g.server)

    g.server:start()
end)

g.after_each(function()
    g.server:stop()
end)

g.test_httpd_role_usage = function()
    t.assert_equals(g.server:eval(
        'return require("test.mocks.mock_role").get_server_port(1)'
    ), 13000)
    t.assert_equals(g.server:eval(
        'return require("test.mocks.mock_role").get_server_port(2)'
    ), 13001)
end
