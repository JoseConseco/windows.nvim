local Frame = require('windows.lib.frame')
local merge_resize_data = require('windows.lib.resize-windows').merge_resize_data
local M = {}

---Calculate the automatic layout for the current window on the requested
---axes. Each axis is decided on its own: a layout that does not fit
---vertically (e.g. a fixed-height panel at the bottom) must not cause the
---window to be maximized horizontally as well.
---@param curwin win.Window
---@param do_width boolean
---@param do_height boolean
---@return win.WinResizeData[]
function M.auto(curwin, do_width, do_height)
   assert(do_width or do_height, 'No axis has been requested')
   local topFrame = Frame() ---@type win.Frame
   if topFrame.type == 'leaf' then
      return {}
   end

   local curwinLeaf
   if curwin:is_valid() and not curwin:is_floating() and not curwin:is_ignored() then
      curwinLeaf = topFrame:find_window(curwin)
      if not curwinLeaf then return {} end
   end

   if do_width then
      if curwinLeaf and not curwin:get_option('winfixwidth') then
         local wanted = topFrame:get_min_width(curwin, curwin:get_wanted_width())
         if wanted > topFrame:get_width() then
            topFrame:maximize_window(curwinLeaf, true, false)
         else
            topFrame:autowidth(curwinLeaf)
         end
      else
         topFrame:equalize_windows(true, false)
      end
   end

   if do_height then
      if curwinLeaf and not curwin:get_option('winfixheight') then
         local wanted = topFrame:get_min_height(curwin, curwin:get_wanted_height())
         if wanted > topFrame:get_height() then
            topFrame:maximize_window(curwinLeaf, false, true)
         else
            topFrame:autoheight(curwinLeaf)
         end
      else
         topFrame:equalize_windows(false, true)
      end
   end

   if do_width and not do_height then
      return topFrame:get_data_for_width_resizing()
   elseif do_height and not do_width then
      return topFrame:get_data_for_height_resizing()
   end
   return merge_resize_data(topFrame:get_data_for_width_resizing(),
                            topFrame:get_data_for_height_resizing())
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
   if not winLeaf then return {}, {} end
   topFrame:maximize_window(winLeaf, do_width, do_height)

   local width_data = topFrame:get_data_for_width_resizing()
   local height_data = topFrame:get_data_for_height_resizing()

   return width_data, height_data
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
