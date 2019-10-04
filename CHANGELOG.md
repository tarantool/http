# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2019-10-04
### Added
- Major rewrite since version 1.x
- Ability to be used with internal http server and an nginx upstream module
  (without modifying the backend code)
- Standardized request object (similar to WSGI)
- A new router with route priorities inspired by Mojolicious
- Middleware support (for e.g. for centrally handling authorization)

## [1.0.3] - 2018-06-29
### Added
- Fixed eof detection

## [1.0.2] - 2017-12-20
### Added
- Fixed request parsing with headers longer than 4096 bytes
