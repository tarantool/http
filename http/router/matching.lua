local utils = require('http.utils')

local function transform_filter(filter)
    local path = filter.path  -- luacheck: ignore
    -- route must have '/' at the begin and end
    if string.match(path, '.$') ~= '/' then
        path = path .. '/'
    end
    if string.match(path, '^.') ~= '/' then
        path = '/' .. path
    end

    return {
        path = path,
        method = string.upper(filter.method)
    }
end

-- converts user-defined path pattern to a matcher string.
-- used on adding new route.
local function transform_pattern(path)
    local match = path
    match = string.gsub(match, '[-]', "[-]")

    -- convert user-specified route URL to regexp,
    -- and initialize stashes

    local estash = {  }  -- helper table, name -> boolean
    local stash = {  }   -- i -> word

    -- when no such pattern is found, returns false
    local find_and_replace_stash_pattern = function(pattern_regex, replace_with)
        local name = string.match(match, pattern_regex)
        if name == nil then
            return false
        end
        if estash[name] then
            utils.errorf("duplicate stash: %s", name)
        end
        estash[name] = true
        match = string.gsub(match, pattern_regex, replace_with, 1)

        table.insert(stash, name)
        return true
    end

    -- patterns starting with :
    while find_and_replace_stash_pattern(':([%a_][%w_]*)', '([^/]-)') do end
    -- extended patterns starting with *
    while find_and_replace_stash_pattern('[*]([%a_][%w_]*)', '(.-)') do end

    -- ensure match is like '^/xxx/$'
    do
        if string.match(match, '.$') ~= '/' then
            match = match .. '/'
        end
        if string.match(match, '^.') ~= '/' then
            match = '/' .. match
        end
        match = '^' .. match .. '$'
    end

    return match, stash
end

local function matches(r, filter)
    local methods_match = r.method == filter.method or r.method == 'ANY'
    if not methods_match then
        return false
    end

    local regex_groups_matched = {string.match(filter.path, r.match)}
    if #regex_groups_matched == 0 then
        return false
    end
    if #r.stash > 0 and #r.stash ~= #regex_groups_matched then
        return false
    end

    return true, {
        route = r,
        stash = regex_groups_matched,
    }
end

local function better_than(newmatch, oldmatch)
    if newmatch == nil then
        return false
    end
    if oldmatch == nil then
        return true
    end

    -- current match (route) is prioritized iff:
    -- 1. it has less matched words, or
    -- 2. if current match (route) has more specific method filter
    if #oldmatch.stash > #newmatch.stash then
        return true
    end
    return newmatch.route.method ~= oldmatch.route.method and
        oldmatch.method == 'ANY'
end

return {
    matches = matches,
    better_than = better_than,
    transform_filter = transform_filter,
    transform_pattern = transform_pattern,
}
