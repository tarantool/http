local t = require('luatest')
local g = t.group()
local http_lib = require('http.lib')

g.test_template = function()
    t.assert_equals(http_lib.template("<% for i = 1, cnt do %> <%= abc %> <% end %>",
        {abc = '1 <3>&" ', cnt = 3}),
        ' 1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;  ',
        "tmpl1")
    t.assert_equals(http_lib.template("<% for i = 1, cnt do %> <%= ab %> <% end %>",
        {abc = '1 <3>&" ', cnt = 3}),
        ' nil  nil  nil ', "tmpl2")
    local r, msg = pcall(http_lib.template, "<% ab() %>", {ab = '1'})
    t.assert(r == false and msg:match("call local 'ab'") ~= nil, "bad template")

    -- gh-18: rendered tempate is truncated
    local template = [[
<html>
<body>
    <table border="1">
    % for i,v in pairs(t) do
    <tr>
    <td><%= i %></td>
    <td><%= v %></td>
    </tr>
    % end
    </table>
</body>
</html>
]]

    local tt = {}
    for i=1, 100 do
        tt[i] = string.rep('#', i)
    end

    local rendered = http_lib.template(template, { t = tt })
    t.assert(#rendered > 10000, "rendered size")
    t.assert_equals(rendered:sub(#rendered - 7, #rendered - 1), "</html>", "rendered eof")
end

g.test_parse_request = function()

    t.assert_equals(http_lib._parse_request('abc'),
        { error = 'Broken request line', headers = {} }, 'broken request')



    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").path,
        '/',
        'path'
    )
    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").proto,
        {1,1},
        'proto'
    )
    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").headers,
        {host = 's.com'},
        'host'
    )
    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").method,
        'GET',
        'method'
    )
    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").query,
        '',
        'query'
    )
end

g.test_params = function()
    t.assert_equals(http_lib.params(), {}, 'nil string')
    t.assert_equals(http_lib.params(''), {}, 'empty string')
    t.assert_equals(http_lib.params('a'), {a = ''}, 'separate literal')
    t.assert_equals(http_lib.params('a=b'), {a = 'b'}, 'one variable')
    t.assert_equals(http_lib.params('a=b&b=cde'), {a = 'b', b = 'cde'}, 'some')
    t.assert_equals(http_lib.params('a=b&b=cde&a=1'),
        {a = { 'b', '1' }, b = 'cde'}, 'array')
end
