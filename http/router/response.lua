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

local function setcookie(resp, cookie)
    local name = cookie.name
    local value = cookie.value

    if name == nil then
        error('cookie.name is undefined')
    end
    if value == nil then
        error('cookie.value is undefined')
    end

    local str = utils.sprintf('%s=%s', name, utils.uri_escape(value))
    if cookie.path ~= nil then
        str = utils.sprintf('%s;path=%s', str, cookie.path)
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
