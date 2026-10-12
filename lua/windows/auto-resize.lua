---
--- Automatic resizing of the current window. Width and height are handled by
--- the same module and can be enabled independently through
--- `config.autowidth.enable` and `config.autoheight.enable`. When both are
--- enabled the layout is computed for both axes in a single pass.
---
local api = vim.api
local fn = vim.fn
local calc_layout = require('windows.calculate-layout')
local config = require('windows.config')
local cache = require('windows.cache')
local Window = require('windows.lib.api').Window
local resize_windows = require('windows.lib.resize-windows').resize_windows
local merge_resize_data = require('windows.lib.resize-windows').merge_resize_data
local tbl_is_empty = vim.tbl_isempty
local autocmd = api.nvim_create_autocmd
local augroup = api.nvim_create_augroup('windows.auto-resize', {})
local command = api.nvim_create_user_command
local M = {}

local curwin   ---@type win.Window
local curbufnr ---@type integer

---Flag for when a new window has been created.
---@type boolean
local new_window = false

---To avoid multiple layout resizing in row, when several autocommands were
---triggered.
---@type boolean
M.resizing_request = false

local function do_width()  return config.autowidth.enable  end
local function do_height() return config.autoheight.enable end

---Is any axis enabled?
function M.is_enabled()
   return do_width() or do_height()
end

---@return win.ResizeWindowsAnimated | nil
local function get_animation()
   if config.animation.enable then
      return require('windows.lib.resize-windows-animated'):new()
   end
end

---Merge the data of the axis that is not handled automatically, so that a
---maximized window gets restored on both axes.
---@param winsdata win.WinResizeData[]
---@return win.WinResizeData[]
local function merge_maximized(winsdata)
   if not cache.maximized then return winsdata end
   if not do_height() and cache.maximized.height then
      local height_data = new_window and calc_layout.equalize_wins(false, true)
                          or cache.maximized.height
      winsdata = merge_resize_data(winsdata, height_data)
   elseif not do_width() and cache.maximized.width then
      local width_data = new_window and calc_layout.equalize_wins(true, false)
                         or cache.maximized.width
      winsdata = merge_resize_data(winsdata, width_data)
   end
   cache.maximized = nil
   return winsdata
end

local function setup_layout()
   if not curwin or not M.resizing_request or not M.is_enabled() then
      return
   end
   M.resizing_request = false

   local animation = get_animation()
   local winsdata = calc_layout.auto(curwin, do_width(), do_height())
   if tbl_is_empty(winsdata) then
      if animation then animation:restore_virtualedit() end
      return
   end

   winsdata = merge_maximized(winsdata)
   new_window = false

   if animation then
      animation:load(winsdata)
      animation:run()
   else
      resize_windows(winsdata)
   end
end

---Prepare the cursor for a width animation: when the cursor is beyond the
---width the window will shrink to, move it to the edge so the view does not
---scroll horizontally during the animation.
---@param animation win.ResizeWindowsAnimated
local function prepare_cursor(animation)
   local virtcol = cache.cursor_virtcol[curwin]
   if not virtcol or not animation:cursor_can_be_moved() then return end
   local leftcol = fn.winsaveview().leftcol
   local width = curwin:get_width() - curwin:get_text_offset()
   if leftcol == 0 and width < virtcol then
      cache.virtualedit = {
         win = curwin,
         value = curwin:get_option('virtualedit')
      }
      curwin:set_option('virtualedit', 'all')
      api.nvim_feedkeys(width .. '|', 'nx', false)
      fn.winrestview({ leftcol = 0 })
   end
end

---Request a layout recalculation for the current window.
function M.request_layout()
   if not M.is_enabled() then return end
   M.resizing_request = true
   vim.schedule(setup_layout)
end

