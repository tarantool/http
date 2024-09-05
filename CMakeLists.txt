cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

project(http C)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

find_package(LuaTest)
find_package(LuaCheck)
find_package(LuaCov)
find_package(LuaCovCoveralls)

set(CODE_COVERAGE_REPORT "${PROJECT_SOURCE_DIR}/luacov.report.out")
set(CODE_COVERAGE_STATS "${PROJECT_SOURCE_DIR}/luacov.stats.out")

# Find Tarantool and Lua dependecies
set(Tarantool_FIND_REQUIRED ON)
find_package(Tarantool)
include_directories(${TARANTOOL_INCLUDE_DIRS})

# Set CFLAGS
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -Wall -Wextra")

string(RANDOM ALPHABET 0123456789 seed)

add_subdirectory(http)
add_subdirectory(roles)

add_custom_target(luacheck
  COMMAND ${LUACHECK} ${PROJECT_SOURCE_DIR}
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMENT "Run luacheck"
)

add_custom_target(luatest-coverage
  COMMAND ${LUATEST} -v --coverage --shuffle all:${seed}
  BYPRODUCTS ${CODE_COVERAGE_STATS}
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMENT "Run regression tests with coverage"
)

add_custom_target(luatest
  COMMAND ${LUATEST} -v --shuffle all:${seed}
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMENT "Run regression tests without coverage"
)

add_custom_target(coverage
  COMMAND ${LUACOV} ${PROJECT_SOURCE_DIR} && grep -A999 '^Summary' ${CODE_COVERAGE_REPORT}
  DEPENDS ${CODE_COVERAGE_STATS}
  BYPRODUCTS ${CODE_COVERAGE_REPORT}
  WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
  COMMENT "Generate code coverage stats"
)

if(DEFINED ENV{GITHUB_TOKEN})
  set(COVERALLS_COMMAND ${LUACOVCOVERALLS} --include ^http --verbose --repo-token $ENV{GITHUB_TOKEN})
else()
  set(COVERALLS_COMMAND ${CMAKE_COMMAND} -E echo "Skipped uploading to coveralls.io: no token.")
endif()

add_custom_target(coveralls
  # Replace absolute paths with relative ones.
  # In command line: sed -i -e 's@'"$(realpath .)"'/@@'.
  COMMAND sed -i -e "\"s@\"'${PROJECT_SOURCE_DIR}'\"/@@\"" ${CODE_COVERAGE_STATS}
  COMMAND ${COVERALLS_COMMAND}
  DEPENDS ${CODE_COVERAGE_STATS}
  WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
  COMMENT "Send code coverage data to the coveralls.io service"
)

set (LUA_PATH "LUA_PATH=${PROJECT_SOURCE_DIR}/?.lua\\;${PROJECT_SOURCE_DIR}/?/init.lua\\;\\;")
set (LUA_SOURCE_DIR "LUA_SOURCE_DIR=${PROJECT_SOURCE_DIR}")
set_target_properties(luatest-coverage PROPERTIES ENVIRONMENT "${LUA_PATH};${LUA_SOURCE_DIR}")
