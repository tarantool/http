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
install(FILES server.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http)
install(FILES client.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http)
install(FILES mime_types.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http)
install(FILES codes.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/http)
