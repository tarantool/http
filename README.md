Tarantool HTTP
==============

HTTP client and server for [Tarantool][].

## Status

This module is in early alpha stage.
Tarantool 1.6.3-1+ required.

[![Build Status](https://travis-ci.org/tarantool/http.png?branch=master)](https://travis-ci.org/tarantool/http)

## Getting Started

### Installation

    cmake . -DCMAKE_INSTALL_PREFIX=/usr # Tarantool prefix
    make
    make install
    make test

Please check that you have `include/tarantool/config.h` installed.

### Usage

    tarantool> client = require('http.client')
    tarantool> print(client.get("http://mail.ru/").status)

See more examples in the [documentation][Documentation] and [tests][Tests].

## See Also

 * [Tarantool][]
 * [Documentation][]
 * [Tests][]

[Tarantool]: http://github.com/tarantool/tarantool
[Documentation]: https://github.com/tarantool/http/wiki
[Tests]: https://github.com/tarantool/http/tree/master/test
