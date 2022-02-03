#!/bin/sh

# Call this script to install test dependencies.

set -e

# Test dependencies:
tarantoolctl rocks install luatest 0.5.7
tarantoolctl rocks install luacheck 0.25.0
tarantoolctl rocks install luacov 0.13.0

# cluacov, luacov-coveralls and dependencies
tarantoolctl rocks install luacov-coveralls 0.2.3-1 --server=https://luarocks.org
tarantoolctl rocks install cluacov 0.1.2-1 --server=https://luarocks.org

tarantoolctl rocks make
