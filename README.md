<a href="http://tarantool.org">
   <img src="https://avatars2.githubusercontent.com/u/2344919?v=2&s=250"
align="right">
</a>

# HTTP server for Tarantool 1.7.5+

[![Build Status](https://travis-ci.org/tarantool/http.png?branch=tarantool-1.7)](https://travis-ci.org/tarantool/http)

> **Note:** In Tarantool 1.7.5+, a full-featured HTTP client is available aboard.
> For Tarantool 1.6.5+, both HTTP server and client are available
> [here](https://github.com/tarantool/http/tree/tarantool-1.6).

## Table of contents

* [Prerequisites](#prerequisites)
* [Installation](#installation)
* [Usage](#usage)
* [Creating a server](#creating-a-server)
* [Using routes](#using-routes)
* [Contents of app\_dir](#contents-of-app_dir)
* [Route handlers](#route-handlers)
  * [Fields and methods of the Request object](#fields-and-methods-of-the-request-object)
  * [Fields and methods of the Response object](#fields-and-methods-of-the-response-object)
  * [Examples](#examples)
* [Working with stashes](#working-with-stashes)
  * [Special stash names](#special-stash-names)
* [Working with cookies](#working-with-cookies)
* [Rendering a template](#rendering-a-template)
* [Template helpers](#template-helpers)
* [Hooks](#hooks)
  * [handler(httpd, req)](#handlerhttpd-req)
  * [before\_dispatch(httpd, req)](#before_dispatchhttpd-req)
  * [after\_dispatch(cx, resp)](#after_dispatchcx-resp)
* [See also](#see-also)

## Prerequisites

 * Tarantool 1.7.5+ with header files (`tarantool` && `tarantool-dev` packages)

## Installation

You can:

* clone the repository and build the `http` module using CMake:

  ``` bash
  git clone https://github.com/tarantool/http.git
  cd http && cmake . -DCMAKE_BUILD_TYPE=RelWithDebugInfo
  make
  make install
  ```

* install the `http` module using `tarantoolctl`:

  ``` bash
  tarantoolctl rocks install http
  ```

* install the `http` module using LuaRocks
  (see [TarantoolRocks](https://github.com/tarantool/rocks) for
  LuaRocks configuration details):

  ``` bash
  luarocks install https://raw.githubusercontent.com/tarantool/http/master/rockspecs/http-scm-1.rockspec --local
  ```

## Usage

The server is an object which is configured with HTTP request
handlers, routes (paths), templates, and a port to bind to.
Unless Tarantool is running under a superuser, port numbers
below 1024 may be unavailable.

The server can be started and stopped anytime. Multiple
servers can be created.

To start a server:

1. [Create it](#creating-a-server) with `httpd = require('http.server').new(...)`.
2. [Configure routing](#using-routes) with `httpd:route(...)`.
3. Start it with `httpd:start()`.

To stop the server, use `httpd:stop()`.

## Creating a server

```lua
httpd = require('http.server').new(host, port[, { options } ])
```

`host` and `port` must contain:
* For tcp socket: the host and port to bind to.
* For unix socket: `unix/` and path to socket (for example `/tmp/http-server.sock`) to bind to.

`options` may contain:

* `max_header_size` (default is 4096 bytes) - a limit for
  HTTP request header size.
* `header_timeout` (default: 100 seconds) - a timeout until
  the server stops reading HTTP headers sent by the client.
  The server closes the client connection if the client doesn't
  send its headers within the given amount of time.
* `app_dir` (default is '.', the server working directory) -
  a path to the directory with HTML templates and controllers.
* `handler` - a Lua function to handle HTTP requests (this is
  a handler to use if the module "routing" functionality is not
  needed).
* `charset` - the character set for server responses of
  type `text/html`, `text/plain` and `application/json`.
* `display_errors` - return application errors and backtraces to the client
  (like PHP).
* `log_requests` - log incoming requests. This parameter can receive:
    - function value, supporting C-style formatting: log_requests(fmt, ...), where fmt is a format string and ... is Lua Varargs, holding arguments to be replaced in fmt.
    - boolean value, where `true` choose default `log.info` and `false` disable request logs at all.

  By default uses `log.info` function for requests logging.
* `log_errors` - same as the `log_requests` option but is used for error messages logging. By default uses `log.error()` function.

## Using routes

It is possible to automatically route requests between different
handlers, depending on the request path. The routing API is inspired
by [Mojolicious](http://mojolicio.us/perldoc/Mojolicious/Guides/Routing) API.

Routes can be defined using:

* an exact match (e.g. "index.php")
* simple regular expressions
* extended regular expressions

Route examples:

```text
'/'                 -- a simple route
'/abc'              -- a simple route
'/abc/:cde'         -- a route using a simple regular expression
'/abc/:cde/:def'    -- a route using a simple regular expression
'/ghi*path'         -- a route using an extended regular expression
```

To configure a route, use the `route()` method of the `httpd` object:

```lua
httpd:route({ path = '/path/to' }, 'controller#action')
httpd:route({ path = '/', template = 'Hello <%= var %>' }, handle1)
httpd:route({ path = '/:abc/cde', file = 'users.html.el' }, handle2)
httpd:route({ path = '/objects', method = 'GET' }, handle3)
...
```

The first argument for `route()` is a Lua table with one or more keys:

* `file` - a template file name (can be relative to.
  `{app_dir}/templates`, where `app_dir` is the path set when creating the
  server). If no template file name extension is provided, the extension is
  set to ".html.el", meaning HTML with embedded Lua.
* `template` - template Lua variable name, in case the template
  is a Lua variable. If `template` is a function, it's called on every
  request to get template body. This is useful if template body must be
  taken from a database.
* `path` - route path, as described earlier.
* `name` - route name.
* `method` - method on the route like `POST`, `GET`, `PUT`, `DELETE`
* `log_requests` - option that overrides the server parameter of the same name but only for current route.
* `log_errors` - option that overrides the server parameter of the same name but only for current route.

The second argument is the route handler to be used to produce
a response to the request.

The typical usage is to avoid passing `file` and `template` arguments,
since they take time to evaluate, but these arguments are useful
for writing tests or defining HTTP servers with just one "route".

The handler can also be passed as a string of the form 'filename#functionname'.
In that case, the handler body is taken from a file in the
`{app_dir}/controllers` directory.

## Contents of `app_dir`

* `public` - a path to static content. Everything stored on this path
  defines a route which matches the file name, and the HTTP server serves this
  file automatically, as is. Notice that the server doesn't use `sendfile()`,
  and it reads the entire content of the file into the memory before passing
  it to the client. ??? Caching is not used, unless turned on. So this is not
  suitable for large files, use nginx instead.
* `templates` -  a path to templates.
* `controllers` - a path to *.lua files with Lua controllers. For example,
  the controller name 'module.submodule#foo' is mapped to
  `{app_dir}/controllers/module.submodule.lua`.

## Route handlers

A route handler is a function which accepts one argument (**Request**) and
returns one value (**Response**).

```lua
function my_handler(req)
    -- req is a Request object
    -- resp is a Response object
    local resp = req:render({text = req.method..' '..req.path })
    resp.headers['x-test-header'] = 'test';
    resp.status = 201
    return resp
end
```

### Fields and methods of the Request object

* `req.method` - HTTP request type (`GET`, `POST` etc).
* `req.path` - request path.
* `req.query` - request arguments.
* `req.proto` - HTTP version (for example, `{ 1, 1 }` is `HTTP/1.1`).
* `req.headers` - normalized request headers. A normalized header
  is in the lower case, all headers joined together into a single string.
* `req.peer` - a Lua table with information about the remote peer
  (like `socket:peer()`).
* `tostring(req)` - returns a string representation of the request.
* `req:request_line()` - returns the request body.
* `req:read(delimiter|chunk|{delimiter = x, chunk = x}, timeout)` - reads the
  raw request body as a stream (see `socket:read()`).
* `req:json()` - returns a Lua table from a JSON request.
* `req:post_param(name)` - returns a single POST request a parameter value.
  If `name` is `nil`, returns all parameters as a Lua table.
* `req:query_param(name)` - returns a single GET request parameter value.
  If `name` is `nil`, returns a Lua table with all arguments.
* `req:param(name)` - any request parameter, either GET or POST.
* `req:cookie(name)` - to get a cookie in the request.
* `req:stash(name[, value])` - get or set a variable "stashed"
  when dispatching a route.
* `req:url_for(name, args, query)` - returns the route's exact URL.
* `req:render({})` - create a **Response** object with a rendered template.
* `req:redirect_to` - create a **Response** object with an HTTP redirect.

### Fields and methods of the Response object

* `resp.status` - HTTP response code.
* `resp.headers` - a Lua table with normalized headers.
* `resp.body` - response body (string|table|wrapped\_iterator).
* `resp:setcookie({ name = 'name', value = 'value', path = '/', expires = '+1y', domain = 'example.com'))` -
  adds `Set-Cookie` headers to `resp.headers`.

### Examples

```lua
function my_handler(req)
    return {
        status = 200,
        headers = { ['content-type'] = 'text/html; charset=utf8' },
        body = [[
            <html>
                <body>Hello, world!</body>
            </html>
        ]]
    }
end
```

## Working with stashes

```lua
function hello(self)
    local id = self:stash('id')    -- here is :id value
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

### Special stash names

* `controller` - the controller name.
* `action` - the handler name in the controller.
* `format` - the current output format (e.g. `html`, `txt`). Is
  detected automatically based on the request's `path` (for example, `/abc.js`
  sets `format` to `js`). When producing a response, `format` is used
  to serve the response's 'Content-type:'.

## Working with cookies

To get a cookie, use:

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

To set a cookie, use the `setcookie()` method of a response object and pass to
it a Lua table defining the cookie to be set:

```lua
function user_login(self)
    local login = self:param('login')
    local password = self:param('password')

    local user = box.select(users, 1, login, password)
    if user ~= nil then
        local resp = self:redirect_to('/')
        resp:setcookie({ name = 'uid', value = user[0], expires = '+1y' })
        return resp
    end

    -- to login again and again and again
    return self:redirect_to('/login')
end
```

The table must contain the following fields:

* `name`
* `value`
* `path` (optional; if not set, the current request path is used)
* `domain` (optional)
* `expires` - cookie expire date, or expire offset, for example:

  * `1d`  - 1 day
  * `+1d` - the same
  * `23d` - 23 days
  * `+1m` - 1 month (30 days)
  * `+1y` - 1 year (365 days)

## Rendering a template

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

To embed Lua code into a template, use:

* `<% lua-here %>` - insert any Lua code, including multi-line.
  Can be used anywhere in the template.
* `% lua-here` - a single-line Lua substitution. Can only be
  present at the beginning of a line (with optional preceding spaces
  and tabs, which are ignored).

A few control characters may follow `%`:

* `=` (e.g., `<%= value + 1 %>`) - runs the embedded Lua code
  and inserts the result into HTML. Special HTML characters,
  such as `<`, `>`, `&`, `"`, are escaped.
* `==` (e.g., `<%== value + 10 %>`) - the same, but without
  escaping.

A Lua statement inside the template has access to the following
environment:

1. Lua variables defined in the template,
1. stashed variables,
1. variables standing for keys in the `render` table.

## Template helpers

Helpers are special functions that are available in all HTML
templates. These functions must be defined when creating an `httpd` object.

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

## Hooks

It is possible to define additional functions invoked at various
stages of request processing.

### `handler(httpd, req)`

If `handler` is present in `httpd` options, it gets
involved on every HTTP request, and the built-in routing
mechanism is unused (no other hooks are called in this case).

### `before_dispatch(httpd, req)`

Is invoked before a request is routed to a handler. The first
argument of the hook is the HTTP request to be handled.
The return value of the hook is ignored.

This hook could be used to log a request, or modify request headers.

### `after_dispatch(cx, resp)`

Is invoked after a handler for a route is executed.

The arguments of the hook are the request passed into the handler,
and the response produced by the handler.

This hook can be used to modify the response.
The return value of the hook is ignored.

## See also

 * [Tarantool project][Tarantool] on GitHub
 * [Tests][] for the `http` module

[Tarantool]: http://github.com/tarantool/tarantool
[Tests]: https://github.com/tarantool/http/tree/master/test
