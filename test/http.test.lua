#!/usr/bin/env tarantool

package.path = package.path..";../?.lua"
package.cpath = package.cpath..";../?.so"

tap = require('tap')
http_lib = require('http.lib')
http_client = require('http.client')
http_server = require('http.server')

local test = tap.test("http")
test:plan(6)
test:test("split_uri", function(test)
    test:plan(70)
    local function check(uri, rhs)
        local schema, host, service, path, qs = http_lib.split_url(uri)
        local lhs = { schema = schema, host = host, port = port,
            path = path, qs = qs }
        if lhs.qs == '' then
            lhs.qs = nil
        end
        local extra = { lhs = lhs, rhs = rhs }
        test:is(schema, rhs.schema, uri.." schema", extra)
        test:is(host, rhs.host, uri.." host", extra)
        test:is(service, rhs.service, uri.." service", extra)
        test:is(path, rhs.path, uri.." path", extra)
        test:is(qs, rhs.qs, uri.." qs", extra)
    end
    check('http://abc', { schema = 'http', host = 'abc', path ='/'})
    check('http://abc/', { schema = 'http', host = 'abc', path ='/'})
    check('http://abc?', { schema = 'http', host = 'abc', path ='/'})
    check('http://abc/?', { schema = 'http', host = 'abc', path ='/'})
    check('http://abc/?', { schema = 'http', host = 'abc', path ='/'})
    check('http://abc:123', { schema = 'http', host = 'abc', service = '123',
        path ='/'})
    check('http://abc:123?', { schema = 'http', host = 'abc', service = '123',
        path ='/'})
    check('http://abc:123?query', { schema = 'http', host = 'abc',
        service = '123', path ='/', qs = 'query'})
    check('http://domain.subdomain.com:service?query', { schema = 'http',
        host = 'domain.subdomain.com', service = 'service', path ='/',
        qs = 'query'})
    check('google.com', { schema = 'http', host = 'google.com', path = '/'})
    check('google.com?query', { schema = 'http', host = 'google.com',
        path = '/', qs = 'query'})
    check('google.com/abc?query', { schema = 'http', host = 'google.com',
        path = '/abc', qs = 'query'})
    check('https://google.com:443/abc?query', { schema = 'https',
        host = 'google.com', service = '443', path = '/abc', qs = 'query'})
    check('https://', { schema = 'https', path = '/'})
end)

test:test("template", function(test)
    test:plan(3)
    test:is(http_lib.template("<% for i = 1, cnt do %> <%= abc %> <% end %>",
        {abc = '1 <3>&" ', cnt = 3}),
        ' 1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;  ',
        "tmpl1")
    test:is(http_lib.template("<% for i = 1, cnt do %> <%= ab %> <% end %>",
        {abc = '1 <3>&" ', cnt = 3}),
        ' nil  nil  nil ', "tmpl2")
    local r, msg = pcall(http_lib.template, "<% ab() %>", {ab = '1'})
    test:ok(r == false and msg:match("call local 'ab'") ~= nil, "bad template")
end)

