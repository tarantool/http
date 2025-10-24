local M = {dependencies = { 'roles.httpd' }}

local servers = {}
local applied = {}

M.validate = function() end

M.apply = function(conf)
    for _, server in pairs(conf) do
        servers[server.id] = require('roles.httpd').get_server(server.name)

        if servers[server.id] ~= nil then
            servers[server.id]:route({
                path = '/ping',
            }, function(tx)
                return tx:render({text = 'pong'})
            end)

            if applied[server.id] == nil then
                servers[server.id]:route({
                    path = '/ping_once',
                }, function(tx)
                    return tx:render({text = 'pong once'})
                end)
                applied[server.id] = {}
            end
        end
    end
end

M.stop = function() end

M.get_server_port = function(id)
    return servers[id].port
end

return M
