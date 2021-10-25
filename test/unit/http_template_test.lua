local t = require('luatest')
local http_lib = require('http.lib')

local g = t.group()

g.test_template_1 = function()
    t.assert_equals(http_lib.template("<% for i = 1, cnt do %> <%= abc %> <% end %>",
                                     {abc = '1 <3>&" ', cnt = 3}),
                   ' 1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;  ',
                   'tmpl1')
end

g.test_template_2 = function()
    t.assert_equals(http_lib.template('<% for i = 1, cnt do %> <%= ab %> <% end %>',
                                     {abc = '1 <3>&" ', cnt = 3}),
                   ' nil  nil  nil ', 'tmpl2')
end

g.test_broken_template = function()
    local r, msg = pcall(http_lib.template, '<% ab() %>', {ab = '1'})
    t.assert(r == false and msg:match("call local 'ab'") ~= nil, 'bad template')
end

g.test_rendered_template_truncated_gh_18 = function()
    local template = [[
<html>
<body>
    <table border='1'>
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

    local rendered, _ = http_lib.template(template, { t = tt })
    t.assert(#rendered > 10000, 'rendered size')
    t.assert_equals(rendered:sub(#rendered - 7, #rendered - 1), '</html>', 'rendered eof')
end

g.test_incorrect_arguments_escaping_leads_to_segfault_gh_51 = function()
    local template = [[<%= {{continue}} %>"]]
    local result = http_lib.template(template, {continue = '/'})
    t.assert(result:find('\"') ~= nil)
end
