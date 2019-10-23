local t = require('luatest')
local g = t.group('middleware')

local middleware_module = require('http.router.middleware')

g.test_ordering = function()
  local middleware = middleware_module.new()

  local add = function(opts, add_opts)
      local should_be_ok = not (add_opts or {}).must_fail

      local msg = ('adding middleware %s is successful'):format(opts.name)
      if not should_be_ok then
          msg = ('adding middleware %s must fail'):format(opts.name)
      end

      local ok = middleware:use(opts)
      t.assert_equals(ok, should_be_ok, msg)
  end

  local ensure_before = function(mwname1, mwname2)
      local msg = ('%s must be ordered before %s'):format(mwname1, mwname2)
      for _, mw in ipairs(middleware:ordered()) do
          if mw.name == mwname1 then
              -- test:ok(true, msg)
              return
          elseif mw.name == mwname2 then
              t.fail(msg)
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
end
