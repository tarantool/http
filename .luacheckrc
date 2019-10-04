redefined = false
include_files = {"**/*.lua", "*.rockspec", "*.luacheckrc"}
exclude_files = {"lua_modules", ".luarocks", ".rocks", "luatest/luaunit.lua", "build"}
new_read_globals = {
    'box',
    '_TARANTOOL',
    'tonumber64',
    os = {
        fields = {
            'environ',
        }
    },
    string = {
        fields = {
            'split',
            'startswith',
        },
    },
    table = {
        fields = {
            'maxn',
            'copy',
            'new',
            'clear',
            'move',
            'foreach',
            'sort',
            'remove',
            'foreachi',
            'deepcopy',
            'getn',
            'concat',
            'insert',
        },
    },
}
