local t = require('luatest')
local http_lib = require('http.lib')

local g = t.group()

g.test_parse_request = function()
    t.assert_equals(http_lib._parse_request('abc'), {
        error = 'Broken request line',
        headers = {}
    }, 'broken request')

    t.assert_equals(
        http_lib._parse_request('GET / HTTP/1.1\nHost: s.com\r\n\r\n').path,
        '/',
        'path'
    )
    t.assert_equals(
        http_lib._parse_request('GET / HTTP/1.1\nHost: s.com\r\n\r\n').proto,
        {1, 1},
        'proto'
    )
    t.assert_equals(
        http_lib._parse_request('GET / HTTP/1.1\nHost: s.com\r\n\r\n').headers,
        {host = 's.com'},
        'host'
    )
    t.assert_equals(
        http_lib._parse_request('GET / HTTP/1.1\nHost: s.com\r\n\r\n').method,
        'GET',
        'method'
    )
    t.assert_equals(
        http_lib._parse_request('GET / HTTP/1.1\nHost: s.com\r\n\r\n').query,
        '',
        'query'
    )
end
