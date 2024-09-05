local M = {dependencies = { 'roles.httpd' }}

local servers = {}

M.validate = function() end

M.apply = function(conf)
    for _, server in pairs(conf) do
        servers[server.id] = require('roles.httpd').get_server(server.name)
    end
end

M.stop = function() end

M.get_server_port = function(id)
    return servers[id].port
end

return M
