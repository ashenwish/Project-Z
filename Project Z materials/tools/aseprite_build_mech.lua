-- Мех и эффекты: кадры, теги и длительности берём из JSON задания.
local job = json.decode(io.open(app.params["job"], "r"):read("*a"))
local spr = Sprite(job.width, job.height, ColorMode.RGB)
spr:setPalette(Palette{ fromFile = job.palette })
spr.layers[1].name = job.layer
local n = 0
for _, row in ipairs(job.rows) do
  for i, path in ipairs(row.files) do
    n = n + 1
    if n > 1 then spr:newEmptyFrame() end
    spr:newCel(spr.layers[1], n, Image{ fromFile = path }, Point(0, 0))
    spr.frames[n].duration = job.durations_ms[i] / 1000
  end
end
local first = 1
for _, row in ipairs(job.rows) do
  spr:newTag(first, first + #row.files - 1).name = row.tag
  first = first + #row.files
end
spr:saveAs(job.output)
