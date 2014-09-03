-- http.client

local lib = require('http.lib') -- native library
local socket = require('socket')
local errno = require('errno')
local log = require('log')

local function errorf(fmt, ...)
    error(string.format(fmt, ...))
end

local function retcode(code, reason)
    return {
        status  = code,
        reason  = reason
    }
end

local function ucfirst(str)
    return (str:gsub("^%l", string.upper))
end

local function request(method, url, body, opts)
    if opts == nil then
        opts = {}
    end

    local hdrs = opts.headers
    if hdrs == nil then
        hdrs = {}
    end

    local ho = {}
    for k, v in pairs(hdrs) do
        ho[ string.lower(k) ] = v
    end
    hdrs = ho
    ho = nil

    method = string.upper(method)
    if method ~= 'GET' and method ~= 'POST' then
        return retcode(599, "Unknown request method: " .. method)
    end

    local scheme, host, port, path, query = lib.split_url( url )
    if scheme ~= 'http' then
        return retcode(599, "Unknown scheme: " .. scheme)
    end

    if string.len(host) < 1 then
        return retcode(595, "Can't route host")
    end

    if port == nil then
        port = 80
    elseif string.match(port, '^%d+$') ~= nil then
        port = tonumber(port)
    else
        return retcode(599, "Wrong port number: " .. port)
    end

    local s = socket.tcp_connect(host, port)
    if s == nil then
        return retcode(595, errno.strerror())
    end

    if body == nil then
        body = ''
    end

    if method == 'GET' then
        hdrs['content-length'] = nil
        body = ''
    elseif string.len(body) > 0 then
        hdrs['content-length'] = string.len(body)
    end

    if hdrs['user-agent'] == nil then
        hdrs['user-agent'] = 'Tarantool http client'
    end

    if port == 80 then
        hdrs['host'] = host
    else
        hdrs['host'] = string.format("%s:%d", host, port)
    end

    hdrs['connection'] = 'close' -- 'keep-alive'
    if hdrs['te'] == nil then
        hdrs['te'] = 'trailers'
    end

    if hdrs.referer == nil then
        hdrs.referer = url
    end

    hdrs.URL = url

    local hdr = ''
    for i, v in pairs(hdrs) do
        hdr = hdr .. string.format("%s: %s\r\n", ucfirst(i), v)
    end

    local pquery = ''

    if query ~= nil and string.len(query) > 0 then
        pquery = '?' .. query
    end

    local req = string.format("%s %s%s HTTP/1.1\r\n%s\r\n%s",
        method, path, pquery, hdr, body)

    if not s:write(req) then
        return retcode(595, errno.strerror())
    end

    local resp = s:read{line = { "\n\n", "\r\n\r\n"} }
    
    if resp == nil then
        return retcode(595, "Can't read response headers")
    end

    resp = lib.parse_response(resp)

    if resp.error ~= nil then
        return retcode(595, resp.error)
    end

    resp.body = ''
    local data
    if resp.headers['content-length'] ~= nil then
        data = s:read(tonumber(resp.headers['content-length']))
    else
        data = s:read({ "\r\n\r\n" })
    end
    if data == nil then
        -- TODO: text of error
        return retcode(595, "Can't read response body")
    end

    resp.body = data

    s:close()
    return resp
end

-- GET
local function get(url, opts)
    return request('GET', url, '', opts)
end

-- POST
local function post(url, body, opts)
    return request('POST', url, body, opts)
end

return {
    request = request;
    get = get;
    post = post;
}
