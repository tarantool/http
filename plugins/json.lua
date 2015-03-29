local json = require('json')

local function json_decode(self)
    local data = self:read()
    if data == nil then
        return nil
    end

    local s, mp = pcall(json.decode, data)

    if s and data ~= nil then
        return mp
    end
    return nil
end

local function plugin()
    return {
        request = {
            name = 'json',
            ext  = json_decode,
        }
    }
end

return plugin
