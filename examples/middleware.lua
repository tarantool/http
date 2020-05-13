#!/usr/bin/env tarantool
local http_router = require('http.router')
local http_server = require('http.server')
local tsgi = require('http.tsgi')
local json = require('json')
local log = require('log')

local httpd = http_server.new('127.0.0.1', 8080, {
    log_requests = true,
    log_errors = true
})
local router = http_router.new()

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

router:route({method = 'GET', path = '/fruits/apple'}, function()
    return {status = 200, body = json.encode({kind = 'apple'})}
end)

router:route({method = 'GET', path = '/fruits/orange'}, function()
    return {status = 200, body = json.encode({kind = 'orange'})}
end)

assert(router:use(swap_orange_and_apple, {
    preroute = true,
    name = 'swap_orange_and_apple',
    method = 'GET',
    path = '/fruits/.*',
}), 'conflict on adding swap_orange_and_apple')

assert(router:use(add_helloworld_to_response, {
    name = 'hello_world',
    method = 'GET',
    path = '/fruits/.*',
}), 'conflict on adding hello_world middleware')

httpd:set_router(router)
httpd:start()
