local t = require('luatest')
local http_server = require('http.server')
local http_client = require('http.client').new()
local fio = require('fio')

local helpers = require('test.helpers')

local g = t.group('ssl')

local ssl_data_dir = fio.pathjoin(helpers.get_testdir_path(), "ssl_data")

g.before_all(function()
    helpers.skip_if_ssl_not_enabled()
end)

local server_test_cases = {
    test_key_password_missing = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.enc.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
        },
        expected_err_msg = 'Private key is invalid or password mismatch',
    },
    test_incorrect_key_password = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.enc.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_password = 'incorrect_password',
        },
        expected_err_msg = 'Private key is invalid or password mismatch',
    },
    test_invalid_ciphers_server = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
            ssl_ciphers = "INVALID",
        },
        expected_err_msg = "Ciphers are invalid",
    },
    test_invalid_ca = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.key'),
        },
        expected_err_msg = "CA file is invalid",
    },
}

for name, tc in pairs(server_test_cases) do
    g.before_test(name, function()
        g.httpd = helpers.cfgserv(tc.ssl_opts)
    end)

    g.after_test(name, function()
        if g.httpd.is_run then
            helpers.teardown(g.httpd)
        end
    end)

    g[name] = function()
        t.assert_error_msg_contains(tc.expected_err_msg, function()
            g.httpd:start()
        end)
    end
end

local client_test_cases = {
    test_basic = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
        },
    },
    test_encrypted_key_ok = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.enc.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_password = '1q2w3e',
        },
    },
    test_encrypted_key_password_file = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.enc.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_password_file = fio.pathjoin(ssl_data_dir, 'passwd'),
        },
    },
    test_encrypted_key_many_passwords_file = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.enc.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_password_file = fio.pathjoin(ssl_data_dir, 'passwords'),
        },
    },
    test_key_crt_ca_server_key_crt_client = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
    },
    test_client_password_key_missing = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
        request_opts = {
            ssl_cert = fio.pathjoin(ssl_data_dir, 'client.crt'),
            ssl_key = fio.pathjoin(ssl_data_dir, 'client.enc.key'),
        },
        expected_err_msg = "curl: Problem with the local SSL certificate",
    },
    test_ciphers_server = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
            ssl_ciphers = "ECDHE-RSA-AES256-GCM-SHA384",
        },
        request_opts = {
            ssl_cert = fio.pathjoin(ssl_data_dir, 'client.crt'),
            ssl_key = fio.pathjoin(ssl_data_dir, 'client.key'),
        },
    },
    test_invalid_key_path = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
        request_opts = {
            ssl_cert = fio.pathjoin(ssl_data_dir, 'client.crt'),
            ssl_key = fio.pathjoin(ssl_data_dir, 'invalid.key'),
        },
        expected_err_msg = "curl: Problem with the local SSL certificate",
    },
    test_invalid_cert_path = {
        ssl_opts = {
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
        request_opts = {
            ssl_cert = fio.pathjoin(ssl_data_dir, 'invalid.crt'),
            ssl_key = fio.pathjoin(ssl_data_dir, 'client.key'),
        },
        expected_err_msg = "curl: Problem with the local SSL certificate",
    },
    test_verify_client_optional_with_certs_valid = {
        ssl_opts = {
            ssl_verify_client = 'optional',
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
        request_opts = {
            ssl_cert = fio.pathjoin(ssl_data_dir, 'client.crt'),
            ssl_key = fio.pathjoin(ssl_data_dir, 'client.key'),
        },
    },
    test_verify_client_optional_with_certs_invalid = {
        ssl_opts = {
            ssl_verify_client = 'optional',
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
        request_opts = {
            ssl_cert = fio.pathjoin(ssl_data_dir, 'bad_client.crt'),
            ssl_key = fio.pathjoin(ssl_data_dir, 'bad_client.key'),
        },
        expected_err_msg = helpers.CONNECTION_REFUSED_ERR_MSG,
    },
    test_verify_client_optional_withouts_certs = {
        ssl_opts = {
            ssl_verify_client = 'optional',
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
    },
    test_verify_client_on_valid = {
        ssl_opts = {
            ssl_verify_client = 'on',
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
        request_opts = {
            ssl_cert = fio.pathjoin(ssl_data_dir, 'client.crt'),
            ssl_key = fio.pathjoin(ssl_data_dir, 'client.key'),
        },
    },
    test_verify_client_on_invalid = {
        ssl_opts = {
            ssl_verify_client = 'on',
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
        request_opts = {
            ssl_cert = fio.pathjoin(ssl_data_dir, 'bad_client.crt'),
            ssl_key = fio.pathjoin(ssl_data_dir, 'bad_client.key'),
        },
        expected_err_msg = helpers.CONNECTION_REFUSED_ERR_MSG,
    },
    test_verify_client_on_certs_missing = {
        ssl_opts = {
            ssl_verify_client = 'on',
            ssl_key_file = fio.pathjoin(ssl_data_dir, 'server.key'),
            ssl_cert_file = fio.pathjoin(ssl_data_dir, 'server.crt'),
            ssl_ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
        },
        expected_err_msg = helpers.CONNECTION_REFUSED_ERR_MSG,
    },
}

for name, tc in pairs(client_test_cases) do
    g.before_test(name, function()
        g.httpd = helpers.cfgserv(tc.ssl_opts)
        g.httpd:start()
    end)

    g.after_test(name, function()
        helpers.teardown(g.httpd)
    end)

    g[name] = function()
        local req_opts = http_server.internal.extend({
            -- We need to provide ca_file by default because curl uses the
            -- system native CA store for verification.
            -- See: https://curl.se/docs/sslcerts.html
            ca_file = fio.pathjoin(ssl_data_dir, 'ca.crt'),
            verbose = true,
        }, tc.request_opts or {})

        if tc.expected_err_msg ~= nil then
            t.assert_error_msg_contains(tc.expected_err_msg, function()
                http_client:get(helpers.tls_uri .. '/test', req_opts)
            end)
        else
            local r = http_client:get(helpers.tls_uri .. '/test', req_opts)
            t.assert_equals(r.status, 200, 'response not 200')
        end
    end
end
