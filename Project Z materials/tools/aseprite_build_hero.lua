-- Сборка анимации героя в Aseprite: палитра PZ-28, кадры по направлениям, теги, длительности.
-- Aseprite.exe -b --script-param root="C:/Project Z materials" --script-param anim=walk
--   --script-param frames=6 --script-param fps=11 --script tools/aseprite_build_hero.lua
-- Слои (hero_layers.py): --script-param src=art/hero/layers/render --script-param prefix=U_
--   --script-param out=art/hero/layers  (кадры <prefix><anim>_<dir>_<n>.png, файл <out>/<prefix><anim>.aseprite)
local root = app.params["root"]
local anim = app.params["anim"]
local frames = tonumber(app.params["frames"])
local fps = tonumber(app.params["fps"] or "10")
local src = app.params["src"] or "art/hero/render"
local prefix = app.params["prefix"] or "hero_"
local out = app.params["out"] or "art/hero"
-- для боевых анимаций: длительности кадров в мс через запятую (вместо постоянного fps)
local durs = {}
for v in string.gmatch(app.params["durations"] or "", "[^,]+") do durs[#durs + 1] = tonumber(v) / 1000 end
local dirs = { "s", "se", "e", "ne", "n", "nw", "w", "sw" }

local spr = Sprite(tonumber(app.params["w"] or "64"), tonumber(app.params["h"] or "96"), ColorMode.RGB)
spr:setPalette(Palette{ fromFile = root .. "/art/palette/pz-28.gpl" })
spr.layers[1].name = "hero"

local n = 0
for _, d in ipairs(dirs) do
  for f = 0, frames - 1 do
    n = n + 1
    if n > 1 then spr:newEmptyFrame() end
    local img = Image{ fromFile = string.format("%s/%s/%s%s_%s_%d.png", root, src, prefix, anim, d, f) }
    spr:newCel(spr.layers[1], n, img, Point(0, 0))
    spr.frames[n].duration = durs[f + 1] or 1 / fps
  end
end
-- теги после всех кадров, иначе newEmptyFrame растягивает уже созданные
for i, d in ipairs(dirs) do
  local first = (i - 1) * frames + 1
  local tag = spr:newTag(first, first + frames - 1)
  tag.name = anim .. "_" .. d
end

spr:saveAs(string.format("%s/%s/%s%s.aseprite", root, out, prefix, anim))
