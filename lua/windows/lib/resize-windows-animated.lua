---
--- Singleton
---
local singleton = require('windows.class.singleton')
local Animation = require('animation')
local Window = require('windows.lib.api').Window
local cache = require('windows.cache')
local round = require('windows.lib.util').round
local winsaveview = vim.fn.winsaveview

---@class win.ResizeWindowsAnimated.Data
---@field win win.Window
---@field initial_width?  integer
---@field initial_height? integer
---@field final_width?    integer
---@field final_height?   integer
---@field delta_width?    integer The delta between initial and final widths.
---@field delta_height?   integer The delta between initial and final heights.

---@class win.ResizeWindowsAnimated : nvim.Animation
---@field winsdata win.ResizeWindowsAnimated.Data[]
---@field curwin win.Window
---@field cursor_pos? { [1]: integer, [2]: integer } The cursor position of the current window
---@field cursor_virtcol? integer
---@field new fun(...):win.ResizeWindowsAnimated
local ResizeWindowsAnimated = singleton(Animation)

function ResizeWindowsAnimated:initialize(duration, fps, easing)
   Animation.initialize(self, duration, fps, easing, nil)
end

---Apply new animation parameters to the existing singleton instance.
function ResizeWindowsAnimated:reconfigure(duration, fps, easing)
   if self:is_running() then self:finish() end
   Animation.initialize(self, duration, fps, easing, nil)
end

---The cursor is moved with normal mode commands during the animation. They
---are only safe to send when Neovim is in normal mode and not waiting for
---input (operator pending, cmdline, insert, ...).
---@return boolean
function ResizeWindowsAnimated:cursor_can_be_moved()
   local mode = vim.api.nvim_get_mode()
   return mode.mode:sub(1, 1) == 'n' and not mode.blocking
end

---Restore the 'virtualedit' option that was temporary changed to 'all' before
---the animation. Safe to call at any moment.
function ResizeWindowsAnimated:restore_virtualedit()
   local ve = cache.virtualedit
   if ve and ve.win and ve.win:is_valid() then
      ve.win:set_option('virtualedit', ve.value)
   end
   cache.virtualedit = nil
   self.virtualedit = nil
end

---A string that describes which windows of the current tab page have fixed
---size. If it changes during the animation, the layout the animation was
---calculated for is stale.
---@return string
local function fixed_size_signature()
   local parts = {}
   for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local wfw = vim.api.nvim_get_option_value('winfixwidth', { win = win })
      local wfh = vim.api.nvim_get_option_value('winfixheight', { win = win })
      parts[#parts + 1] = win .. (wfw and 'w' or '') .. (wfh and 'h' or '')
   end
   return table.concat(parts, ',')
end

---@param winsdata win.WinResizeData[]
function ResizeWindowsAnimated:load(winsdata)
   if self:is_running() then self:finish() end

   self.winsdata = {}
   for _, wd in ipairs(winsdata) do
      if not wd.win:is_valid() then goto continue end
      local data = {}
      data.win = wd.win
      if wd.width then
         local fin = wd.width -- final
         local init = wd.win:get_width() -- initial
         data.initial_width = init
         data.delta_width = fin - init -- delta
      end
      if wd.height then
         local fin = wd.height -- final
         local init = wd.win:get_height() -- initial
         data.initial_height = init
         data.delta_height = fin - init -- delta
      end
      table.insert(self.winsdata, data)
      ::continue::
   end

   self.curwin = Window(0)
   self.signature = fixed_size_signature()

   if winsaveview().leftcol == 0 then
      self.cursor_virtcol = cache.cursor_virtcol[self.curwin]
   end

   self:set_callback(function(fraction)
      -- Some plugins (e.g. Diffview) make a window fixed-size right after
      -- creating it, without firing any event. The resize calculated before
      -- that is stale: abort it and ask for a fresh calculation.
      if fixed_size_signature() ~= self.signature then
         self:finish()
         vim.schedule(function()
            local auto_resize = package.loaded['windows.auto-resize']
            if auto_resize then auto_resize.request_layout() end
         end)
         return true
      end

      for _, d in ipairs(self.winsdata) do
         if not d.win:is_valid() then goto continue end
         if d.delta_width then
            local width = d.initial_width + round(fraction * d.delta_width)
            d.win:set_width(width)
         end
         if d.delta_height then
            local height = d.initial_height + round(fraction * d.delta_height)
            d.win:set_height(height)
         end
         ::continue::
      end

      if not self.curwin:is_valid()
         or self.curwin.id ~= vim.api.nvim_get_current_win()
         or not self:cursor_can_be_moved()
      then
         return
      end

      if self.cursor_virtcol then
         local width = self.curwin:get_width() - self.curwin:get_text_offset()
         local col
         if width < self.cursor_virtcol then
            col = width
         else
            col = self.cursor_virtcol
            self.cursor_virtcol = nil
         end
         vim.api.nvim_feedkeys(col..'|', 'nx', false)
      else
         vim.api.nvim_feedkeys('ze', 'nx', false)
      end
   end)
end

function ResizeWindowsAnimated:run()
   if self:is_running() then return end

   if self.cursor_virtcol and cache.virtualedit and cache.virtualedit.win == self.curwin then
      self.virtualedit = cache.virtualedit.value
   else
      -- 'virtualedit' was changed for another window, or no animation needs it.
      self:restore_virtualedit()
      self.virtualedit = vim.api.nvim_get_option_value('virtualedit', { win = 0 })
   end

   Animation.run(self)
end

function ResizeWindowsAnimated:finish()
   if self:is_running() then
      Animation.finish(self)
      if self.virtualedit and self.curwin and self.curwin:is_valid() then
         self.curwin:set_option('virtualedit', self.virtualedit)
      end
   end
   self:restore_virtualedit()
   self.winsdata = {}
end

return ResizeWindowsAnimated
