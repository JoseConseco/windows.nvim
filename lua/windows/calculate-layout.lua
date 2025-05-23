local Frame = require('windows.lib.frame')
local merge_resize_data = require('windows.lib.resize-windows').merge_resize_data
local M = {}

---Calculate layout for autowidth
---@param curwin win.Window
---@return win.WinResizeData[]
function M.autowidth(curwin)
   local topFrame = Frame() ---@type win.Frame
   if topFrame.type == 'leaf' then
      return {}
   end

   if curwin:is_valid()
      and not curwin:is_floating()
      and not curwin:get_option('winfixwidth')
      and not curwin:is_ignored()
   then
      local curwinLeaf = topFrame:find_window(curwin)
      local topFrame_width = topFrame:get_width()
      local curwin_wanted_width = curwin:get_wanted_width()
      local topFrame_wanted_width = topFrame:get_min_width(curwin, curwin_wanted_width)

      if topFrame_wanted_width > topFrame_width then
         topFrame:maximize_window(curwinLeaf, true, false)
      else
         topFrame:autowidth(curwinLeaf)
      end
   else
      topFrame:equalize_windows(true, false)
   end

   local data = topFrame:get_data_for_width_resizing()
   return data
end

---Calculate layout for autoheight
---@param curwin win.Window
---@return win.WinResizeData[]
function M.autoheight(curwin)
   local topFrame = Frame() ---@type win.Frame
   if topFrame.type == 'leaf' then
      return {}
   end

   if curwin:is_valid()
      and not curwin:is_floating()
      and not curwin:get_option('winfixheight')
      and not curwin:is_ignored()
   then
      local curwinLeaf = topFrame:find_window(curwin)
      local topFrame_height = topFrame:get_height()
      local curwin_wanted_height = curwin:get_wanted_height()
      local topFrame_wanted_height = topFrame:get_min_height(curwin, curwin_wanted_height)

      if topFrame_wanted_height > topFrame_height then
         topFrame:maximize_window(curwinLeaf, false, true)
      else
         topFrame:autoheight(curwinLeaf)
      end
   else
      topFrame:equalize_windows(false, true)
   end

   local data = topFrame:get_data_for_height_resizing()
   return data
end

---@param win win.Window
---@param do_width boolean
---@param do_height boolean
---@return win.WinResizeData[] width
---@return win.WinResizeData[] height
function M.maximize_win(win, do_width, do_height)
   local topFrame = Frame() ---@type win.Frame
   if topFrame.type == 'leaf' then
      return {}, {}
   end

   local winLeaf = topFrame:find_window(win)
   topFrame:maximize_window(winLeaf, do_width, do_height)

   local width_data = topFrame:get_data_for_width_resizing()
   local height_data = topFrame:get_data_for_height_resizing()

   return width_data, height_data
end

---Calculate layout for autoboth (width and height)
---@param curwin win.Window
---@return win.WinResizeData[]
function M.autoboth(curwin)
   local topFrame = Frame() ---@type win.Frame
   if topFrame.type == 'leaf' then
      return {}
   end

   if curwin:is_valid()
      and not curwin:is_floating()
      and not curwin:get_option('winfixwidth')
      and not curwin:get_option('winfixheight')
      and not curwin:is_ignored()
   then
      local curwinLeaf = topFrame:find_window(curwin)
      local topFrame_width = topFrame:get_width()
      local topFrame_height = topFrame:get_height()
      local curwin_wanted_width = curwin:get_wanted_width()
      local curwin_wanted_height = curwin:get_wanted_height()
      local topFrame_wanted_width = topFrame:get_min_width(curwin, curwin_wanted_width)
      local topFrame_wanted_height = topFrame:get_min_height(curwin, curwin_wanted_height)

      if topFrame_wanted_width > topFrame_width or topFrame_wanted_height > topFrame_height then
         topFrame:maximize_window(curwinLeaf, true, true)
      else
         topFrame:autowidth(curwinLeaf)
         topFrame:autoheight(curwinLeaf)
      end
   else
      topFrame:equalize_windows(true, true)
   end

   local width_data = topFrame:get_data_for_width_resizing()
   local height_data = topFrame:get_data_for_height_resizing()
   return merge_resize_data(width_data, height_data)
end

---@param do_width boolean
---@param do_height boolean
---@return win.WinResizeData[]
function M.equalize_wins(do_width, do_height)
   assert(do_width or do_height, 'No arguments have been passed')
   local topFrame = Frame() ---@type win.Frame
   if topFrame.type == 'leaf' then
      return {}
   end

   topFrame:equalize_windows(do_width, do_height)

   if do_width and not do_height then
      return topFrame:get_data_for_width_resizing()
   elseif not do_width and do_height then
      return topFrame:get_data_for_height_resizing()
   else
      return merge_resize_data(topFrame:get_data_for_width_resizing(),
                               topFrame:get_data_for_height_resizing())
   end
end

return M