--[[
lua dump = function(d, ...) if type(d) ~= 'table' then return "'" .. box.cjson.encode(d, ...) .. "'" end local o = {} for k, v in pairs(d) do if type(v) ~= 'function' then o[k] = v end end  return "'" .. box.cjson.encode(o) .. "'" end
---
...
lua hdump = function(h) h.server = nil return dump(h) end
---
...
lua dump(http_server.parse_request('abc'))
---
 - '{"error":"Broken request line","headers":{}}'
...
lua dump(http_server.parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n"))
---
 - '{"path":"\/","broken":false,"method":"GET","query":"","body":"","proto":[1,1],"headers":{"host":"s.com"}}'
...
lua dump(http_server.parse_request("GET / HTTP/1.0\nHost: s.com\nHost: cde.com"))
---
 - '{"path":"\/","broken":false,"query":"","method":"GET","proto":[1,0],"headers":{"host":"s.com, cde.com"}}'
...
lua dump(http_server.parse_request("GET / HTTP/0.9\nX-Host: s.com\r\n\r\nbody text"))
---
 - '{"path":"\/","broken":false,"method":"GET","query":"","body":"body text","proto":[0,9],"headers":{"x-host":"s.com"}}'
...
lua dump(http_lib.parse_response('abc'))
---
 - '{"error":"Too short response line","headers":{}}'
...
lua dump(http_lib.parse_response("HTTP/1.0 200 Ok\nHost: s.com\r\n\r\n"))
---
 - '{"reason":"Ok","status":200,"body":"","proto":[1,0],"headers":{"host":"s.com"}}'
...
lua dump(http_lib.parse_response("HTTP/1.0 200 Ok\nHost: s.com\r\n\r\ntext of body"))
---
 - '{"reason":"Ok","status":200,"body":"text of body","proto":[1,0],"headers":{"host":"s.com"}}'
...
--]]

test:test("http request", function(test)
    test:plan(11)
    local r = http_client.get("http://mail.ru/")
    test:is(r.status, 200, 'mail.ru 200')
    test:is(r.proto[1], 1, 'mail.ru http 1.1')
    test:is(r.proto[2], 1, 'mail.ru http 1.1')
    test:ok(r.body:match("<(html)") ~= nil, "mail.ru is html", r)
    test:ok(tonumber(r.headers["content-length"]) > 0,
        "mail.ru content-length > 0")
    test:is(http_client.get("http://localhost:88/").status, 595, 'timeout')
    local r = http_client.get("http://go.mail.ru/search?fr=main&q=tarantool")
    test:is(r.status, 200, 'go.mail.ru 200')
    test:is(r.proto[1], 1, 'go.mail.ru http 1.1')
    test:is(r.proto[2], 1, 'go.mail.ru http 1.1')
    test:ok(r.body:match("<(html)") ~= nil, "go.mail.ru is html", r)
    test:is(http_client.request("GET", "http://mail.ru/").status, 200, 'alias')
end)

--[[
lua dump(http_lib.params())
---
 - '{}'
...
lua dump(http_lib.params(''))
---
 - '{}'
...
lua dump(http_lib.params('a'))
---
 - '{"a":""}'
...
lua dump(http_lib.params('a=b'))
---
 - '{"a":"b"}'
...
lua dump(http_lib.params('a=b&b=cde'))
---
 - '{"a":"b","b":"cde"}'
...
lua dump(http_lib.params('a=b&b=cde&a=1'))
---
 - '{"a":["b","1"],"b":"cde"}'
...
lua dump(http_lib.params('a=b&b=cde&a=1&a=10'))
---
 - '{"a":["b","1","10"],"b":"cde"}'
...
--]]

local function cfgserv()
    local httpd = http_server.new('127.0.0.1', 12345, { app_dir = '.' })
        :route({path = '/abc/:cde/:def', name = 'test'}, function() end)
        :route({path = '/abc'}, function() end)
        :route({path = '/ctxaction'}, 'module.controller#action')
        :route({path = '/absentaction'}, 'module.controller#absent')
        :route({path = '/absent'}, 'module.absent#action')
        :route({path = '/abc/:cde'}, function() end)
        :route({path = '/abc_:cde_def'}, function() end)
        :route({path = '/abc-:cde-def'}, function() end)
        :route({path = '/aba*def'}, function() end)
        :route({path = '/abb*def/cde', name = 'star'}, function() end)
--[[
lua type(httpd:route({path = '/abb*def/cde', name = 'star'}, function() end))
---
error: './box/http/server.lua:15: Route with name ''star'' is already exists'
...
--]]
        :helper('helper_title', function(self, a) return 'Hello, ' .. a end)
        :route({path = '/helper', file = 'helper.html.el'})
        :route({ path = '/test', file = 'test.html.el' },
            function(cx) cx:render({ title = 'title: 123' }) end)
    return httpd
end

test:test("server url match", function(test)
    test:plan(17)
    local httpd = cfgserv()
    test:istable(httpd, "httpd object")
    test:isnil(httpd:match('GET', '/'))
    test:is(httpd:match('GET', '/abc').endpoint.path, "/abc", "/abc")
    test:is(#httpd:match('GET', '/abc').stash, 0, "/abc")
    test:is(httpd:match('GET', '/abc/123').endpoint.path, "/abc/:cde", "/abc/123")
    test:is(httpd:match('GET', '/abc/123').stash.cde, "123", "/abc/123")
    test:is(httpd:match('GET', '/abc/123/122').endpoint.path, "/abc/:cde/:def",
        "/abc/123/122")
    test:is(httpd:match('GET', '/abc/123/122').stash.def, "122",
        "/abc/123/122")
    test:is(httpd:match('GET', '/abc/123/122').stash.cde, "123",
        "/abc/123/122")
    test:is(httpd:match('GET', '/abc_123-122').endpoint.path, "/abc_:cde_def",
        "/abc_123-122")
    test:is(httpd:match('GET', '/abc_123-122').stash.cde_def, "123-122",
        "/abc_123-122")
    test:is(httpd:match('GET', '/abc-123-def').endpoint.path, "/abc-:cde-def",
        "/abc-123-def")
    test:is(httpd:match('GET', '/abc-123-def').stash.cde, "123",
        "/abc-123-def")
    test:is(httpd:match('GET', '/aba-123-dea/1/2/3').endpoint.path,
        "/aba*def", '/aba-123-dea/1/2/3')
    test:is(httpd:match('GET', '/aba-123-dea/1/2/3').stash.def,
        "-123-dea/1/2/3", '/aba-123-dea/1/2/3')
    test:is(httpd:match('GET', '/abb-123-dea/1/2/3/cde').endpoint.path,
        "/abb*def/cde", '/abb-123-dea/1/2/3/cde')
    test:is(httpd:match('GET', '/abb-123-dea/1/2/3/cde').stash.def,
        "-123-dea/1/2/3", '/abb-123-dea/1/2/3/cde')
end)

test:test("server url_for", function(test)
    test:plan(5)
    local httpd = cfgserv()
    test:is(httpd:url_for('abcdef'), '/abcdef', '/abcdef')
    test:is(httpd:url_for('test'), '/abc//', '/abc//')
    test:is(httpd:url_for('test', { cde = 'cde_v', def = 'def_v' }),
        '/abc/cde_v/def_v', '/abc/cde_v/def_v')
    test:is(httpd:url_for('star', { def = '/def_v' }),
        '/abb/def_v/cde', '/abb/def_v/cde')
    test:is(httpd:url_for('star', { def = '/def_v' }, { a = 'b', c = 'd' }),
        '/abb/def_v/cde?a=b&c=d', '/abb/def_v/cde?a=b&c=d')
end)

test:test("server requests", function(test)
    test:plan(35)
    local httpd = cfgserv()
    httpd:start()
    local r = http_client.get('http://127.0.0.1:12345/test')
    test:is(r.status, 200, 'testserv 200')
    test:is(r.proto[1], 1, 'testserv http 1.1')
    test:is(r.proto[2], 1, 'testserv http 1.1')
    test:is(r.reason, 'Ok', 'testserv reason')
    test:is(string.match(r.body, 'title: 123'), 'title: 123', 'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/test1')
    test:is(r.status, 404, 'testserv 404')
    test:is(r.reason, 'Not found', 'testserv reason')

    local r = http_client.get('http://127.0.0.1:12345/absent')
    test:is(r.status, 500, 'testserv 500')
    test:is(r.reason, 'Internal server error', 'testserv reason')
    test:is(string.match(r.body, 'load module'), 'load module', 'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/ctxaction')
    test:is(r.status, 200, 'testserv 200')
    test:is(r.reason, 'Ok', 'testserv reason')
    test:is(string.match(r.body, 'Hello, Tarantool'), 'Hello, Tarantool',
        'testserv body')
    test:is(string.match(r.body, 'action: action'), 'action: action',
        'testserv body action')
    test:is(string.match(r.body, 'controller: module[.]controller'),
        'controller: module.controller', 'testserv body controller')

    local r = http_client.get('http://127.0.0.1:12345/ctxaction.js')
    test:is(r.status, 200, 'testserv 200')
    test:is(r.reason, 'Ok', 'testserv reason')
    test:is(string.match(r.body, 'json template js'), 'json template js',
        'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/ctxaction.jsonaaa')
    test:is(r.status, 500, 'testserv 500') -- WTF?
    test:is(r.reason, 'Internal server error', 'testserv reason')
    test:is(string.match(r.body, 'No such file'), 'No such file',
        'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/hello.html')
    test:is(r.status, 200, 'testserv 200')
    test:is(r.reason, 'Ok', 'testserv reason')
    test:is(string.match(r.body, 'static html'), 'static html',
        'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/absentaction')
    test:is(r.status, 500, 'testserv 500')
    test:is(r.reason, 'Internal server error', 'testserv reason')
    test:is(string.match(r.body, 'contain function'), 'contain function',
        'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/helper')
    test:is(r.status, 200, 'helper 200')
    test:is(r.reason, 'Ok', 'helper reason')
    test:is(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    local r = http_client.get('http://127.0.0.1:12345/helper?abc')
    test:is(r.status, 200, 'helper?abc 200')
    test:is(r.reason, 'Ok', 'helper?abc reason')
    test:is(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    httpd:route({path = '/die', file = 'helper.html.el'},
        function() error(123) end )

    local r = http_client.get('http://127.0.0.1:12345/die')
    test:is(r.status, 500, 'die 500')
    test:is(r.reason, 'Internal server error', 'die reason')

--[[
lua type(httpd:route({method = 'POST', path = '/dit', file = 'helper.html.el'}, function(tx) tx:render({text = 'POST = ' .. tx.req.body}) end ))
---
 - table
...
lua type(httpd:route({method = 'GET', path = '/dit', file = 'helper.html.el'}, function(tx) tx:render({text = 'GET = ' .. tx.req.body}) end ))
---
 - table
...
lua res = http_client.request('POST', 'http://127.0.0.1:12345/dit', 'test')
---
...
lua res.body == 'POST = test'
---
 - true
...
lua res = http_client.post('http://127.0.0.1:12345/dit', 'test')
---
...
lua res.body == 'POST = test'
---
 - true
...
lua res = http_client.request('GET', 'http://127.0.0.1:12345/dit')
---
...
lua res.body == 'GET = '
---
 - true
...
lua type(httpd:route({method = 'POST', path = '/gparam' }, function(tx) tx:render({text = 'POST PARAM = ' .. dump( tx.req:post_param() )  }) end ))
---
 - table
...
lua type(httpd:route({path = '/gparam' }, function(tx) tx:render({text = 'PARAM = ' .. dump( tx.req:query_param() )  }) end ))
---
 - table
...
lua res = http_client.request('GET', 'http://127.0.0.1:12345/gparam?aaa=12343')
---
...
lua res.body == [ [PARAM = '{"aaa":"12343"}'] ]
---
 - true
...
lua res = http_client.request('POST', 'http://127.0.0.1:12345/gparam?aaa=12343', '')
---
...
lua res.body == [ [POST PARAM = '{}'] ]
---
 - true
...
lua res = http_client.request('POST', 'http://127.0.0.1:12345/gparam?aaa=12343', 'bbb=4321')
---
...
lua res.body == [ [POST PARAM = '{"bbb":"4321"}'] ]
---
 - true
...
lua type(httpd:route({path = '/bparam' }, function(tx) tx:render({text = 'PARAM = ' .. dump( tx.req:param() )  }) end ))
---
 - table
...
lua res = http_client.request('POST', 'http://127.0.0.1:12345/bparam?aaa=12343', 'bbb=4321')
---
...
lua res.body == [ [PARAM = '{"bbb":"4321","aaa":"12343"}'] ]
---
 - true
...
lua type(httpd:route({method = 'GET', path = '/cookie' }, function(tx) tx:cookie({name = 'name', value = 'value' }) tx:cookie({name = 'time', value = 'a ' .. tostring(tx:cookie('time')) }) tx:render({text = 'a ' .. tostring(tx:cookie('time'))  }) end ))
---
 - table
...
lua res = http_client.request('GET', 'http://127.0.0.1:12345/cookie')
---
...
lua dump(res.status)
---
 - '200'
...
lua dump(res.body)
---
 - '"a nil"'
...
lua dump(res.headers['set-cookie'])
---
 - '"name=value;path=\/cookie, time=a%20nil;path=\/cookie"'
...
lua res = http_client.request('GET', 'http://127.0.0.1:12345/cookie', nil, { headers = { cookie = 'name=ignore; time=123' } })
---
...
lua dump(res.status)
---
 - '200'
...
lua dump(res.body)
---
 - '"a 123"'
...
lua hdump(res.headers)
---
 - '{"set-cookie":"name=value;path=\/cookie, time=a%20123;path=\/cookie","content-length":"5","content-type":"text\/plain; charset=utf-8","connection":"close"}'
...
lua dump(res.headers['set-cookie'])
---
 - '"name=value;path=\/cookie, time=a%20123;path=\/cookie"'
...
--]]
    httpd:stop()
end)

test:check()
os.exit(0)