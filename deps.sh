#!/bin/sh

# Call this script to install test dependencies.

set -e

# Test dependencies:
# Could be replaced with luatest >= 1.1.0 after a release.
#
# luatest >= 1.4.3 forbids running on Tarantool < 2.2.1, so pin the last
# compatible version (1.4.2) for Tarantool 1.x.
# https://github.com/tarantool/luatest/commit/8fa5687a410c94340891c194266fb8c0a35cc9d0
if tarantool -e 'os.exit(_TARANTOOL:match("^1%.") and 0 or 1)'; then
    tt rocks install luatest 1.4.2
else
    tt rocks install luatest
fi
tt rocks install luacheck 0.25.0
tt rocks install luacov 0.13.0
tt rocks install luafilesystem 1.7.0-2

# cluacov, luacov-coveralls and dependencies
tt rocks install luacov-coveralls 0.2.3-1 --server=https://luarocks.org
tt rocks install cluacov 0.1.2-1 --server=https://luarocks.org

tt rocks make
