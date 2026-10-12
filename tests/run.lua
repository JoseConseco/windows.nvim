-- Headless test runner. Run from the plugin root:
--
--    nvim --headless -u NONE -l tests/run.lua
--
-- The `middleclass` and `animation.nvim` plugins must be siblings of this
-- plugin directory (as with lazy.nvim), or on the runtimepath already.

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
for _, dep in ipairs({ 'middleclass', 'animation.nvim' }) do
   vim.opt.rtp:append(vim.fn.fnamemodify(root, ':h') .. '/' .. dep)
end
vim.o.columns = 120
vim.o.lines = 40

local failed = 0
local function test(name, fun)
   local ok, err = pcall(fun)
   if ok then
      print('ok   ' .. name)
   else
      failed = failed + 1
      print('FAIL ' .. name .. '\n     ' .. tostring(err))
   end
end

local function eq(expected, actual, msg)
   if not vim.deep_equal(expected, actual) then
      error((msg or 'not equal') .. ': expected ' .. vim.inspect(expected)
            .. ', got ' .. vim.inspect(actual), 2)
   end
end

local function wait_animation()
   vim.wait(600, function() return false end)
end

local function reset_windows()
   vim.cmd('silent! only!')
   vim.cmd('enew!')
end

local function autocmd_count(group)
   return #vim.api.nvim_get_autocmds({ group = group })
end

--------------------------------------------------------------------------------

test('config: lists replace defaults, unknown nested table does not crash', function()
   local config = require('windows.config')
   config({ ignore = { filetype = { 'foo' } }, unknown = { nested = true } })
   eq({ foo = true }, config.ignore.filetype)
   eq({ quickfix = true }, config.ignore.buftype)
   eq({ nested = true }, config.unknown)
end)

test('config: unknown easing disables animation with a warning', function()
   local config = require('windows.config')
   local notified
   local notify = vim.notify
   vim.notify = function(msg) notified = msg end
   config({ animation = { enable = true, easing = 'does_not_exist' } })
   vim.notify = notify
   eq(false, config.animation.enable)
   assert(notified and notified:find('does_not_exist'), 'no warning was shown')
   config({ animation = { enable = true, easing = 'in_out_sine' } })
   eq(true, config.animation.enable)
   eq('function', type(config.animation.easing))
end)

test('setup: legacy autoboth option enables both axes with a warning', function()
   local notified
   local notify = vim.notify
   vim.notify = function(msg) notified = msg end
   require('windows').setup({ autoboth = { enable = true } })
   vim.notify = notify
   assert(notified and notified:find('autoboth'), 'no warning was shown')
   local config = require('windows.config')
   eq(true, config.autowidth.enable)
   eq(true, config.autoheight.enable)
   eq(nil, config.autoboth)
   assert(autocmd_count('windows.auto-resize') > 0, 'auto-resize not enabled')
end)

test('setup: can be called again and switches modes', function()
   require('windows').setup({ autowidth = { enable = false }, autoheight = { enable = false } })
   eq(0, autocmd_count('windows.auto-resize'))
   require('windows').setup({ autowidth = { enable = true } })
   assert(autocmd_count('windows.auto-resize') > 0, 'auto-resize not enabled')
end)

test('enable twice does not duplicate autocmds', function()
   local auto_resize = require('windows.auto-resize')
   auto_resize.enable()
   local n = autocmd_count('windows.auto-resize')
   auto_resize.enable()
   eq(n, autocmd_count('windows.auto-resize'))
   vim.cmd('WindowsEnableAutowidth')
   eq(n, autocmd_count('windows.auto-resize'))
   vim.cmd('WindowsDisableAutowidth')
   eq(0, autocmd_count('windows.auto-resize'))
   vim.cmd('WindowsToggleAutoheight')
   assert(autocmd_count('windows.auto-resize') > 0, 'autoheight toggle did not enable')
   vim.cmd('WindowsDisableAutoheight')
end)

test('wanted height is an integer', function()
   local Window = require('windows.lib.api').Window
   local h = Window(0):get_wanted_height()
   eq(h, math.floor(h))
end)

