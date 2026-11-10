# Project Z

Пиксельный 2.5D gore-slasher на Godot 4.7.2: альтернативная Российская империя 1918 года, стимпанк и паровые мехи.

## Структура

- `project Z/z/` — игровой проект Godot, готовые ассеты и тесты.
- `Project Z materials/` — исходники арта, Blender/Aseprite, инструменты генерации и документация.

## Запуск

Открыть `project Z/z/project.godot` в Godot 4.7.2 и запустить проект (F6 — текущая сцена, F5 — проект). Основная сцена — `scenes/test_arena.tscn`.

WASD — движение, мышь — прицел, ЛКМ/ПКМ — атаки, Q — смена модуля, Alt — револьвер, R — перезарядка, Shift — рывок, Space — прыжок (дважды — двойной), Ctrl — ульта. F1 — подсказки, F2 — добавить меха, F10 — восстановить здоровье.

## Проверки

```powershell
godot --headless --path "project Z/z" --editor --import
godot --headless --path "project Z/z" -s res://tests/test_round18.gd
```

`tests/test_mech_live_mouse.gd` запускается с обычным рендером и проверяет полный путь стрельбы мышью. Исходники звуков и лицензии перечислены в `project Z/z/assets/audio/CREDITS.md` и `MECH_CREDITS.md`.

Кэши Godot, Python и локальные учётные данные в репозиторий не входят. Файлы `.uid` и `.import` сохраняются.
