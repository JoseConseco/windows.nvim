---
--- Singleton
---
local util = require('windows.lib.util')
local animation_is_available, easing = pcall(require, 'animation.easing')
local mt = {}

---@class win.Config
---@field animation { enable: boolean, duration: integer, fps: integer, easing: fun(ratio: number): number }
---@field ignore { buftype: table<string, true>, filetype: table<string, true> }
local config = {
   autowidth = {
      enable = true,
      winwidth = 5,
      filetype = {
         help = 2,
      },
   },
   autoheight = {
      enable = false,
      winheight = 5,
      filetype = {
         help = 1,
      },
   },
   autoboth = {
      enable = false,
   },
   ignore = {
      buftype = { 'quickfix' },
      filetype = {
         'undotree', 'gundo',
         'NvimTree', 'neo-tree',
         'Outline' -- simrat39/symbols-outline.nvim
      }
   },
   animation = {
      enable = true,
      duration = 300,
      fps = 30,
      easing = 'in_out_sine' ---@diagnostic disable-line
   }
}

---Apply user options. Every call merges `input` into the current config, so
---calling `setup()` again with different options takes effect.
---@param input? table
---@return win.Config
function mt:__call(input)
   util.megre_config(config, input or {})
   util.convert_list_to_set(config.ignore.buftype)
   util.convert_list_to_set(config.ignore.filetype)

   if not config.animation.enable then
      return config
   end
   if not animation_is_available then
      config.animation.enable = false
      return config
   end
   if type(config.animation.easing) == 'string' then
      local name = config.animation.easing
      config.animation.easing = easing[name]
      if not config.animation.easing then
         vim.notify('[windows.nvim] unknown easing function: '..name
                    ..'; animation is disabled', vim.log.levels.WARN)
         config.animation.enable = false
      end
   end

   return config
end

setmetatable(config, mt)

return config
