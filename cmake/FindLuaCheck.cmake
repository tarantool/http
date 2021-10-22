find_program(LUACHECK luacheck
    HINTS .rocks/
    PATH_SUFFIXES bin
    DOC "Lua static analyzer"
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(LuaCheck
    REQUIRED_VARS LUACHECK
)

mark_as_advanced(LUACHECK)
