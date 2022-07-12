#!/usr/bin/env bash

set -e -o pipefail

curl -LsSf https://www.tarantool.io/release/1.10/installer.sh | sudo bash
