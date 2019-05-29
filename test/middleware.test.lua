#!/usr/bin/env tarantool

local tap = require('tap')
local middleware_module = require('http.router.middleware')

-- fix tap and http logs interleaving.
--
-- tap module writes to stdout,
-- http-server logs to stderr.
-- this results in non-synchronized output.
--
-- somehow redirecting stdout to stderr doesn't
-- remove buffering of tap logs (at least on OSX).
-- Monkeypatching to the rescue!

local orig_iowrite = io.write
package.loaded['io'].write = function(...)
    orig_iowrite(...)
    io.flush()
end

local test = tap.test("http")
test:plan(1)

test:test("ordering", function(test)  -- luacheck: ignore
  test:plan(7)

  local middleware = middleware_module.new()

  local add = function(opts, add_opts)
      local should_be_ok = not (add_opts or {}).must_fail

      local msg = ('adding middleware %s is successful'):format(opts.name)
      if not should_be_ok then
          msg = ('adding middleware %s must fail'):format(opts.name)
      end

      local ok = middleware:use(opts)
      test:is(ok, should_be_ok, msg)
  end

  local ensure_before = function(mwname1, mwname2)
      local msg = ('%s must be ordered before %s'):format(mwname1, mwname2)
      for _, mw in ipairs(middleware:ordered()) do
          if mw.name == mwname1 then
              test:ok(true, msg)
              return
          elseif mw.name == mwname2 then
              test:fail(msg)
              return
          end
      end
  end

  add({
      name = 'a'
  })

  add({
      name = 'b',
      after = 'a',
      before = 'c'
  })
  add({
      name = 'c',
  })

  ensure_before('a', 'b')
  ensure_before('b', 'c')
  ensure_before('b', 'c')

  add({
      name = 'd',
      before = 'a',
      after = 'c'
  }, {
      must_fail = true
  })

  middleware:clear()
end)
