find_program(LUACOV luacov
    HINTS .rocks/
    PATH_SUFFIXES bin
    DOC "Lua test coverage analysis"
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(LuaCov
    REQUIRED_VARS LUACOV
)

mark_as_advanced(LUACOV)
