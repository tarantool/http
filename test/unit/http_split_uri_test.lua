local t = require('luatest')
local urilib = require('uri')

local g = t.group()

local function check(uri, rhs)
    local lhs = urilib.parse(uri)
    local extra = { lhs = lhs, rhs = rhs }
    if lhs.query == '' then
        lhs.query = nil
    end

    t.assert_equals(lhs.scheme, rhs.scheme, uri..' scheme', extra)
    t.assert_equals(lhs.host, rhs.host, uri..' host', extra)
    t.assert_equals(lhs.service, rhs.service, uri..' service', extra)
    t.assert_equals(lhs.path, rhs.path, uri..' path', extra)
    t.assert_equals(lhs.query, rhs.query, uri..' query', extra)
end

g.test_split_uri = function()
    check('http://abc', {
        scheme = 'http',
        host = 'abc'
    })
    check('http://abc/', {
        scheme = 'http',
        host = 'abc',
        path ='/'
    })
    check('http://abc?', {
        scheme = 'http',
        host = 'abc'
    })
    check('http://abc/?', {
        scheme = 'http',
        host = 'abc',
        path ='/'
    })
    check('http://abc/?', {
        scheme = 'http',
        host = 'abc',
        path ='/'
    })
    check('http://abc:123', {
        scheme = 'http',
        host = 'abc',
        service = '123'
    })
    check('http://abc:123?', {
        scheme = 'http',
        host = 'abc',
        service = '123'
    })
    check('http://abc:123?query', {
        scheme = 'http',
        host = 'abc',
        service = '123',
        query = 'query'
    })
    check('http://domain.subdomain.com:service?query', {
        scheme = 'http',
        host = 'domain.subdomain.com',
        service = 'service',
        query = 'query'
    })
    check('google.com', {
        host = 'google.com'
    })
    check('google.com?query', {
        host = 'google.com',
        query = 'query'
    })
    check('google.com/abc?query', {
        host = 'google.com',
        path = '/abc',
        query = 'query'
    })
    check('https://google.com:443/abc?query', {
        scheme = 'https',
        host = 'google.com',
        service = '443',
        path = '/abc',
        query = 'query'
    })
end
