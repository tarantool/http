local t = require('luatest')

local http_server = require('http.server')

local g = t.group()

local function get_object()
    return setmetatable({}, http_server.internal.response_mt)
end

g.test_values_escaping = function()
    local test_table = {
        whitespace = {
            value = "f f",
            result = 'f%20f',
        },
        dquote = {
            value = 'f"f',
            result = 'f%22f',
        },
        comma = {
            value = "f,f",
            result = "f%2Cf",
        },
        semicolon = {
            value = "f;f",
            result = "f%3Bf",
        },
        backslash = {
            value = "f\\f",
            result = "f%5Cf",
        },
        unicode = {
            value = "fюf",
            result = "f%D1%8Ef"
        },
        unprintable_ascii = {
            value = string.char(15),
            result = "%0F"
        }
    }

    for byte = 33, 126 do
        if byte ~= string.byte('"') and
           byte ~= string.byte(",") and
           byte ~= string.byte(";") and
           byte ~= string.byte("\\") then
                test_table[byte] = {
                    value = "f" .. string.char(byte) .. "f",
                    result = "f" .. string.char(byte) .. "f",
                }
        end
    end

    for case_name, case in pairs(test_table) do
        local resp = get_object()
        resp:setcookie({
            name='name',
            value = case.value
        })
        t.assert_equals(resp.headers['set-cookie'], {
            "name=" .. case.result
        }, case_name)
    end
end

g.test_values_raw = function()
    local test_table = {}
    for byte = 0, 127 do
        test_table[byte] = {
            value = "f" .. string.char(byte) .. "f",
            result = "f" .. string.char(byte) .. "f",
        }
    end

    test_table.unicode = {
        value = "fюf",
        result = "fюf"
    }

    for case_name, case in pairs(test_table) do
        local resp = get_object()
        resp:setcookie({
                name='name',
                value = case.value
            }, {
                raw = true
        })
        t.assert_equals(resp.headers['set-cookie'], {
            "name=" .. case.result
        }, case_name)
    end
end

g.test_path_escaping = function()
    local test_table = {
        semicolon = {
            path = "f;f",
            result = "f%3Bf",
        },
        unicode = {
            path = "fюf",
            result = "f%D1%8Ef"
        },
        unprintable_ascii = {
            path = string.char(15),
            result = "%0F"
        }
    }

    for byte = 32, 126 do
        if byte ~= string.byte(";") then
            test_table[byte] = {
                path = "f" .. string.char(byte) .. "f",
                result = "f" .. string.char(byte) .. "f",
            }
        end
    end

    for case_name, case in pairs(test_table) do
        local resp = get_object()
        resp:setcookie({
            name='name',
            value = 'value',
            path = case.path
        })
        t.assert_equals(resp.headers['set-cookie'], {
            "name=value;" .. 'path=' .. case.result
        }, case_name)
    end
end

g.test_path_raw = function()
    local test_table = {}
    for byte = 0, 127 do
        test_table[byte] = {
            path = "f" .. string.char(byte) .. "f",
            result = "f" .. string.char(byte) .. "f",
        }
    end

    test_table.unicode = {
        path = "fюf",
        result = "fюf"
    }

    for case_name, case in pairs(test_table) do
        local resp = get_object()
        resp:setcookie({
                name='name',
                value = 'value',
                path = case.path
            }, {
                raw = true
        })
        t.assert_equals(resp.headers['set-cookie'], {
            "name=value;" .. 'path=' .. case.result
        }, case_name)
    end
end

g.test_set_header = function()
    local test_table = {
        name_value = {
            cookie = {
                name = 'name',
                value = 'value'
            },
            result = {"name=value"},
        },
        name_value_path = {
            cookie = {
                name = 'name',
                value = 'value',
                path = 'path'
            },
            result = {"name=value;path=path"},
        },
        name_value_path_domain = {
            cookie = {
                name = 'name',
                value = 'value',
                path = 'path',
                domain = 'domain',
            },
            result = {"name=value;path=path;domain=domain"},
        },
        name_value_path_domain_expires = {
            cookie = {
                name = 'name',
                value = 'value',
                path = 'path',
                domain = 'domain',
                expires = 'expires'
            },
            result = {"name=value;path=path;domain=domain;expires=expires"},
        },
    }

    for case_name, case in pairs(test_table) do
        local resp = get_object()
        resp:setcookie(case.cookie)
        t.assert_equals(resp.headers["set-cookie"], case.result, case_name)
    end
end
