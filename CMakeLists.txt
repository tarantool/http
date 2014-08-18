project(box.http C)
cmake_minimum_required(VERSION 2.8 FATAL_ERROR)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebugInfo)
endif()
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

# Find Tarantool
set(TARANTOOL_FIND_REQUIRED ON)


option(TARANTOOL_SRC_DIR "Directory with tarantool sources")

if (NOT TARANTOOL_SRC_DIR)
	find_package(Tarantool)
	include_directories(${TARANTOOL_INCLUDEDIR})
else()
	include_directories(${TARANTOOL_SRC_DIR}/src)
	include_directories(${TARANTOOL_SRC_DIR}/third_party)
	include_directories(${TARANTOOL_SRC_DIR}/third_party/luajit/src)
endif()

# Set CFLAGS
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -Wall -Wextra")

add_subdirectory(http)

add_custom_target(test
	WORKING_DIRECTORY .
	COMMAND ./test/http.test.lua)
