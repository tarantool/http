-- http.client

local lib = require('box.http.lib') -- native library
local socket_lib = require('box.socket')

local function errorf(fmt, ...)
    error(string.format(fmt, ...))
end

local function retcode(code, reason)
    return {
        status  = code,
        reason  = reason
    }
end

local function connect(host, port)
    local s = socket_lib.tcp()
    if s == nil then
        return nil, "Can't create socket"
    end
    local res = { s:connect(host, port) }
    if res[1] == nil then
        return nil, res[4]
    end
    return s
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

    local s, err = connect(host, port)
    if s == nil then
        return retcode(595, err)
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
        hdrs['user-agent'] = 'Tarantool box.http agent'
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

    if string.len(query) > 0 then
        pquery = '?' .. query
    end

    local req = string.format("%s %s%s HTTP/1.1\r\n%s\r\n%s",
        method, path, pquery, hdr, body)

    local res = { s:send(req) }

    if #res > 1 then
        return retcode(595, res[4])
    end
    if res[1] ~= string.len(req) then
        return retcode(595, "Can't send request")
    end

    res = { s:readline({ "\n\n", "\r\n\r\n" }) }

    if res[2] ~= nil and res[2] ~= 'eof' then
        -- TODO: text of error
        return retcode(595, "Can't read response headers")
    end

    local resp = lib.parse_response(res[1])

    if resp.error ~= nil then
        return retcode(595, resp.error)
    end

    resp.body = ''
    if resp.headers['content-length'] ~= nil then
        res = { s:recv(tonumber(resp.headers['content-length'])) }
        if #res > 1 then
            -- TODO: text of error
            return retcode(595, "Can't read response body")
        end
    end

    resp.body = res[1]

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