for _, mode in ipairs({ 'width', 'height', 'both' }) do
   test(mode .. ': split, switch, maximize, equalize, close do not error', function()
      reset_windows()
      require('windows').setup({
         autowidth = { enable = mode ~= 'height' },
         autoheight = { enable = mode ~= 'width' },
      })
      vim.cmd('vsplit | split | enew')
      wait_animation()
      vim.cmd('wincmd w')
      wait_animation()
      vim.cmd('WindowsMaximize')
      wait_animation()
      vim.cmd('wincmd w') -- auto module restores the maximized layout
      wait_animation()
      vim.cmd('WindowsEqualize')
      wait_animation()
      eq(nil, require('windows.cache').maximized)
      vim.cmd('close')
      wait_animation()
      eq(2, #vim.api.nvim_list_wins())
   end)
end

test('closed window during animation does not error', function()
   reset_windows()
   require('windows').setup({ autowidth = { enable = true }, autoheight = { enable = false } })
   vim.cmd('vsplit | vsplit')
   vim.cmd('wincmd w')
   vim.wait(20) -- let the scheduled resize start the animation
   vim.cmd('close')
   wait_animation()
   eq(2, #vim.api.nvim_list_wins())
end)

test('virtualedit is restored after the animation', function()
   reset_windows()
   require('windows').setup({ autowidth = { enable = true }, autoheight = { enable = false } })
   vim.api.nvim_set_option_value('virtualedit', '', { win = 0 })
   vim.cmd('vsplit')
   wait_animation()
   vim.cmd('wincmd w')
   wait_animation()
   for _, w in ipairs(vim.api.nvim_list_wins()) do
      eq('', vim.api.nvim_get_option_value('virtualedit', { win = w }), 'win ' .. w)
   end
   eq(nil, require('windows.cache').virtualedit)
end)

test('cursor is not moved while not in normal mode', function()
   -- ':startinsert' has no effect in `nvim -l` (no main loop), so stub the
   -- mode instead and check that no normal mode keys are fed.
   reset_windows()
   require('windows').setup({ autowidth = { enable = true }, autoheight = { enable = false } })
   vim.cmd('vsplit')
   wait_animation()
   local get_mode, feedkeys = vim.api.nvim_get_mode, vim.api.nvim_feedkeys
   local fed = 0
   vim.api.nvim_get_mode = function() return { mode = 'i', blocking = false } end
   vim.api.nvim_feedkeys = function(...) fed = fed + 1; return feedkeys(...) end
   local ok, err = pcall(function()
      vim.cmd('wincmd w')
      wait_animation()
   end)
   vim.api.nvim_get_mode, vim.api.nvim_feedkeys = get_mode, feedkeys
   assert(ok, err)
   eq(0, fed, 'keys were fed in insert mode')
   -- In normal mode the animation does feed keys.
   fed = 0
   vim.api.nvim_feedkeys = function(...) fed = fed + 1; return feedkeys(...) end
   vim.cmd('wincmd w')
   wait_animation()
   vim.api.nvim_feedkeys = feedkeys
   assert(fed > 0, 'no keys were fed in normal mode')
end)

test('fixed-height bottom panel does not maximize width (DiffviewFileHistory layout)', function()
   -- Layout:  [ A | B ]  over a 'winfixheight' panel taller than what fits.
   reset_windows()
   require('windows').setup({
      autowidth = { enable = true, winwidth = 1.5 },
      autoheight = { enable = true, winheight = 0.62 },
   })
   vim.cmd('botright split')
   vim.api.nvim_set_option_value('winfixheight', true, { win = 0 })
   vim.api.nvim_win_set_height(0, 32)
   vim.cmd('wincmd k')
   vim.cmd('vsplit')
   wait_animation()
   vim.cmd('wincmd l')
   wait_animation()
   local cur = vim.api.nvim_get_current_win()
   local w = vim.api.nvim_win_get_width(cur)
   local wanted = require('windows.lib.api').Window(cur):get_wanted_width()
   assert(w <= wanted + 1, ('window was maximized: width %d, wanted %d'):format(w, wanted))
   assert(w >= vim.o.winminwidth, 'window narrower than winminwidth')
end)

test('window made fixed-size mid-animation does not get a stale layout (Diffview panel)', function()
   -- A panel is created and focused as a regular window, so a resize that gives
   -- it the golden-ratio height starts. Then it becomes 'winfixheight' with a
   -- small height, like Diffview does. The in-flight animation must not undo it.
   reset_windows()
   require('windows').setup({
      autowidth = { enable = true },
      autoheight = { enable = true, winheight = 0.62 },
      animation = { enable = true, duration = 300 },
   })
   vim.cmd('vsplit')
   wait_animation()
   vim.cmd('botright split | enew')
   vim.wait(30) -- the scheduled resize has started animating
   local panel = vim.api.nvim_get_current_win()
   -- Like Diffview, change the options without firing any event.
   vim.cmd('noautocmd lua vim.api.nvim_set_option_value("winfixheight", true, { win = ' .. panel .. ' })')
   vim.cmd('noautocmd lua vim.api.nvim_win_set_height(' .. panel .. ', 8)')
   wait_animation()
   wait_animation()
   local h = vim.api.nvim_win_get_height(panel)
   eq(8, h, 'panel height')
   local total = vim.o.lines - vim.o.cmdheight - 1
   for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= panel then
         eq(total - 8 - 1, vim.api.nvim_win_get_height(w), 'diff window height')
      end
   end
end)

--------------------------------------------------------------------------------

print(failed == 0 and 'ALL TESTS PASSED' or (failed .. ' TEST(S) FAILED'))
vim.cmd(failed == 0 and 'qall!' or 'cquit!')
