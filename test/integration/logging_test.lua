local t = require('luatest')
local capture = require('luatest.capture'):new()
local json = require('json')
local http_server = require('http.server')
local http_router = require('http.router')
local http_client = require('http.client')
local g = t.group()

local helper = require('test.helper')

g.before_all(function()
    g.default_log_level = box.cfg.log_level
    box.cfg{ log_level = 7 }
end)

g.after_all(function()
    box.cfg{ log_level = g.default_log_level }
end)

local log_queue = {}

local custom_logger = {
    debug = function() end,
    info = function(...)
        table.insert(log_queue, { log_lvl = 'info', msg = string.format(...)})
    end,
    error = function(...)
        table.insert(log_queue, { log_lvl = 'error', msg = string.format(...)})
    end
}

local function find_msg_in_log_queue(msg)
    for _, log in ipairs(log_queue) do
        if log.msg:match(msg) then
            return log
        end
    end
end

local function clear_log_queue()
    log_queue = {}
end

g.before_each(function()
    g.server = http_server.new(helper.base_host, helper.base_port)
    g.router = http_router.new()
    g.server:set_router(g.router)
    g.server:start()
end)

g.after_each(function()
    clear_log_queue()
    g.server:stop()
end)

g.test_default_server_logger = function()
    local test_cases = {
        {
            log_options = nil,
            log_prefixes = {
                log_requests = 'I>',
                log_errors = 'E>'
            }
        },
        {
            log_options = {
                log_requests = true,
                log_errors = true,
            },
            log_prefixes = {
                log_requests = 'I>',
                log_errors = 'E>'
            }
        },
        {
            log_options = {
                log_requests = false,
                log_errors = false,
            },
            log_prefixes = {
                log_requests = 'D>',
                log_errors = 'D>'
            }
        }
    }

    g.router:route({path = 'log', method = 'GET'}, function() error('test') end)
    for _, test_case in pairs(test_cases) do
        if test_case.log_options ~= nil then
            g.server.options.log_requests = test_case.log_options.log_requests
            g.server.options.log_errors = test_case.log_options.log_errors
        end

        -- capture logs
        capture:wrap(true, function()
            http_client.get(helper.base_uri .. 'log')
        end)
        local logs = capture:flush().stderr

        t.assert_str_contains(
            logs, test_case.log_prefixes.log_requests .. ' GET /log\n', false, json.encode(test_case)
        )
        t.assert_str_contains(
            logs, test_case.log_prefixes.log_errors .. ' unhandled error:(.-) test\n',
            true, json.encode(test_case)
        )
    end
end

g.test_server_custom_logger_output = function()
    g.server.options.log_requests = custom_logger.info
    g.server.options.log_errors = custom_logger.error
    g.router:route({ path='/' }, function() error('Some error...') end)

    http_client.get(helper.base_uri)

    t.assert_items_include(
        log_queue, {{ log_lvl = 'info', msg = 'GET /' }},
        "Route should logging requests in custom logger if it's presents"
    )

    t.assert_is_not(
        find_msg_in_log_queue("Some error..."), nil,
        "Route should logging error in custom logger if it's presents"
    )
end

g.test_route_log_options = function()
    local dummy_logger = function() end

    local test_cases = {
        {
            args = { path = '/', log_requests = 3 },
            err = "'log_requests' option should be a function",
        },
        {
            args = { path = '/', log_requests = { info = dummy_logger } },
            err = "'log_requests' option should be a function or a boolean",
        },
        {
            args = { path = '/', log_errors = 3 },
            err = "'log_errors' option should be a function or a boolean"
        },
        {
            args = { path = '/', log_errors = { error = dummy_logger } },
            err = "'log_errors' option should be a function or a boolean"
        }
    }

    for _, test_case in pairs(test_cases) do
        local ok, err = pcall(g.router.route, g.router, test_case.args)
        t.assert_is(ok, false)
        t.assert_str_contains(
            err,
            test_case.err
        )
    end
end

g.test_route_custom_logger_output = function()
    local servers_options = {
        {
            log_requests = true,
            log_errors = true
        },
        {
            log_requests = false,
            log_errors = false
        },
    }
    g.router:route(
        { path = '/', log_requests = custom_logger.info, log_errors = custom_logger.error },
        function() error("User business logic exception...") end
    )

    for _, opts in ipairs(servers_options) do
        http_client.get(helper.base_uri)
        g.server.options.log_requests = opts.log_requests
        g.server.options.log_errors = opts.log_errors
        t.assert_items_include(log_queue, {{ log_lvl = 'info', msg = 'GET /' }},
            "Route should logging requests in custom logger if it's presents"
        )
        t.assert_is_not(
            find_msg_in_log_queue("User business logic exception..."), nil,
            "Route should logging error custom logger if it's presents in case of route exception"
        )
        clear_log_queue()
    end
end

g.test_route_logger_override_default_logger = function()
    local test_cases = {
        {
            servers_options = {
                log_requests = true,
                log_errors = true,
            },
            route_options = {
                log_requests = false,
                log_errors = false,
            },
            log_prefixes = {
                log_requests = 'D>',
                log_errors = 'D>'
            }
        },
        {
            servers_options = {
                log_requests = false,
                log_errors = false,
            },
            route_options = {
                log_requests = true,
                log_errors = true,
            },
            log_prefixes = {
                log_requests = 'I>',
                log_errors = 'E>'
            }
        }
    }

    for _, test_case in ipairs(test_cases) do
        g.router.routes = {}
        g.router:route(
            {
                path = '/', method = 'GET',
                log_requests = test_case.route_options.log_requests,
                log_errors = test_case.route_options.log_errors
            }, function() error('test') end
        )

        g.server.options.log_requests = test_case.servers_options.log_requests
        g.server.options.log_errors = test_case.servers_options.log_errors

        -- capture logs
        capture:wrap(true, function()
            http_client.get(helper.base_uri)
        end)
        local logs = capture:flush().stderr

        t.assert_str_contains(logs, test_case.log_prefixes.log_requests .. ' GET /\n', false, json.encode(test_case))
        t.assert_str_contains(
            logs, test_case.log_prefixes.log_errors .. ' unhandled error:(.-) test\n', true, json.encode(test_case)
        )
    end
end

g.test_route_logger_override_custom_logger = function()
    local server_logger = {
        debug = function() end,
        info = function(...)
            table.insert(log_queue, { log_lvl = 'server-info', msg = string.format(...)})
        end,
        error = function(...)
            table.insert(log_queue, { log_lvl = 'server-error', msg = string.format(...)})
        end
    }
    g.server.options.log_requests = server_logger.info
    g.server.options.log_errors = server_logger.error

    g.router:route(
        {
            path = '/', method = 'GET',
            log_requests = custom_logger.info,
            log_errors = custom_logger.error
        }, function() error('test') end
    )

    http_client.get(helper.base_uri)

    t.assert_items_include(log_queue, {{ log_lvl = 'info', msg = 'GET /' }},
        "Route should logging requests in custom logger if it's presents"
    )
    t.assert_is_not(
        find_msg_in_log_queue("test"), nil,
        "Route should logging error custom logger if it's presents in case of route exception"
    )
end
