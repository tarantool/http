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

local function plugin()
    return {
        request = {
            name = 'json',
            ext  = json_decode,
        }
    }
end

return plugin
