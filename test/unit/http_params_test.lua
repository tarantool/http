local t = require('luatest')
local http_lib = require('http.lib')

local pgroup = t.group('http_params', {
    { params = nil, t = {}, comment = 'nil string' },
    { params = '', t = {}, comment = 'empty string' },
    { params = 'a', t = { a = '' }, comment = 'separate literal' },
    { params = 'a=b', t = { a = 'b' }, comment = 'one variable' },
    { params = 'a=b&b=cde', t = {a = 'b', b = 'cde'}, comment = 'some'},
    { params = 'a=b&b=cde&a=1', t = {a = { 'b', '1' }, b = 'cde'}, comment = 'array'}
})

pgroup.test_params = function(g)
    t.assert_equals(http_lib.params(g.params.params), g.params.t, g.params.comment)
end
