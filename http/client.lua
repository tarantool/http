-- http.client

local lib = require('http.lib') -- native library
local socket = require('socket')
local errno = require('errno')
local log = require('log')
local urilib = require('uri')

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

local function request(method, urlstr, body, opts)
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

    local ua = opts.ua
    if opts.ua == nil then
        ua = 'Tarantool http client'
    end

    method = string.upper(method)

    local url = urilib.parse(urlstr)
    if not url then
        return retcode(599, "Invalid url: " .. urlstr)
    end

    if url.scheme and url.scheme ~= 'http' then
        return retcode(599, "Unknown scheme: " .. url.scheme)
    end

    if string.len(url.host) < 1 then
        return retcode(595, "Can't route host")
    end

    if url.service == nil then
        url.service = 80
    end

    local s = socket.tcp_connect(url.host, url.service)
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
        hdrs['user-agent'] = ua
    end

    if url.host == 'unix/' then
        hdrs['host'] = 'localhost'
    elseif url.service == 80 or url.service == 'http' then
        hdrs['host'] = url.host
    else
        hdrs['host'] = string.format("%s:%d", url.host, s:peer().port)
    end

    hdrs['connection'] = 'close' -- 'keep-alive'
    if hdrs['te'] == nil then
        hdrs['te'] = 'trailers'
    end

    if hdrs.referer == nil then
        hdrs.referer = urlstr
    end

    local hdr = ''
    for i, v in pairs(hdrs) do
        hdr = hdr .. string.format("%s: %s\r\n", ucfirst(i), v)
    end

    local pquery = ''

    if url.query ~= nil and string.len(url.query) > 0 then
        pquery = '?' .. url.query
    end

    local req = string.format("%s %s%s HTTP/1.1\r\n%s\r\n%s",
        method, url.path or "/", pquery, hdr, body)

    if not s:write(req) then
        return retcode(595, errno.strerror())
    end

    local resp = s:read{line = { "\r\n\r\n"} }
    if resp == nil then
        return retcode(595, "Can't read response headers")
    end

    resp = lib.parse_response(resp)

    if resp.error ~= nil then
        return retcode(595, resp.error)
    end

    if resp.headers['transfer-encoding'] == 'chunked' then
        local body = {}
        while true do
            local data = s:read("\r\n")
            if not data then
                break
            end
            local len = tonumber(data, 16)
            if not len then
                break
            end
            if len == 0 then
                -- no more chunks
                if s:read(2) ~= "\r\n" then
                    break
                end
                resp.body = table.concat(body)
                break
            end
            local chunk = s:read(len)
            if not chunk or s:read(2) ~= "\r\n" then
                break
            end
            table.insert(body, chunk)
        end
    elseif resp.headers['content-length'] ~= nil then
        local len = tonumber(resp.headers['content-length'])
        if len then
            resp.body = s:read(len)
        end
    elseif resp.status == 204 then
        -- 204: No Content
        resp.body = ''
    end

    s:close()
    if resp.body == nil then
        -- TODO: text of error
        return retcode(595, "Can't read response body")
    end

    return resp
end

-- GET
local function get(url, opts)
    return request('GET', url, body, opts)
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
