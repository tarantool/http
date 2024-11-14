# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed

## [1.7.0] - 2024-11-15

The release introduces a TLS support.

### Added

- SSL support (#35).
- SSL support into roles (#199).

## [1.6.0] - 2024-09-13

The release introduces a role for Tarantool 3.

### Fixed

- Fixed request crash with empty body and unexpected header
  Content-Type (#189).

### Added

- `roles.httpd` role to configure one or more HTTP servers (#196).
- `httpd:delete(name)` method to delete named routes (#197).

## [1.5.0] - 2023-03-29

### Added

- Add versioning support.

### Fixed

- Allow dot in path segment.

## [1.4.0] - 2022-12-30

### Added

- Add path_raw field. This field contains request path without encoding.

## [1.3.0] - 2022-07-27

### Changed

- Allow to use a non-standard socket (for example, `sslsocket` with TLS
  support).
- When processing a GET request, the plus sign in the parameter name and
  value is now replaced with a space. In order to explicitly pass a "+"
  sign it must be represented as "%2B".

### Added

- Add option to control keepalive connection state (#137).
- Add option to control idle connections (#137).

## [1.2.0] - 2021-11-10

### Changed

- Disable option display_errors by default.

## [1.1.1] - 2021-10-28

### Changed

- Revert all changes related to http v2 (#134).
- Rewrite TAP tests with luatest.
- Create a separate target for running tests in CMake.
- Replace io with fio module.

### Added

- Replace Travis CI with Github Actions.
- Add workflow that publish rockspec.
- Add editorconfig to configure indentation.
- Add luacheck integration.
- Add option to get cookie without escaping.
- Add option to set cookie without escaping and change escaping algorithm.

### Fixed

- Fix FindTarantool.cmake module.
- Fix SEGV_MAPERR when box httpd html escaping.

## [2.1.0] - 2020-01-30

### Added

- Return ability to set loggers for a specific route.
- Return ability to server and route to use custom loggers.

### Fixed

- Fix routes overlapping by any pattern in route's path.
- Fix req:redirect_to method.

## [2.0.1] - 2019-10-09

### Fixed

- Fix installation paths to not contain extra directories.

## [2.0.0] - 2019-10-04

### Added

- Major rewrite since version 1.x.
- Ability to be used with internal http server and an nginx upstream module
  (without modifying the backend code).
- Standardized request object (similar to WSGI).
- A new router with route priorities inspired by Mojolicious.
- Middleware support (for e.g. for centrally handling authorization).

## [1.1.0] - 2019-05-30
### Added
- Travis builds for tags.

## [1.0.6] - 2019-05-19
### Added
- Custom logger per route support.

### Fixed
- Fixed buffer reading when timeout or disconnect occurs.
- Fixed cookies formatting: stop url-encoding cookie path and quoting cookie expire date.

### Changed
- Readme updates: fix setcookie() description, how to use unix socket.

## [1.0.5] - 2018-09-03
### Changed
- Protocol upgrade: detaching mechanism is re-worked.

## [1.0.4] - 2018-08-31
### Added
- Detach callback support for protocol upgrade implementations.

## [1.0.3] - 2018-06-29
### Fixed
- Fixed eof detection.

## [1.0.2] - 2018-02-01
### Fixed
- Fixed request parsing with headers longer than 4096 bytes.

## [1.0.1] - 2018-01-22
### Added
- Added RPM and DEB specs.
- Enabled builds for Tarantool 1.7.

### Fixed
- Fixed building on Mac OS X.
- Fixed server handler and before_routes hooks.
- Fixed "data" response body rendering option.
- Fixed crash in uri_escape and uri_unescape when multiple arguments with same name.
- Fixed no distinction between PUT and DELETE methods (#25).
- Fixed compatibility with Tarantool 1.7.
- Fixed empty Content-Type header handling.
- Fixed curl delay: add support for expect=100-Continue.

## [1.0] - 2016-11-29
### Added
- Added requets peer host and port.
- Show tarantool version in HTTP header.
- Support for new Tarantool uri parser.
- Chunked encoding support in responses.
- Chunked encoding support in client.

### Changed
- Fedora 23 build is disabled.
- HTTP new sockets API.
- Refactor handler API.
- Cloud build is enabled.
- Update the list of supported OS for tarantool/build.

### Fixed
- Fixed build without -std=c99.
- Fixed socket:write() problem: use :write instead :send, use new sockets in http_client.
- Fixed directory traversal attack.
- Fixed routes with dots don't work as expected (#17).
- Fixed truncated rendered template (#18).

## [0.0.1] - 2014-05-05
