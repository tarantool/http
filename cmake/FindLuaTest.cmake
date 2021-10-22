find_program(LUATEST luatest
    HINTS .rocks/
    PATH_SUFFIXES bin
    DOC "Lua testing framework"
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(LuaTest
    REQUIRED_VARS LUATEST
)

mark_as_advanced(LUATEST)
