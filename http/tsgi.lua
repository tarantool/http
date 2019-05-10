-- TSGI helper functions

local KEY_HTTPD = 'tarantool.http.httpd'
local KEY_SOCK = 'tarantool.http.sock'
local KEY_REMAINING = 'tarantool.http.sock_remaining_len'
local KEY_PARSED_REQUEST = 'tarantool.http.parsed_request'
local KEY_PEER = 'tarantool.http.peer'

-- XXX: do it with lua-iterators
local function headers(env)
    local map = {}
    for name, value in pairs(env) do
        if string.startswith(name, 'HEADER_') then  -- luacheck: ignore
            map[name] = value
        end
    end
    return map
end

return {
    KEY_HTTPD = KEY_HTTPD,
    KEY_SOCK = KEY_SOCK,
    KEY_REMAINING = KEY_REMAINING,
    KEY_PARSED_REQUEST = KEY_PARSED_REQUEST,
    KEY_PEER = KEY_PEER,

    headers = headers,
}
