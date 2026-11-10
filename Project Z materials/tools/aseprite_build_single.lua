-- Один кадр PNG -> .aseprite с палитрой PZ-28 и тегом.
-- Aseprite.exe -b --script-param root="D:/PRZ/Project Z materials" --script-param png=art/mech/mech_scout_se.png
--   --script-param tag=idle_se --script tools/aseprite_build_single.lua
local root, png = app.params["root"], app.params["png"]
local img = Image{ fromFile = root .. "/" .. png }
local spr = Sprite(img.width, img.height, ColorMode.RGB)
spr:setPalette(Palette{ fromFile = root .. "/art/palette/pz-28.gpl" })
spr.layers[1].name = app.params["layer"] or "body"
spr:newCel(spr.layers[1], 1, img, Point(0, 0))
spr:newTag(1, 1).name = app.params["tag"]
spr:saveAs(root .. "/" .. png:gsub("%.png$", ".aseprite"))
