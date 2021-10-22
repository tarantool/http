#!/bin/sh

# Call this script to install test dependencies.

set -e

# Test dependencies:
tarantoolctl rocks install luatest 0.5.5

tarantoolctl rocks make
