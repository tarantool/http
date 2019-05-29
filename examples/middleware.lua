#!/usr/bin/env tarantool
local http_router = require('http.router')
local http_server = require('http.server')
local tsgi = require('http.tsgi')
local json = require('json')
local log = require('log')

box.cfg{}  -- luacheck: ignore

local httpd = http_server.new('127.0.0.1', 12345, {
    log_requests = true,
    log_errors = true
})

local function swap_orange_and_apple(env)
    local path_info = env['PATH_INFO']
    log.info('swap_orange_and_apple: path_info = %s', path_info)
    if path_info == '/fruits/orange' then
        env['PATH_INFO'] = '/fruits/apple'
    elseif path_info == '/fruits/apple' then
        env['PATH_INFO'] = '/fruits/orange'
    end

    return tsgi.next(env)
end

local function add_helloworld_to_response(env)
    local resp = tsgi.next(env)
    if resp.body == nil then
        return resp
    end

    local lua_body = json.decode(resp.body)
    lua_body.message = 'hello world!'
    resp.body = json.encode(lua_body)

    return resp
end

local function apple_handler(_)
    return {status = 200, body = json.encode({kind = 'apple'})}
end

local function orange_handler(_)
    return {status = 200, body = json.encode({kind = 'orange'})}
end

local router = http_router.new()
    :route({
            method = 'GET',
            path = '/fruits/apple',
        },
        apple_handler
    )
    :route({
            method = 'GET',
            path = '/fruits/orange',
        },
        orange_handler
    )

local ok = router:use({
    preroute = true,
    name = 'swap_orange_and_apple',
    method = 'GET',
    path = '/fruits/.*',
    handler = swap_orange_and_apple,
})
assert(ok, 'no conflict on adding swap_orange_and_apple')

ok = router:use({
    name = 'hello_world',
    method = 'GET',
    path = '/fruits/.*',
    handler = add_helloworld_to_response,
})
assert(ok, 'no conflict on adding hello_world middleware')


httpd:set_router(router)
httpd:start()
