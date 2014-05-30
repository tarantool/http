project(box.http C)
cmake_minimum_required(VERSION 2.8 FATAL_ERROR)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebugInfo)
endif()
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

# Find Tarantool
set(TARANTOOL_FIND_REQUIRED ON)
find_package(Tarantool)
include_directories(${TARANTOOL_INCLUDEDIR})

# Set CFLAGS
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -Wall -Wextra")

# Build
add_library(httpd SHARED src/lib.c)
set_target_properties(httpd PROPERTIES PREFIX "" OUTPUT_NAME "lib")

# Install
install(TARGETS httpd LIBRARY DESTINATION ${MODULE_LIBDIR}/http)
install(FILES src/server.lua DESTINATION ${MODULE_LUADIR}/http)
install(FILES src/client.lua DESTINATION ${MODULE_LUADIR}/http)
install(FILES src/mime_types.lua DESTINATION ${MODULE_LUADIR}/http)
install(FILES src/codes.lua DESTINATION ${MODULE_LUADIR}/http)
