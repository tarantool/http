local utils = require('http.utils')

local function expires_str(str)
    local now = os.time()
    local gmtnow = now - os.difftime(now, os.time(os.date("!*t", now)))
    local fmt = '%a, %d-%b-%Y %H:%M:%S GMT'

    if str == 'now' or str == 0 or str == '0' then
        return os.date(fmt, gmtnow)
    end

    local diff, period = string.match(str, '^[+]?(%d+)([hdmy])$')
    if period == nil then
        return str
    end

    diff = tonumber(diff)
    if period == 'h' then
        diff = diff * 3600
    elseif period == 'd' then
        diff = diff * 86400
    elseif period == 'm' then
        diff = diff * 86400 * 30
    else
        diff = diff * 86400 * 365
    end

    return os.date(fmt, gmtnow + diff)
end

local function valid_cookie_value_byte(byte)
    -- https://tools.ietf.org/html/rfc6265#section-4.1.1
    -- US-ASCII characters excluding CTLs, whitespace DQUOTE, comma, semicolon, and backslash
    return 32 < byte and byte < 127 and byte ~= string.byte('"') and
            byte ~= string.byte(",") and byte ~= string.byte(";") and byte ~= string.byte("\\")
end

local function valid_cookie_path_byte(byte)
    -- https://tools.ietf.org/html/rfc6265#section-4.1.1
    -- <any CHAR except CTLs or ";">
    return 32 <= byte and byte < 127 and byte ~= string.byte(";")
end

local function escape_string(str, byte_filter)
    local result = {}
    for i = 1, str:len() do
        local char = str:sub(i,i)
        if byte_filter(string.byte(char)) then
            result[i] = char
        else
            result[i] = utils.escape_char(char)
        end
    end
    return table.concat(result)
end

local function escape_value(cookie_value)
    return escape_string(cookie_value, valid_cookie_value_byte)
end

local function escape_path(cookie_path)
    return escape_string(cookie_path, valid_cookie_path_byte)
end

local function setcookie(resp, cookie, options)
    options = options or {}

    local name = cookie.name
    local value = cookie.value

    if name == nil then
        error('cookie.name is undefined')
    end
    if value == nil then
        error('cookie.value is undefined')
    end

    if not options.raw then
        value = escape_value(value)
    end

    local str = utils.sprintf('%s=%s', name, value)

    if cookie.path ~= nil then
        if options.raw then
            str = utils.sprintf('%s;path=%s', str, cookie.path)
        else
            str = utils.sprintf('%s;path=%s', str, escape_path(cookie.path))
        end
    end

    if cookie.domain ~= nil then
        str = utils.sprintf('%s;domain=%s', str, cookie.domain)
    end

    if cookie.expires ~= nil then
        str = utils.sprintf('%s;expires=%s', str, expires_str(cookie.expires))
    end

    if not resp.headers then
        resp.headers = {}
    end
    if resp.headers['set-cookie'] == nil then
        resp.headers['set-cookie'] = { str }
    elseif type(resp.headers['set-cookie']) == 'string' then
        resp.headers['set-cookie'] = {
            resp.headers['set-cookie'],
            str
        }
    else
        table.insert(resp.headers['set-cookie'], str)
    end
    return resp
end

local metatable = {
    __index = {
        setcookie = setcookie;
    }
}
return {metatable = metatable}
