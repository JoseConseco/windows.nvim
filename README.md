# windows.nvim

- Automatically expand width and/or height of the current window;
- Maximizes and restores the current window.

And all this with nice animations!

https://user-images.githubusercontent.com/13056013/190786962-01047891-38b1-4e87-bd9b-e8eca9acc8b8.mp4

## Installation and setup

This plugin requires next dependencies:

- [middleclass](https://github.com/anuvyklack/middleclass)  
- [animation.nvim](https://github.com/anuvyklack/animation.nvim) — optional:
  needed if you want animations

Also, if you enable animations, is recommended to set `winwidth`, `winminwidth`
options to some reasonable and equal values (between 5 and 20 will be OK), and
disable `equalalways` option.

You can install and setup **windows.nvim** with [packer](https://github.com/wbthomason/packer.nvim)
plugin manager using next snippet:

- with animation
  ```lua
  use { "anuvyklack/windows.nvim",
     requires = {
        "anuvyklack/middleclass",
        "anuvyklack/animation.nvim"
     },
     config = function()
        vim.o.winwidth = 10
        vim.o.winminwidth = 10
        vim.o.equalalways = false
        require('windows').setup()
     end
  }
  ```

- without animation
  ```lua
  use { "anuvyklack/windows.nvim",
     requires = "anuvyklack/middleclass",
     config = function()
        require('windows').setup()
     end
  }
  ```

## Configuration

Default settings (every option is optional; `setup()` merges them into these):

```lua
require("windows").setup({
   autowidth = {
      enable = true,       -- resize the current window's width automatically
      winwidth = 5,        -- wanted width: 0<n<1 fraction of screen, 1<n<2 fraction of 'textwidth', else 'textwidth' + n
      filetype = {         -- per-filetype override of `winwidth`
         help = 2,
      },
   },
   autoheight = {
      enable = false,      -- resize the current window's height automatically
      winheight = 5,       -- wanted height: 0<n<1 fraction of screen, 1<n<2 fraction of buffer lines, else lines + n (max 61% of screen)
      filetype = {         -- per-filetype override of `winheight`
         help = 2,
      },
   },
   ignore = {
      buftype = { "quickfix" },                                    -- buffer types never resized
      filetype = { "NvimTree", "neo-tree", "undotree", "gundo" },  -- filetypes never resized
   },
   animation = {
      enable = true,       -- animate resizing (needs animation.nvim)
      duration = 300,      -- animation length in milliseconds
      fps = 30,            -- animation frames per second
      easing = "in_out_sine", -- easing function name from animation.nvim
   },
})
```

Enable both `autowidth` and `autoheight` to resize in both axes at once.
The old `autoboth` option was removed; setting it still works but warns.

Read more in the [documentation](https://github.com/anuvyklack/windows.nvim/blob/main/doc/windows.txt).

## Commands

- `:WindowsMaximize`

  Maximize current window. If the window is already maximized, then restore
  original sizes.  When go to another window while current is maximized - all
  original sizes will be restored.  If the window will be closed while being
  maximized, then all other windows would be equalized.

- `:WindowsMaximizeVertically`

  Maximize width of the current window. Almost the same as `:vertical resize`
  (see `:help CTRL-W_bar`) but with animation.

- `:WindowsMaximizeHorizontally`

  Maximize height of the current window. Almost the same as `:resize`
  (see `:help CTRL-W__`) but with animation.

- `:WindowsEqualize`

  Equalize all windows heights and widths width animation.
  (see `:help CTRL-W_=`)

- `:WindowsEnableAutowidth`  
  `:WindowsDisableAutowidth`  
  `:WindowsToggleAutowidth`

  Enable, disable or toggle auto-width feature.

- `:WindowsEnableAutoheight`  
  `:WindowsDisableAutoheight`  
  `:WindowsToggleAutoheight`

  Enable, disable or toggle auto-height feature.

## Keymapings

If you want a keymaps thees are a fitting choice:

```lua
local function cmd(command)
   return table.concat({ '<Cmd>', command, '<CR>' })
end

vim.keymap.set('n', '<C-w>z', cmd 'WindowsMaximize')
vim.keymap.set('n', '<C-w>_', cmd 'WindowsMaximizeVertically')
vim.keymap.set('n', '<C-w>|', cmd 'WindowsMaximizeHorizontally')
vim.keymap.set('n', '<C-w>=', cmd 'WindowsEqualize')
```

## Proposals

If you have any proposals, what else can be done with this mechanics, you are
welcome to open an issue.
