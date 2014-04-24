if(TARANTOOL_FOUND)
    return()
endif()

# Find and parse config.h
find_path(_dir NAMES tarantool/config.h)
set(_config "-")
if (_dir)
    file(READ "${_dir}/tarantool/config.h" _config)
endif()
macro(extract_definition name output input)
    string(REGEX MATCH "#define[\t ]+${name}[\t ]+\"([^\"]*)\""
        _t "${input}")
    string(REGEX REPLACE "#define[\t ]+${name}[\t ]+\"([^\"]*)\"" "\\1"
        ${output} "${_t}")
endmacro()
extract_definition(PACKAGE_VERSION TARANTOOL_VERSION ${_config})
extract_definition(MODULE_LUADIR TARANTOOL_LUADIR ${_config})
extract_definition(MODULE_LIBDIR TARANTOOL_LIBDIR ${_config})
extract_definition(MODULE_INCLUDEDIR TARANTOOL_INCLUDEDIR ${_config})
unset(_config)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(TARANTOOL
    REQUIRED_VARS TARANTOOL_INCLUDEDIR TARANTOOL_LUADIR TARANTOOL_LIBDIR
    VERSION_VAR TARANTOOL_VERSION)
