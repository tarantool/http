<a href="http://tarantool.org">
   <img src="https://avatars2.githubusercontent.com/u/2344919?v=2&s=250"
align="right">
</a>

# HTTP server for Tarantool 1.7.5+

[![Build Status](https://travis-ci.org/tarantool/http.svg?branch=master)](https://travis-ci.org/tarantool/http)

> **DISCLAIMER:** Any functionality not described here is subject to change
> in backward incompatible fashion at any time. Don't rely on source code
> internals.

> **Note:** In Tarantool 1.7.5+, a full-featured HTTP client is available aboard.
> For Tarantool 1.6.5+, both HTTP server and client are available
> [here](https://github.com/tarantool/http/tree/tarantool-1.6).

## Table of contents

* [Prerequisites](#prerequisites)
* [Installation](#installation)
* [Usage](#usage)
* [Creating a server](#creating-a-server)
* [Using routes](#using-routes)
* [Route handlers](#route-handlers)
  * [Fields and methods of the Request object](#fields-and-methods-of-the-request-object)
  * [Fields and methods of the Response object](#fields-and-methods-of-the-response-object)
  * [Examples](#examples)
* [Working with stashes](#working-with-stashes)
* [Working with cookies](#working-with-cookies)
* [Middleware](#middleware)
  * [router:use(f, opts)](#routerusef-opts)
  * [f](#f)
  * [Ordering](#ordering)
  * [Example](#example)

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

There are 4 main logical objects you can operate with:
1. **server**, which can be nginx or built-in
2. **router**, where you define routes and middleware
3. **route**, a function processing HTTP requests
4. **middleware**, a function invoked before route handler is invoked

The **server** is an object which implements HTTP protocol and handles all
lower level stuff like TCP connection.
Unless Tarantool is running under a superuser, port numbers
below 1024 may be unavailable.

The server can be started and stopped anytime. Multiple
servers can be created.

The **router** is where you define how and who will handle your requests
configured with HTTP request handlers, routes (paths), templates,
and a port to bind to. You need to set the router to a server, for it to be used.

To start a server with a router:

1. [Create a server](#creating-a-server) with `server = require('http.server').new(...)`.
2. [Create a router](#creating-a-router) with `router = require('http.router').new(...)`.
3. Set a router to server with `server:set_router(router)`.
4. [Configure routing](#using-routes) with `router:route(...)`.
5. Start serving HTTP requests it with `server:start()`.

To stop the server, use `server:stop()`.

## Creating a server

```lua
server = require('http.server').new(host, port[, { options } ])
```

`host` and `port` must contain:
* For tcp socket: the host and port to bind to.
* For unix socket: `unix/` and path to socket (for example `/tmp/http-server.sock`) to bind to.

`options` may contain:

* `handler` - a Lua function to handle HTTP requests (this is
  a handler to use if the module "routing" functionality is not
  needed).
* `display_errors` - return application errors and backtraces to the client
  (like PHP).
* `log_errors` - log application errors using `log.error()`.
* `log_requests` - log incoming requests.

## Creating a router

```lua
router = require('http.router').new(options)
server:set_router(router)
```

`options` may contain:

* `charset` - the character set for server responses of
  type `text/html`, `text/plain` and `application/json`.

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
httpd:route({ path = '/objects', method = 'GET' }, handle3)
...
```

The first argument for `route()` is a Lua table with one or more keys:

| key | description |
| --- | ----------- |
| `path` | route path, as described earlier. |
| `name` | route name. |
| `method` | method on the route like `POST`, `GET`, `PUT`, `DELETE` |

The second argument is the route handler to be used to produce
a response to the request.

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

| method | description |
| ------ | ----------- |
| `req:method()` | HTTP request type (`GET`, `POST` etc). |
| `req:path()` | request path. |
| `req:query()` | request arguments. |
| `req:proto()` | HTTP version (for example, `{ 1, 1 }` is `HTTP/1.1`). |
| `req:headers()` | normalized request headers. A normalized header. |
| `req:header(name)` | value of header `name`. |
| `req:peer()` | a Lua table with information about the remote peer (like `socket:peer()`).  **NOTE**: when router is being used with nginx adapter, `req:peer()` contains information on iproto connection with nginx, not the original HTTP user-agent. |
| `tostring(req)` | returns a string representation of the request.
| `req:request_line()` | returns the request body.
| `req:read(delimiter\|chunk\|{delimiter = x, chunk = x}, timeout)` | reads the raw request body as a stream (see `socket:read()`). **NOTE**: when using NGINX TSGI adapter, only `req:read(chunk)` is available. |
| `req:post_param(name)` | returns a single POST request a parameter value.  If `name` is `nil`, returns all parameters as a Lua table. |
| `req:query_param(name)` | returns a single GET request parameter value.  If `name` is `nil`, returns a Lua table with all arguments. |
| `req:param(name)` | any request parameter, either GET or POST. |
| `req:cookie(name)` | to get a cookie in the request. |
| `req:stash(name[, value])` | **NOTE**: currently not supported inside middleware handlers. Get or set a variable "stashed" when dispatching a route. |
| `req:url_for(name, args, query)` | returns the route's exact URL.
| `req:redirect_to` | create a **Response** object with an HTTP redirect.
| `req:next()` | in middleware invokes remaining middleware chain and route handler and returns the response |
| `req:hijack()` | terminates HTTP connection. Open TCP connection object is returned |

### Fields and methods of the Response object

| method | description |
| ------ | ----------- |
| `resp.status` | HTTP response code.
| `resp.headers` | a Lua table with normalized headers.
| `resp.body` | response body (string|table|wrapped\_iterator).
| `resp:setcookie({ name = 'name', value = 'value', path = '/', expires = '+1y', domain = 'example.com'))` | adds `Set-Cookie` headers to `resp.headers`.

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

## Middleware

tarantool/http v2 comes with improved middleware support:
1. middleware functions control both HTTP request arrival and HTTP response
return in the same function. As opposed to v1 functions `before_dispatch()`, `after_dispatch()`.
2. filters on path and method: if request doesn't match path pattern or
method, the middleware won't be invoked for this particular request.
3. you can modify order of middleware execution by specifying relations
between middlewares via optional `opts.after` / `opts.before` arrays on
middleware creation (see below).

### `router:use(f, opts)`

#### Parameters

| parameter   | type   | description      |
| ----------- | ------ | ---------------- |
| `f` | response = function(req) | see explanation below |
| `opts.path` | string | as in `route(f)` |
| `opts.method` | string | as in `route()` |
| `opts.preroute` | bool | when true, middleware will be invoked before routing |
| `opts.name` | string | middleware name that is referred to when defining order between middleware.
| `opts.before` | array of strings | middleware names that must be invoked before this middleware |
| `opts.after` | array of strings | middleware names that must be invoked after this middleware |
| `return-value` | bool | true, if middleware is added successfully, false otherwise |

#### f
`f` has the same signature as route handler.

Inside `f` use `req:next()` to call next function, which can be
another middleware handler or a terminating route handler.

**NOTE**: `req:stash()` is currently not working inside middleware handlers.

Alternatively, you can return response from `f` before calling
`req:next()` (early exit), in this case the request will not be
dispatched to the route handler.

This is convenient for example in authorization middleware functions,
where you can exit with 403 Forbidden on authorization failure.

#### Ordering

By default, if you don't specify `before`/`after` options in `router:use()`,
the order of invokation for any request is the **definition order** (of
course, if some middleware is filtered-out, it won't be executed)

If you need more complex order of execution between middleware handlers,
you can do so by providing local execution order:

```lua
local ok_b = router:use(b, {name = 'c', before = 'a'})
local ok_a = router:use(a, {name = 'a'})
local ok_c = router:use(c, {name = 'b', after = 'a'})
-- order is a -> b -> c -> route-handler (where "->" is invokation via `req:next()`)

local ok_d = router:use(d, {before = 'a', after = 'c'})
assert(ok_d) -- FAIL: cannot satisfy order without breaking specified dependencies
```

Internally, in any time, a total-order of middleware is maintained.
If upon adding new middleware such total-order becomes non-existing,
the middleware addition is rejected.

#### Example
```lua
local users = require('myproject.users')

local json = require('json')
local digest = require('digest')

local function basic_auth_handler(req)
  local auth = req:header('authorization')
  if not auth or not auth:find('Basic ') then
    return {
      status = 401,
      body = json.encode({message = 'Missing Authorization Header'})
    }
  end

  local base64_credentials = auth:split(' ')[2]
  local credentials = digest.base64_decode(base64_credentials)
  local username = credentials:split(':')[1]
  local password = credentials:split(':')[2]

  local user = users.authenticate(username, password)
  if not user then
    return {
      status = 401,
      body = json.encode({message = 'Invalid Authentication Credentials'})
    }
  end

  req.user = user

  return req:next()
end

local ok = router:use(basic_auth_handler, {
  path = '/api/v1',  -- e.g. in API v2 a different
                     -- authentication mechanism is used
  method = 'ANY',
})
```
