cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

project(http C)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

# Find Tarantool and Lua dependecies
set(TARANTOOL_FIND_REQUIRED ON)
find_package(Tarantool)
include_directories(${TARANTOOL_INCLUDE_DIRS})

# Set CFLAGS
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -Wall -Wextra")

add_subdirectory(http)

add_custom_target(check
    WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
    COMMAND env - BINARY_DIR=${PROJECT_BINARY_DIR}
            prove -v ./test/http.test.lua)
