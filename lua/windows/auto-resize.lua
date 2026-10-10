---
--- Factory for the automatic resizing modules: autowidth, autoheight and
--- autoboth. They share all their logic and differ only in which axis they
--- resize, so each of them is produced by `create(axis)`.
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
local autocmd = vim.api.nvim_create_autocmd
local command = vim.api.nvim_create_user_command

---@alias win.AutoResizeAxis 'width' | 'height' | 'both'

---Capitalize the first letter: 'width' -> 'Width'
---@param s string
local function capitalize(s)
   return s:sub(1, 1):upper() .. s:sub(2)
end

---@param axis win.AutoResizeAxis
---@return table
local function create(axis)
   local name = 'auto' .. axis -- 'autowidth' | 'autoheight' | 'autoboth'
   local augroup = api.nvim_create_augroup('windows.' .. name, {})
   local do_width = axis ~= 'height'
   local do_height = axis ~= 'width'
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

   ---@return win.ResizeWindowsAnimated | nil
   local function get_animation()
      if config.animation.enable then
         return require('windows.lib.resize-windows-animated'):new()
      end
   end

   ---@param win win.Window
   ---@return win.WinResizeData[]
   local function calculate(win)
      if axis == 'width' then
         return calc_layout.autowidth(win)
      elseif axis == 'height' then
         return calc_layout.autoheight(win)
      else
         return calc_layout.autoboth(win)
      end
   end

   ---Merge the data of the axis that this module does not handle, so that a
   ---maximized window gets restored on both axes.
   ---@param winsdata win.WinResizeData[]
   ---@return win.WinResizeData[]
   local function merge_maximized(winsdata)
      if not cache.maximized then return winsdata end
      if axis == 'width' and cache.maximized.height then
         local height_data = new_window and calc_layout.equalize_wins(false, true)
                             or cache.maximized.height
         winsdata = merge_resize_data(winsdata, height_data)
      elseif axis == 'height' and cache.maximized.width then
         local width_data = new_window and calc_layout.equalize_wins(true, false)
                            or cache.maximized.width
         winsdata = merge_resize_data(winsdata, width_data)
      end
      cache.maximized = nil
      return winsdata
   end

   local function setup_layout()
      if not curwin or not M.resizing_request then
         return
      end
      M.resizing_request = false

      local animation = get_animation()
      local winsdata = calculate(curwin)
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

   ---Enable automatic resizing.
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
         if do_width and curwin then
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
         if do_width and animation then
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

      if config.animation.enable then
         if do_width then
            autocmd('WinLeave', { group = augroup, callback = function()
               local win = Window() ---@type win.Window
               local animation = get_animation()
               if not win:is_floating() and not win:is_ignored()
                  and animation and not animation:is_running()
               then
                  cache.cursor_virtcol[win] = fn.wincol() - win:get_text_offset()
               end
            end })
         end

         autocmd('WinClosed', { group = augroup, callback = function(ctx)
            ---Id of the closing window.
            local id = tonumber(ctx.match) --[[@as integer]]
            local win = Window(id)

            if not win:is_floating() then
               local animation = get_animation()
               if animation then animation:finish() end
               if do_width then cache.cursor_virtcol[id] = nil end
            end
         end })

         autocmd('TabLeave', { group = augroup, callback = function()
            local animation = get_animation()
            if animation then animation:finish() end
         end })
      end
   end

   ---Disable automatic resizing.
   function M.disable()
      api.nvim_clear_autocmds({ group = augroup })
      M.resizing_request = false
   end

   ---Toggle automatic resizing.
   function M.toggle()
      if config[name].enable then
         M.disable()
         config[name].enable = false
      else
         M.enable()
         config[name].enable = true
      end
   end

   local Name = capitalize(name) -- 'Autowidth' | 'Autoheight' | 'Autoboth'
   command('WindowsEnable' .. Name,  M.enable,  {})
   command('WindowsDisable' .. Name, M.disable, {})
   command('WindowsToggle' .. Name,  M.toggle,  {})

   return M
end

return { create = create }
