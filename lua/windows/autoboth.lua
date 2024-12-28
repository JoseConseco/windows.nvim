local api = vim.api
local fn = vim.fn
local calc_layout = require('windows.calculate-layout')
local config = require('windows.config')
local cache = require('windows.cache')
local Window = require('windows.lib.api').Window
local resize_windows = require('windows.lib.resize-windows').resize_windows
local merge_resize_data = require('windows.lib.resize-windows').merge_resize_data
local tbl_is_empty = vim.tbl_isempty
local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup('windows.autoboth', {})
local command = vim.api.nvim_create_user_command
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

---@type win.ResizeWindowsAnimated | nil
local animation
if config.animation.enable then
   local ResizeWindowsAnimated = require('windows.lib.resize-windows-animated')
   animation = ResizeWindowsAnimated:new()
end

local function setup_layout()
   if not curwin or not M.resizing_request then
      return
   end
   M.resizing_request = false

   local winsdata = calc_layout.autoboth(curwin)
   if tbl_is_empty(winsdata) then return end

   if cache.maximized then
      cache.maximized = nil
   end
   new_window = false

   if animation then
      animation:load(winsdata)
      animation:run()
   else
      resize_windows(winsdata)
   end
end

---Enable autoboth
function M.enable()
   autocmd('BufWinEnter', { group = augroup, callback = function(ctx)
      local win = Window(0) ---@type win.Window
      if win:is_floating()
         or (new_window and win:is_ignored())
         or win:get_type() == 'command' -- "[Command Line]" window
      then
         return
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

      -- Defer resizing to handle the case when a new buffer is opened.
      -- Then 'BufWinEnter' event will be fired after 'WinEnter'.
      vim.defer_fn(setup_layout, 10)
   end })

   autocmd('WinNew', { group = augroup, callback = function()
      new_window = true
   end })

   if animation then
      autocmd('WinClosed', { group = augroup, callback = function(ctx)
         ---Id of the closing window.
         local id = tonumber(ctx.match) --[[@as integer]]
         local win = Window(id)

         if not win:is_floating() then
            animation:finish()
         end
      end })

      autocmd('TabLeave', { group = augroup, callback = function()
         animation:finish()
      end })
   end
end

---Disable autoboth
function M.disable()
   api.nvim_clear_autocmds({ group = augroup })
end

---Toggle autoboth
function M.toggle()
   if config.autoboth.enable then
      M.disable()
      config.autoboth.enable = false
   else
      M.enable()
      config.autoboth.enable = true
   end
end

command('WindowsEnableAutoboth',  M.enable,  { bang = true })
command('WindowsDisableAutoboth', M.disable, { bang = true })
command('WindowsToggleAutoboth',  M.toggle,  { bang = true })

return M
