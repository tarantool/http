# Build
if (APPLE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -undefined suppress -flat_namespace")
endif(APPLE)

add_library(httpd SHARED lib.c)
set_target_properties(httpd
        PROPERTIES
            PREFIX ""
            SUFFIX ".so"
            OUTPUT_NAME "lib")

# Install
install(TARGETS httpd LIBRARY DESTINATION ${TARANTOOL_INSTALL_LIBDIR}/http)
install(FILES server/init.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/server/init.lua)
install(FILES server/tsgi_adapter.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/server/tsgi_adapter.lua)
install(FILES nginx_server/init.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/nginx_server/init.lua)
install(FILES router/init.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/router/init.lua)
install(FILES router/fs.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/router/fs.lua)
install(FILES router/matching.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/router/matching.lua)
install(FILES router/middleware.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/router/middleware.lua)
install(FILES router/request.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/router/request.lua)
install(FILES router/response.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/router/response.lua)
install(FILES tsgi.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/tsgi.lua)
install(FILES utils.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/utils.lua)
install(FILES mime_types.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/mime_types.lua)
install(FILES codes.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http/codes.lu)
