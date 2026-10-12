local config = require('windows.config')
local M = {}

---Setup the plugin. Can be called several times: every call re-applies the
---given options on top of the current ones.
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

   require('windows.auto-resize').apply_config()
   require('windows.commands')
end

return M
