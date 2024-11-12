local checks = require('checks')
local urilib = require('uri')
local http_server = require('http.server')

local M = {
    DEFAULT_SERVER_NAME = 'default',
}
local servers = {}

local function parse_listen(listen)
    if listen == nil then
        return nil, nil, "must exist"
    end
    if type(listen) ~= "string" and type(listen) ~= "number" then
        return nil, nil, "must be a string or a number, got " .. type(listen)
    end

    local host
    local port
    if type(listen) == "string" then
        local uri, err = urilib.parse(listen)
        if err ~= nil then
            return nil, nil, "failed to parse URI: " .. err
        end

        if uri.scheme ~= nil then
            if uri.scheme == "unix" then
                uri.unix = uri.path
            else
                return nil, nil, "URI scheme is not supported"
            end
        end

        if uri.login ~= nil or uri.password then
            return nil, nil, "URI login and password are not supported"
        end

        if uri.query ~= nil then
            return nil, nil, "URI query component is not supported"
        end

        if uri.unix ~= nil then
            host = "unix/"
            port = uri.unix
        else
            if uri.service == nil then
                return nil, nil, "URI must contain a port"
            end

            port = tonumber(uri.service)
            if port == nil then
                return nil, nil, "URI port must be a number"
            end
            if uri.host ~= nil then
                host = uri.host
            elseif uri.ipv4 ~= nil then
                host = uri.ipv4
            elseif uri.ipv6 ~= nil then
                host = uri.ipv6
            else
                host = "0.0.0.0"
            end
        end
    elseif type(listen) == "number" then
        host = "0.0.0.0"
        port = listen
    end

    if type(port) == "number" and (port < 1 or port > 65535) then
        return nil, nil, "port must be in the range [1, 65535]"
    end
    return host, port, nil
end

-- parse_params returns table with set options from config to pass
-- it into new() function.
local function parse_params(node)
    return {
        ssl_cert_file = node.ssl_cert_file,
        ssl_key_file = node.ssl_key_file,
        ssl_password = node.ssl_password,
        ssl_password_file = node.ssl_password_file,
        ssl_ca_file = node.ssl_ca_file,
        ssl_ciphers = node.ssl_ciphers,
    }
end

local function apply_http(name, node)
    local host, port, err = parse_listen(node.listen)
    if err ~= nil then
        error("failed to parse URI: " .. err)
    end

    if servers[name] == nil then
        local httpd = http_server.new(host, port, parse_params(node))

        httpd:start()
        servers[name] = {
            httpd = httpd,
            routes = {},
        }
    end
end

M.validate = function(conf)
    if conf ~= nil and type(conf) ~= "table" then
        error("configuration must be a table, got " .. type(conf))
    end
    conf = conf or {}

    for name, node in pairs(conf) do
        if type(name) ~= 'string' then
            error("name of the server must be a string")
        end

        local host, port, err = parse_listen(node.listen)
        if err ~= nil then
            error("failed to parse http 'listen' param: " .. err)
        end

        local ok, err = pcall(http_server.new, host, port, parse_params(node))
        if not ok then
            error("failed to parse params in " .. name .. " server: " .. tostring(err))
        end
    end
end

M.apply = function(conf)
    -- This should be called on the role's lifecycle, but it's better to give
    -- a meaningful error if something goes wrong.
    M.validate(conf)

    for name, node in pairs(conf or {}) do
        apply_http(name, node)
    end
end

M.stop = function()
    for _, server in pairs(servers) do
        server.httpd:stop()
    end
    servers = {}
end

M.get_server = function(name)
    checks('?string')

    name = name or M.DEFAULT_SERVER_NAME
    return (servers[name] or {}).httpd
end

return M
