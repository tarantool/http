local curl = require('http.client')
local uuid = require('uuid')
local json = require('json')

local function retcode(code, reason)
    return {
        error = {
            code    = code,
            message = reason
        }
    }
end

local function wrap(encoder, method, data)
    if method == 'nil' or type(method) ~= 'string' then
        return nil
    end

    local req = {
        id = uuid.str(),

        method  = method,
        jsonrpc = "2.0",
    }

    if data then
        req.params = data
    end

    local s, o = pcall(encoder.encode, req)

    if s and o ~= nil then
        return o
    end

    return nil
end

local function make_request(self, method, data, opts)
    if not self.ctx.url then
        return retcode(599, "Invalid url")
    end
    local format = self.ctx.format

    data = wrap(format, method, data)

    if not data then
        return retcode(595, "Can't encode data to JSON")
    end

    local resp = curl.request('POST', self.ctx.url, data, opts)

    if not resp or resp.status ~= 200 then
        return retcode(resp.status, resp.reason)
    end

    local s, o = pcall(format.decode, resp.body)

    if s and o ~= nil then
        if o.error then
            return {
                error = o.error
            }
        end

        if o.result then
            return {
                result = o.result
            }
        end
        retcode(596, "Not found jsonrpc result/error")
    end

    return retcode(595, "Can't json decode")
end

local function make_method(self, name)
    if name == nil or type(name) ~= 'string' then
        return self
    elseif name == 'cxt' then
        return self
    elseif name == 'method' then
        return self
    end

    self[name] = (function (data, opts)
        return make_request(self, name, data, opts)
    end)

    return self
end

local exports = {
    new = function (name, url, opts)
        local format = nil
        if opts and opts.format then 
            format = opts.format
        else
            format = json
        end

        local self = {
            ctx = {
                url    = url,
                name   = name,
                format = format, -- We can cahnge json to msgpack here
            },
            method = make_method,
        }
        return self
    end,
}

return exports
