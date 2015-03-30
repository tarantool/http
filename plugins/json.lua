local json = require('json')

local function json_decode(self)
    local data = self:read()
    if data == nil then
        return nil
    end

    local s, j = pcall(json.decode, data)

    if s and j ~= nil then
        return j
    end
    return nil
end

local function json_encode(self, opts)
    local data = opts['json']
    local resp = {
        headers = {},
        body    = nil,
    }
    if self.httpd.options.charset ~= false then
        resp.headers['content-type'] =
            string.format('application/json; charset=%s',
                self.httpd.options.charset
            )
    else
        resp.headers['content-type'] = 'application/json'
    end
    resp.body = json.encode(opts.json)
    return resp
end

local function plugin()
    return {
        render = {
            name = 'json',
            ext  = json_encode,
        },
        request = {
            name = 'json',
            ext  = json_decode,
        }
    }
end

return plugin
