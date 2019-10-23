local lib = require('http.lib')
local utils = require('http.utils')
local mime_types = require('http.mime_types')
local response = require('http.router.response')

local json = require('json')

local function type_by_format(fmt)
    if fmt == nil then
        return 'application/octet-stream'
    end

    local t = mime_types[ fmt ]

    if t ~= nil then
        return t
    end

    return 'application/octet-stream'
end

local function catfile(...)
    local sp = { ... }

    local path

    if #sp == 0 then
        return
    end

    for _, pe in pairs(sp) do
        if path == nil then
            path = pe
        elseif string.match(path, '.$') ~= '/' then
            if string.match(pe, '^.') ~= '/' then
                path = path .. '/' .. pe
            else
                path = path .. pe
            end
        else
            if string.match(pe, '^.') == '/' then
                path = path .. string.gsub(pe, '^/', '', 1)
            else
                path = path .. pe
            end
        end
    end

    return path
end

local function static_file(self, request, format)
    local file = catfile(self.options.app_dir, 'public', request:path())

    if self.options.cache_static and self.cache.static[ file ] ~= nil then
        return {
            code = 200,
            headers = {
                [ 'content-type'] = type_by_format(format),
            },
            body = self.cache.static[ file ]
        }
    end

    local s, fh = pcall(io.input, file)

    if not s then
        return { status = 404 }
    end

    local body = fh:read('*a')
    io.close(fh)

    if self.options.cache_static then
        self.cache.static[ file ] = body
    end

    return {
        status = 200,
        headers = {
            [ 'content-type'] = type_by_format(format),
        },
        body = body
    }
end


local function ctx_action(tx)
    local ctx = tx.endpoint.controller
    local action = tx.endpoint.action
    if tx:router().options.cache_controllers then
        if tx:router().cache[ ctx ] ~= nil then
            if type(tx:router().cache[ ctx ][ action ]) ~= 'function' then
                utils.errorf("Controller '%s' doesn't contain function '%s'",
                    ctx, action)
            end
            return tx:router().cache[ ctx ][ action ](tx)
        end
    end

    local ppath = package.path
    package.path = catfile(tx:router().options.app_dir, 'controllers', '?.lua')
                .. ';'
                .. catfile(tx:router().options.app_dir,
                    'controllers', '?/init.lua')
    if ppath ~= nil then
        package.path = package.path .. ';' .. ppath
    end

    local st, mod = pcall(require, ctx)
    package.path = ppath
    package.loaded[ ctx ] = nil

    if not st then
        utils.errorf("Can't load module '%s': %s'", ctx, tostring(mod))
    end

    if type(mod) ~= 'table' then
        utils.errorf("require '%s' didn't return table", ctx)
    end

    if type(mod[ action ]) ~= 'function' then
        utils.errorf("Controller '%s' doesn't contain function '%s'", ctx, action)
    end

    if tx:router().options.cache_controllers then
        tx:router().cache[ ctx ] = mod
    end

    return mod[action](tx)
end

local function load_template(self, r, format)
    if r.template ~= nil then
        return
    end

    if format == nil then
        format = 'html'
    end

    local file
    if r.file ~= nil then
        file = r.file
    elseif r.controller ~= nil and r.action ~= nil then
        file = catfile(
            string.gsub(r.controller, '[.]', '/'),
            r.action .. '.' .. format .. '.el')
    else
        utils.errorf("Can not find template for '%s'", r.path)
    end

    if self.options.cache_templates then
        if self.cache.tpl[ file ] ~= nil then
            return self.cache.tpl[ file ]
        end
    end


    local tpl = catfile(self.options.app_dir, 'templates', file)
    local fh = io.input(tpl)
    local template = fh:read('*a')
    fh:close()

    if self.options.cache_templates then
        self.cache.tpl[ file ] = template
    end
    return template
end


local function render(tx, opts)
    if tx == nil then
        error("Usage: self:render({ ... })")
    end

    local resp = setmetatable({ headers = {} }, response.metatable)
    local vars = {}
    if opts ~= nil then
        if opts.text ~= nil then
            if tx:router().options.charset ~= nil then
                resp.headers['content-type'] =
                    utils.sprintf("text/plain; charset=%s",
                        tx:router().options.charset
                    )
            else
                resp.headers['content-type'] = 'text/plain'
            end
            resp.body = tostring(opts.text)
            return resp
        end

        -- TODO
        if opts.json ~= nil then
            if tx:router().options.charset ~= nil then
                resp.headers['content-type'] =
                    utils.sprintf('application/json; charset=%s',
                        tx:router().options.charset
                    )
            else
                resp.headers['content-type'] = 'application/json'
            end
            resp.body = json.encode(opts.json)
            return resp
        end

        if opts.data ~= nil then
            resp.body = tostring(opts.data)
            return resp
        end

        vars = utils.extend(tx.tstash, opts, false)
    end

    local tpl

    local format = tx.tstash.format
    if format == nil then
        format = 'html'
    end

    if tx.endpoint.template ~= nil then
        tpl = tx.endpoint.template
    else
        tpl = load_template(tx:router(), tx.endpoint, format)
        if tpl == nil then
            utils.errorf('template is not defined for the route')
        end
    end

    if type(tpl) == 'function' then
        tpl = tpl()
    end

    for hname, sub in pairs(tx:router().helpers) do
        vars[hname] = function(...) return sub(tx, ...) end
    end
    vars.action = tx.endpoint.action
    vars.controller = tx.endpoint.controller
    vars.format = format

    resp.body = lib.template(tpl, vars)
    resp.headers['content-type'] = type_by_format(format)

    if tx:router().options.charset ~= nil then
        if format == 'html' or format == 'js' or format == 'json' then
            resp.headers['content-type'] = resp.headers['content-type']
                .. '; charset=' .. tx:router().options.charset
        end
    end
    return resp
end

return {
    render = render,
    ctx_action = ctx_action,
    static_file = static_file,
}
