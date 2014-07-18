# Build
add_library(httpd SHARED lib.c)
set_target_properties(httpd PROPERTIES PREFIX "" OUTPUT_NAME "lib")

# Install
install(TARGETS httpd LIBRARY DESTINATION ${MODULE_LIBDIR}/http)
install(FILES server.lua DESTINATION ${MODULE_LUADIR}/http)
install(FILES client.lua DESTINATION ${MODULE_LUADIR}/http)
install(FILES mime_types.lua DESTINATION ${MODULE_LUADIR}/http)
install(FILES codes.lua DESTINATION ${MODULE_LUADIR}/http)
