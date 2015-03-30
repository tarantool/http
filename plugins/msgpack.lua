local msgpack = require('msgpack')

local function mp_encode(self, opts)
    local data = opts['msgpack']
    return {
        headers = {
            ['content-type'] = 'application/x-msgpack'
        },
        body = msgpack.encode(data),
    }
end

local function mp_decode(self)
    local data = self:read()
    if data == nil then
        return nil
    end

    local s, mp = pcall(msgpack.decode, data)

    if s and mp ~= nil then
        return mp
    end
    return nil
end

local function plugin()
    return {
        render  = {
            name = 'msgpack',
            ext  = mp_encode,
        },
        request = {
            name = 'msgpack',
            ext  = mp_decode,
        }
    }
end

return plugin
