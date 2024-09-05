#!/bin/sh

# Call this script to install test dependencies.

set -e

# Test dependencies:
# Could be replaced with luatest >= 1.1.0 after a release.
tt rocks install luatest
tt rocks install luacheck 0.25.0
tt rocks install luacov 0.13.0
tt rocks install luafilesystem 1.7.0-2

# cluacov, luacov-coveralls and dependencies
tt rocks install luacov-coveralls 0.2.3-1 --server=https://luarocks.org
tt rocks install cluacov 0.1.2-1 --server=https://luarocks.org

tt rocks make
