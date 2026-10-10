---
--- Wrapper around the `middleclass` dependency with a readable error when it
--- is not installed.
---
local ok, class = pcall(require, 'middleclass')
if not ok then
   error('[windows.nvim] the "middleclass" plugin is required but not found. '
         .. 'Install https://github.com/anuvyklack/middleclass', 0)
end
return class
