find_program(LUACOVCOVERALLS luacov-coveralls
    HINTS .rocks/
    PATH_SUFFIXES bin
    DOC "LuaCov reporter for coveralls.io service"
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(LuaCovCoveralls
    REQUIRED_VARS LUACOVCOVERALLS
)

mark_as_advanced(LUACOVCOVERALLS)
