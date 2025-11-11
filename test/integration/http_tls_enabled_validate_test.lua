local t = require('luatest')
local fio = require("fio")

local http_server = require('http.server')
local helpers = require('test.helpers')

local g = t.group()

local ssl_data_dir = fio.pathjoin(helpers.get_testdir_path(), "ssl_data")

local test_cases = {
    ssl_cert_file_missing = {
        opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
        },
        expected_err_msg = "ssl_key_file and ssl_cert_file must be set to enable TLS",
    },
    ssl_cert_file_incorrect_type = {
        opts = {
            ssl_cert_file = 1,
        },
        expected_err_msg = "ssl_cert_file option must be a string",
    },
    cert_file_not_exists = {
        opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = "some/path",
        },
        expected_err_msg = 'file "some/path" not exists',
    },
    ssl_key_file_missing = {
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
        },
        expected_err_msg = "ssl_key_file and ssl_cert_file must be set to enable TLS",
    },
    ssl_key_file_incorrect_type = {
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_key_file = 1,
        },
        expected_err_msg = "ssl_key_file option must be a string",
    },
    ssl_key_file_not_exists = {
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_key_file = "some/path",
        },
        expected_err_msg = 'file "some/path" not exists',
    },
    ssl_password_incorrect_type = {
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_password = 1,
        },
        expected_err_msg = "ssl_password option must be a string",
    },
    ssl_password_file_incorrect_type = {
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_password = "password",
            ssl_password_file = 1,
        },
        expected_err_msg = "ssl_password_file option must be a string",
    },
    ssl_password_file_not_exists = {
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_password = "password",
            ssl_password_file = "some/path",
        },
        expected_err_msg = 'file "some/path" not exists',
    },
    ssl_ca_file_incorrect_type = {
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_password = "password",
            ssl_password_file = fio.pathjoin(ssl_data_dir, 'passwords'),
            ssl_ca_file = 1,
        },
        expected_err_msg = "ssl_ca_file option must be a string",
    },
    ssl_ca_file_not_exists = {
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_password = "password",
            ssl_password_file = fio.pathjoin(ssl_data_dir, 'passwords'),
            ssl_ca_file = "some/path",
        },
        expected_err_msg = 'file "some/path" not exists',
    },
    ssl_ciphers_incorrect_type = {
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_password = "password",
            ssl_password_file = fio.pathjoin(ssl_data_dir, 'passwords'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
            ssl_ciphers = 1,
        },
        expected_err_msg = "ssl_ciphers option must be a string",
    },
    ssl_verify_client_incorrect_value = {
        opts = {
            ssl_verify_client = "unknown",
        },
        expected_err_msg = '"unknown" option not exists. Available options: "on", "off", "optional"'
    },
    ssl_socket_not_supported = {
        check_ssl = true,
        opts = {
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
        },
        expected_err_msg = 'ssl socket is not supported',
    }
}

for name, case in pairs(test_cases) do
    g['test_ssl_option_' .. name] = function()
        helpers.skip_if_ssl_not_enabled()
        if case.check_ssl == true then
            helpers.skip_if_ssl_enabled()
        end
        t.assert_error_msg_contains(case.expected_err_msg, function()
            http_server.new('host', 8080, case.opts)
        end)
    end
end