---Register the autocommands (idempotent).
function M.enable()
   api.nvim_clear_autocmds({ group = augroup })

   autocmd('BufWinEnter', { group = augroup, callback = function(ctx)
      local win = Window(0) ---@type win.Window
      if win:is_floating()
         or (new_window and win:is_ignored())
         or win:get_type() == 'command' -- "[Command Line]" window
      then
         return
      end
      if curwin then
         cache.cursor_virtcol[curwin] = nil
      end

      M.resizing_request = true

      curbufnr = ctx.buf
      setup_layout()
   end })

   autocmd('VimResized', { group = augroup, callback = function()
      M.resizing_request = true
      setup_layout()
   end })

   autocmd('WinEnter', { group = augroup, callback = function(ctx)
      local win = Window(0) ---@type win.Window
      if win:is_floating()
         or win:is_ignored()
         or (win == curwin and ctx.buf == curbufnr)
      then
         return
      end
      curwin = win

      M.resizing_request = true

      local animation = get_animation()
      if do_width() and animation then
         prepare_cursor(animation)
      end

      -- Postpone resizing to handle the case when a new buffer is opened.
      -- Then 'BufWinEnter' event will be fired after 'WinEnter', and
      -- the scheduled call will find `resizing_request` already consumed.
      vim.schedule(setup_layout)
   end })

   autocmd('WinNew', { group = augroup, callback = function()
      new_window = true
   end })

   -- A plugin can mark a window as fixed-size right after creating it (e.g.
   -- the Diffview panels), when a resize calculated for it as a regular window
   -- may be already in flight. Such a stale layout must not be applied: abort
   -- the animation and calculate the layout again with the new constraints.
   autocmd('OptionSet', {
      group = augroup,
      pattern = { 'winfixwidth', 'winfixheight' },
      callback = function()
         if vim.v.option_new == vim.v.option_old then return end
         local animation = get_animation()
         if animation and animation:is_running() then
            animation:finish()
         end
         M.request_layout()
      end
   })

   if config.animation.enable then
      autocmd('WinLeave', { group = augroup, callback = function()
         if not do_width() then return end
         local win = Window() ---@type win.Window
         local animation = get_animation()
         if not win:is_floating() and not win:is_ignored()
            and animation and not animation:is_running()
         then
            cache.cursor_virtcol[win] = fn.wincol() - win:get_text_offset()
         end
      end })

      autocmd('WinClosed', { group = augroup, callback = function(ctx)
         ---Id of the closing window.
         local id = tonumber(ctx.match) --[[@as integer]]
         local win = Window(id)

         if not win:is_floating() then
            local animation = get_animation()
            if animation then animation:finish() end
            cache.cursor_virtcol[id] = nil
         end
      end })

      autocmd('TabLeave', { group = augroup, callback = function()
         local animation = get_animation()
         if animation then animation:finish() end
      end })
   end
end

---Remove the autocommands.
function M.disable()
   api.nvim_clear_autocmds({ group = augroup })
   M.resizing_request = false
end

---Enable or disable automatic resizing according to the config flags.
function M.apply_config()
   if M.is_enabled() then
      M.enable()
   else
      M.disable()
   end
end

---@param axis 'autowidth' | 'autoheight'
---@param value boolean
local function set_axis(axis, value)
   config[axis].enable = value
   M.apply_config()
end

M.enable_autowidth   = function() set_axis('autowidth', true) end
M.disable_autowidth  = function() set_axis('autowidth', false) end
M.toggle_autowidth   = function() set_axis('autowidth', not config.autowidth.enable) end
M.enable_autoheight  = function() set_axis('autoheight', true) end
M.disable_autoheight = function() set_axis('autoheight', false) end
M.toggle_autoheight  = function() set_axis('autoheight', not config.autoheight.enable) end

command('WindowsEnableAutowidth',   M.enable_autowidth,   {})
command('WindowsDisableAutowidth',  M.disable_autowidth,  {})
command('WindowsToggleAutowidth',   M.toggle_autowidth,   {})
command('WindowsEnableAutoheight',  M.enable_autoheight,  {})
command('WindowsDisableAutoheight', M.disable_autoheight, {})
command('WindowsToggleAutoheight',  M.toggle_autoheight,  {})

return M
