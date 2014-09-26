# http - a [Tarantool][] rock for an HTTP client and a server

[![Build Status](https://travis-ci.org/tarantool/http.png?branch=master)](https://travis-ci.org/tarantool/http)

## Getting Started

### Installation

Add http://rocks.tarantool.org to your luarocks repository.
Then use `luarocks install http`

### Usage

``` lua
    client = require('http.client')
    print(client.get("http://mail.ru/").status)
```

## HTTP client

Any kind of HTTP 1.1 query (no SSL support yet).

### box.http.request(method, url, body[, opts])

Issue an HTTP request at the given URL (`url`).
`method` can be either `GET` or `POST`.

If `body` is `nil`, the body is an empty string, otherwise
the string passed in `body`.

`opts` is an optional Lua table with methods, and may contain the following
keys:

* `headers` - additional HTTP headers to send to the server

Returns a Lua table with:

* `status` - HTTP response status
* `reason` - HTTP response status text
* `headers` - a Lua table with normalized HTTP headers
* `body` - response body
* `proto` - protocol version

#### Example

```lua

    r = box.http.request('GET', 'http://google.com')
    r = box.http.request('POST', 'http://google.com', {}, 'text=123')

```
## HTTP server

The server is an object which is configured with HTTP request
handlers, routes (paths), templates, and a port to bind to.
Unless Tarantool is running under a superuser, ports numbers
below 1024 may be unavailable.

The server can be started and stopped any time. Multiple
servers can be creatd.

To start a server:

* create it: `httpd = box.httpd.new(...)`
* configure "routing" `httpd:route(...)`
* start it with `httpd:start()`
* stop with `httpd:stop()`

### `box.httpd.new()` - create an HTTP server

```lua
    httpd = box.httpd.new(host, port[, { options } ])
```

'host' and 'port' must  contain the interface and port to bind to.
'options' may contain:

* `max_header_size` (default is 4096 bytes) - a limit on 
HTTP request header size
* `header_timeout` (default: 100 seconds) - a time out until
the server stops reading HTTP headers sent by the client.
The server closes the client connection if the client can't 
manage to send its headers in the given amount of time.
* `app_dir` (default: '.', the server working directory) - 
a path to the directory with HTML templates and controllers
* `handler` - a Lua function to handle HTTP requests (this is 
a handler to use if the module "routing" functionality is not
needed).
* `charset` - the character set for server responses of 
type `text/html`, `text/plain` and `application/json`.

#### Arguments of the `handler()` callback

If `handler` is given in httpd options, it gets
involved on every HTTP request, and the built-in routing
mechanism is unused.
The arguments of `handler` are:

* `proto` - protocol version
* `path` - request path (like, '/index.html')
* `query` - a string with GET or POST request arguments
* `method` - a string with request type ("GET" or "POST")
* `body` - request body

The function is expected to return a Lua table (array) with
these elements:

1. HTTP response code
1. a Lua table with normalized headers (pass 'nil' for default headers)
1. response body (pass 'nil' for empty body)

```lua

	function my_handler(httpd, request)
		return {
			200,
			{ ['content-type'] = 'text/html; charset=utf8' },
			[[
				<html>
					<body>Hello, world!</body>
				</html>
			]]
		}
	end

```

### Using routes

It is possible to automatically route requests between different
handlers, depending on request path. The routing API is inspired
by [Mojolicious](http://mojolicio.us/perldoc/Mojolicious/Guides/Routing) API.

Routes can be defined using either:

1. and exact match, e.g. "index.php"
1. with simple regular expressions
1. with extended regular expressions

Route examples:

```text

'/'                 -- a simple route
'/abc'              -- a simple route
'/abc/:cde'         -- a route using a simple regular expression
'/abc/:cde/:def'    -- a route using a simple regular expression
'/ghi*path'         -- a route using an extended regular expression

```

To conigure a route, use 'route()' method of httpd object:

```lua
httpd:route({ path = '/path/to' }, 'controller#action')
httpd:route({ path = '/', template = 'Hello <%= var %>' }, handle1)
httpd:route({ path = '/:abc/cde', file = 'users.html.el' }, handle2)
...

```

`route()` first argument is a Lua table with one or several keys:

* `file` - a template file name (if relative, then to path
  `{app_dir}/tempalates`, where app_dir is the path set when creating the
server). If no template file name extention is provided, the extention is
set to ".html.el", meaning HTML with embedded Lua
* `template` - template Lua variable name, in case the template
is a Lua variable. If `template` is a function, it's called on every
request to get template body. This is useful if template body must be
taken from a database
* `path` - route path, as described earlier
* `name` - route name

The second argument is the route handler to be used to produce
a response to the request.

A typical usage is to avoid passing `file` and `template` arguments, 
since these take time to evaluate, but these arguments are useful
for writing tests or defining HTTP servers with just one "route".

The handler can also be passed as a string of form 'filename#functionname'.
In that case, handler body is taken from a file in `{app_dir}/controllers` directory.

#### Summary of the stuff in `app_dir`

* `public` - is a path to store static content. Anything in this path
defines a route which matches the file name, and the server serves this
file automatically, as is. Note, that the server doesn't use sendfile(),
and reads the entire content of the file in memory before passing
it to the client. Caching is used, unless is turned on. So this is 
suitable for large files, use nginx instad.
* `templates` -  a path to templates
* `controllers` - a path to Lua controllers lua. For example,
controller name 'module.submodule#foo' maps to `{app_dir}/controllers/module.submodule.lua`.

#### Route handlers

A route handler is much simpler than a generic handler and is passed
a single Lua table with the following keys:

* `req` - the request itself
* `resp` - an object to prepare a response

`resp` object has the following methods:

* `stash(name[, value])` - get or set a variable "stashed"
when dispatching a route:

```lua

    function hello(self)
        local id = self:stash('id')    -- сюда попадет часть :id
        local user = box.space.users:select(id)
        if user == nil then
            return self:redirect_to('/users_not_found')
        end
        return self:render({ user = user  })
    end

    httpd = box.httpd.new('127.0.0.1', 8080)
    httpd:route(
        { path = '/:id/view', template = 'Hello, <%= user.name %>' }, hello)
    httpd:start()

```

* `redirect_to` - to be used for HTTP redirection
* `render({})` - to render a template
* `cookie` - to get a cookie in the request, or pass a cookie to the
client in the response
* `url_for` - returns the route exact URL

##### Special stash names

* `controller` - controller name
* `action` - handler name in the controller
* `format` - the current output format (e.g. `html`, `txt`). Is
detected automatically based on request `path` (for example, `/abc.js` -
sets `format` to `js`). When producing a response, `format` is used
to set response 'Content-type:'.

#### Working with cookies

Do get a cookie, use:

```lua

    function show_user(self)

        local uid = self:cookie('id')

        if uid ~= nil and string.match(uid, '^%d$') ~= nil then

            local user = box.select(users, 0, uid)
            return self:render({ user = user })
        end

        return self:redirect_to('/login')
    end
```

To set a cookie, use `cookie()` method as well, but pass in a Lua
table defining the cookie to be set:

```lua

    function user_login(self)

        local login = self:param('login')
        local password = self:param('password')

        local user = box.select(users, 1, login, password)
        if user ~= nil then
            self:cookie({ name = 'uid', value = user[0], expires = '+1y' })
            return self:reditect_to('/')
        end

        -- do login again and again and again
        return self:redirect_to('/login')
    end
```

The table must contain the following fields:

* `name`
* `value`
* `path` (optional, if not set, the current request path is used)
* `domain` (optional)
* `expires` - cookie expire date, or expire offset, for example:

 * `1d`  - 1 day
 * `+1d` - the same
 * `23d` - 23 days
 * `+1m` - 1 month (30 days)
 * `+1y` - 1 year (365 days)


#### Request methods and attributes:

* `req.method` - HTTP request type (`GET`, `POST` etc)
* `req.path` - request path
* `req.query` - request arguments
* `req.proto` - HTTP version (for example, `{ 1, 1 }` is `HTTP/1.1`)
* `req.body` - request body (the entire request body is read from the 
socket at once)
* `req.headers` - normalized request headers. A normalized header
is in lower case, all headers joined together into a single string.

* `req:to_string()` - returns a string representation of the request
* `req:request_line()` - returns request body
* `req:query_param(name)` - returns a single GET request parameter value. 
If name is `nil`, returns a Lua table withall arguments
* `req:post_param(name)` - returns a single POST request parameter value.
If `name` is `nil`, returns all parameters as a Lua table.
* `req:param(name)` - any request parameter, either GET or POST

### Rendering a template

Lua can be used inside a response template, for example:

```html
<html>
    <head>
        <title><%= title %></title>
    </head>
    <body>
        <ul>
            % for i = 1, 10 do
                <li><%= item[i].key %>: <%= item[i].value %></li>
            % end
        </ul>
    </body>
</html>
```

To embed Lua into a template, use:

* `<% lua-here %>` - insert any Lua code, including multi-line. 
Can be used in any location in the template.
* `% lua-here` - a single line Lua substitution. Can only be
present in the beginning of a line (with optional preceding spaces
and tabs, which are ignored).

A few control characters may follow `%`:

* `=` (e.g., `<%= value + 1 %>`) - runs the embedded Lua
and inserts the result into HTML. HTML special characters, 
such as `<`, `>`, `&`, `"` are escaped.
* `==` (e.g., `<%== value + 10 %>`) - the same, but with no
escaping.

A Lua statement inside the template has access to the following
environment:

1. the Lua variables defined in the template
1. the stashed variables
1. the variables standing for keys in the `render` table

#### Helpers

Helpers are special functions for use in HTML templates, available
in all templates. They must be defined when creating an httpd object.

Setting or deleting a helper:

```lua

	-- setting a helper
	httpd:helper('time', function(self, ...) return box.time() end)
	-- deleting a helper
	httpd:helper('some_name', nil)

```

Using a helper inside an HTML template:

```html
<div>
	Current timestamp: <%= time() %>
</div>
```

A helper function can receive arguments. The first argument is 
always the current controller. The rest is whatever is
passed to the helper from the template.

### Hooks

It is possible to define additional functions invoked at various
stages of request processing.

#### `before_routes(httpd, request)`

Is invoked before a request is routed to a handler. The first
argument of the hook is the HTTP request to be handled.
The return value of the hook is ignored.

This hook could be used to log a request, or modify request headers.

### `after_dispatch(cx, resp)`

Is invoked after a handler for a route is executed.

The argument of the hook is the request, passed into the handler, 
and the response produced by the handler.

This hook can be used to modify the response. 
The return value of the hook is ignored.


For additional examples, see [documentation][Documentation] and
[tests][Tests].

## See Also

 * [Tarantool][]
 * [Documentation][]
 * [Tests][]

[Tarantool]: http://github.com/tarantool/tarantool
[Documentation]: https://github.com/tarantool/http/wiki
[Tests]: https://github.com/tarantool/http/tree/master/test