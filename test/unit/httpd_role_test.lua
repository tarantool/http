local t = require('luatest')
local g = t.group()

local httpd_role = require('roles.httpd')
local helpers = require('test.helpers')
local fio = require('fio')

local ssl_data_dir = fio.abspath(fio.pathjoin(helpers.get_testdir_path(), "ssl_data"))

g.after_each(function()
    httpd_role.stop()
end)

local validation_cases = {
    ["not_table"] = {
        cfg = 42,
        err = "configuration must be a table, got number",
    },
    ["name_not_string"] = {
        cfg = {
            [42] = {
                listen = 8081,
            },
        },
        err = "name of the server must be a string",
    },
    ["listen_not_exist"] = {
        cfg = {
            server = {
                listen = nil,
            },
        },
        err = "failed to parse http 'listen' param: must exist",
    },
    ["listen_not_string_and_not_number"] = {
        cfg = {
            server = {
                listen = {},
            },
        },
        err = "failed to parse http 'listen' param: must be a string or a number, got table",
    },
    ["listen_port_too_small"] = {
        cfg = {
            server = {
                listen = 0,
            },
        },
        err = "failed to parse http 'listen' param: port must be in the range [1, 65535]",
    },
    ["listen_port_in_range"] = {
        cfg = {
            server = {
                listen = 8081,
            },
        },
    },
    ["listen_port_too_big"] = {
        cfg = {
            server = {
                listen = 65536,
            },
        },
        err = "failed to parse http 'listen' param: port must be in the range [1, 65535]",
    },
    ["listen_uri_no_port"] = {
        cfg = {
            server = {
                listen = "localhost",
            },
        },
        err = "failed to parse http 'listen' param: URI must contain a port",
    },
    ["listen_uri_port_too_small"] = {
        cfg = {
            server = {
                listen = "localhost:0",
            },
        },
        err = "failed to parse http 'listen' param: port must be in the range [1, 65535]",
    },
    ["listen_uri_with_port_in_range"] = {
        cfg = {
            server = {
                listen = "localhost:8081",
            },
        },
    },
    ["listen_uri_port_too_big"] = {
        cfg = {
            server = {
                listen = "localhost:65536",
            },
        },
        err = "failed to parse http 'listen' param: port must be in the range [1, 65535]",
    },
    ["listen_uri_port_not_number"] = {
        cfg = {
            server = {
                listen = "localhost:foo",
            },
        },
        err = "failed to parse http 'listen' param: URI port must be a number",
    },
    ["listen_uri_non_unix_scheme"] = {
        cfg = {
            server = {
                listen = "http://localhost:123",
            },
        },
        err = "failed to parse http 'listen' param: URI scheme is not supported",
    },
    ["listen_uri_login_password"] = {
        cfg = {
            server = {
                listen = "login:password@localhost:123",
            },
        },
        err = "failed to parse http 'listen' param: URI login and password are not supported",
    },
    ["listen_uri_query"] = {
        cfg = {
            server = {
                listen = "localhost:123/?foo=bar",
            },
        },
        err = "failed to parse http 'listen' param: URI query component is not supported",
    },
    ["ssl_ok_minimal"] = {
        cfg = {
            server = {
                listen = "localhost:123",
                ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
                ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt')
            },
        },
    },
    ["ssl_ok_full"] = {
        cfg = {
            server = {
                listen = 123,
                ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
                ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
                ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
                ssl_ciphers = "ECDHE-RSA-AES256-GCM-SHA384",
            },
        },
    },
    ["ssl_key_file_not_string"] = {
        cfg = {
            server = {
                listen = "localhost:123",
                ssl_key_file = 123,
            },
        },
        err = "ssl_key_file option must be a string",
    },
    ["ssl_cert_file_not_string"] = {
        cfg = {
            server = {
                listen = "localhost:123",
                ssl_cert_file = 123,
            },
        },
        err = "ssl_cert_file option must be a string",
    },
    ["ssl_password_not_string"] = {
        cfg = {
            server = {
                listen = "localhost:123",
                ssl_password = 123,
            },
        },
        err = "ssl_password option must be a string",
    },
    ["ssl_password_file_not_string"] = {
        cfg = {
            server = {
                listen = "localhost:123",
                ssl_password_file = 123,
            },
        },
        err = "ssl_password_file option must be a string",
    },
    ["ssl_ca_file_not_string"] = {
        cfg = {
            server = {
                listen = "localhost:123",
                ssl_ca_file = 123,
            },
        },
        err = "ssl_ca_file option must be a string",
    },
    ["ssl_ciphers_not_string"] = {
        cfg = {
            server = {
                listen = "localhost:123",
                ssl_ciphers = 123,
            },
        },
        err = "ssl_ciphers option must be a string",
    },
    ["ssl_key_and_cert_must_exist"] = {
        cfg = {
            server = {
                listen = "localhost:123",
                ssl_ciphers = 'cipher1:cipher2',
            },
        },
        err = "ssl_key_file and ssl_cert_file must be set to enable TLS",
    },
}

for name, case in pairs(validation_cases) do
    local test_name = ('test_validate_http_%s%s'):format(
        (case.err ~= nil) and 'fails_on_' or 'success_for_',
        name
    )

    g[test_name] = function()
        local ok, res = pcall(httpd_role.validate, case.cfg)

        if case.err ~= nil then
            t.assert_not(ok)
            t.assert_str_contains(res, case.err)
        else
            t.assert(ok)
            t.assert_is(res, nil)
        end
    end
end

g['test_get_default_without_apply'] = function()
    local result = httpd_role.get_server()
    t.assert_is(result, nil)
end

g['test_get_default_no_default'] = function()
    local cfg = {
        not_a_default = {
            listen = 13000,
        },
    }

    httpd_role.apply(cfg)

    local result = httpd_role.get_server()
    t.assert_is(result, nil)
end

g['test_get_default'] = function()
    local cfg = {
        [httpd_role.DEFAULT_SERVER_NAME] = {
            listen = 13001,
        },
    }

    httpd_role.apply(cfg)

    local result = httpd_role.get_server()
    t.assert_not_equals(result, nil)
    t.assert_is(result.port, 13001)
end

g['test_get_server_bad_type'] = function()
    local ok, res = pcall(httpd_role.get_server, {})

    t.assert_not(ok)
    t.assert_str_contains(res, '?string expected, got table')
end

g.test_stop_unused_servers = function()
    local cfg = {
        [httpd_role.DEFAULT_SERVER_NAME] = {
            listen = 13001,
        },
        additional = {
            listen = 13002,
        },
    }

    httpd_role.apply(cfg)
    for name, body in pairs(cfg) do
        local res = httpd_role.get_server(name)
        t.assert(res)
        t.assert_equals(res.port, body.listen)
    end

    cfg.additional = nil
    httpd_role.apply(cfg)
    t.assert(httpd_role.get_server())
    t.assert_equals(httpd_role.get_server('additional'))
end

g.test_edit_server_address = function()
    local cfg = {
        [httpd_role.DEFAULT_SERVER_NAME] = {
            listen = 13001,
        },
    }

    httpd_role.apply(cfg)
    local result = httpd_role.get_server()
    t.assert(result)
    t.assert_equals(result.port, cfg[httpd_role.DEFAULT_SERVER_NAME].listen)

    cfg[httpd_role.DEFAULT_SERVER_NAME].listen = 13002

    httpd_role.apply(cfg)
    result = httpd_role.get_server()
    t.assert(result)
    t.assert_equals(result.port, cfg[httpd_role.DEFAULT_SERVER_NAME].listen)
end
