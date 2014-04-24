Tarantool HTTP
==============

HTTP client and server for [Tarantool][].

## Status

This module is in early alpha stage.
Tarantool 1.5.3-99+ or 1.6.2-24+ required.

## Getting Started

### Installation

    cmake . -DCMAKE_INSTALL_PREFIX=/usr # Tarantool prefix
    make
    make install

Please check that you have `include/tarantool/config.h` installed.

### Usage

    tarantool> client = require('box.http.client')
    tarantool> print(client.get("http://mail.ru/").status)

See more examples in the [documentation][Documentation] and [tests][Tests].

## See Also

 * [Tarantool][]
 * [Documentation][]
 * [Tests][]

[Tarantool]: http://github.com/tarantool/tarantool
[Documentation]: https://github.com/tarantool/http/wiki
[Tests]: https://github.com/tarantool/http/tree/master/test
