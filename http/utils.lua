local codes = require('http.codes')

local function errorf(fmt, ...)
    error(string.format(fmt, ...))
end

local function sprintf(fmt, ...)
    return string.format(fmt, ...)
end

local function ucfirst(str)
    return str:gsub("^%l", string.upper, 1)
end

local function reason_by_code(code)
    code = tonumber(code)
    if codes[code] ~= nil then
        return codes[code]
    end
    return sprintf('Unknown code %d', code)
end

local function extend(tbl, tblu, raise)
    local res = {}
    for k, v in pairs(tbl) do
        res[ k ] = v
    end
    for k, v in pairs(tblu) do
        if raise then
            if res[ k ] == nil then
                errorf("Unknown option '%s'", k)
            end
        end
        res[ k ] = v
    end
    return res
end

local function uri_unescape(str, unescape_plus_sign)
    local res = {}
    if type(str) == 'table' then
        for _, v in pairs(str) do
            table.insert(res, uri_unescape(v))
        end
    else
        if unescape_plus_sign ~= nil then
            str = string.gsub(str, '+', ' ')
        end

        res = string.gsub(str, '%%([0-9a-fA-F][0-9a-fA-F])',
                          function(c)
                              return string.char(tonumber(c, 16))
                          end
        )
    end
    return res
end

local function uri_escape(str)
    local res = {}
    if type(str) == 'table' then
        for _, v in pairs(str) do
            table.insert(res, uri_escape(v))
        end
    else
        res = string.gsub(str, '[^a-zA-Z0-9_]',
                          function(c)
                              return string.format('%%%02X', string.byte(c))
                          end
        )
    end
    return res
end

return {
    errorf = errorf,
    sprintf = sprintf,
    ucfirst = ucfirst,
    reason_by_code = reason_by_code,
    extend = extend,
    uri_unescape = uri_unescape,
    uri_escape = uri_escape,
}
