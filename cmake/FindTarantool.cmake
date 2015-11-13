# Define GNU standard installation directories
include(GNUInstallDirs)

macro(extract_definition name output input)
    string(REGEX MATCH "#define[\t ]+${name}[\t ]+\"([^\"]*)\""
        _t "${input}")
    string(REGEX REPLACE "#define[\t ]+${name}[\t ]+\"(.*)\"" "\\1"
        ${output} "${_t}")
endmacro()

find_path(_dir tarantool/module.h
  HINTS ENV TARANTOOL_DIR
#  PATH_SUFFIXES include
)

if (_dir)
    set(_config "-")
    file(READ "${_dir}/tarantool/module.h" _config0)
    string(REPLACE "\\" "\\\\" _config ${_config0})
    unset(_config0)
    extract_definition(PACKAGE_VERSION TARANTOOL_VERSION ${_config})
    extract_definition(INSTALL_PREFIX TARANTOOL_INSTALL_PREFIX ${_config})
    extract_definition(MODULE_INCLUDEDIR TARANTOOL_INCLUDEDIR ${_config})
    unset(_config)
endif (_dir)
unset (_dir)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(TARANTOOL
    REQUIRED_VARS TARANTOOL_INCLUDEDIR TARANTOOL_INSTALL_PREFIX
    VERSION_VAR TARANTOOL_VERSION)
if (TARANTOOL_FOUND AND NOT TARANTOOL_FIND_QUIETLY AND NOT FIND_TARANTOOL_DETAILS)
    set(FIND_TARANTOOL_DETAILS ON CACHE INTERNAL "Details about TARANTOOL")
    set(TARANTOOL_LIBDIR "${CMAKE_INSTALL_LIBDIR}/tarantool")
    set(TARANTOOL_LUADIR "${CMAKE_INSTALL_DATADIR}/tarantool")
    if (NOT CMAKE_INSTALL_PREFIX STREQUAL "/usr/local" AND
        NOT TARANTOOL_INSTALL_PREFIX STREQUAL CMAKE_INSTALL_PREFIX)
        message(WARNING "Provided CMAKE_INSTALL_PREFIX is different from "
            "CMAKE_INSTALL_PREFIX in module.h. You might need to set "
            "corrent package.path/package.cpath to load this module or "
            "change build prefix:"
            "\n"
            "cmake . -DCMAKE_INSTALL_PREFIX=${TARANTOOL_INSTALL_PREFIX}"
            "\n"
        )
    endif ()
    message(STATUS "Tarantool Module LUADIR is ${TARANTOOL_LUADIR}")
    message(STATUS "Tarantool Module LIBDIR is ${TARANTOOL_LIBDIR}")
endif ()
