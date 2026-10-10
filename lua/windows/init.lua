local config = require('windows.config')
local M = {}

---Setup the plugin. Can be called several times: every call re-applies the
---given options on top of the current ones and re-enables the modules.
---@param input? table
function M.setup(input)
   config(input)

   if config.animation.enable then
      local ResizeWindowsAnimated = require('windows.lib.resize-windows-animated')
      local a = config.animation
      -- `new()` only uses the arguments the first time (singleton), so apply
      -- them explicitly for repeated `setup()` calls.
      ResizeWindowsAnimated:new(a.duration, a.fps, a.easing)
                           :reconfigure(a.duration, a.fps, a.easing)
   end

   local autowidth = require('windows.autowidth')
   local autoheight = require('windows.autoheight')
   local autoboth = require('windows.autoboth')

   autowidth.disable()
   autoheight.disable()
   autoboth.disable()

   if config.autoboth.enable then
      if config.autowidth.enable or config.autoheight.enable then
         vim.notify('[windows.nvim] autoboth is enabled, so autowidth and '
                    .. 'autoheight settings are ignored', vim.log.levels.WARN)
      end
      autoboth.enable()
   else
      if config.autowidth.enable then
         autowidth.enable()
      end
      if config.autoheight.enable then
         autoheight.enable()
      end
   end

   require('windows.commands')
end

return M
