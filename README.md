# skills

Godot 4.7 project (Forward+ renderer, Jolt Physics, D3D12 on Windows).

## Structure

- `skills/harpoon/` — harpoon skill: scene (`harpoon.tscn`) and meshes/textures for the grappling claw
- `skills/scanner/` — сканер із гри: тестова сцена (`scanner_test.tscn`) з купою уламків, кораблем ZR4, дроном-розвідником і анімацією скану
  - `vfx/` — `scan_pass.gd` + `scan_pass.gdshader`: смуга, що повзе по моделі знизу вгору (накладка в `material_overlay`)
  - `debris/` — купа уламків «ПЛИТА» (`debris_slab.tscn`, 38 шматків GSX) і `scan_site.gd`, такт скану як у `wreck_site.gd`
  - `ship/` — корабель ZR4 (корпус + три сопла на `jet.gdshader`)
  - `drone/` — дрон LRR5 (пак ReconnaissanceDroneLRR5, текстури зменшено до 2048/1024): злітає від корабля, кружляє над купою й веде на смугу сканера віяло променя (`scan_beam.gdshader`), потім вертається
  - `fx/scan_fx.gd` — спалах і іскри наприкінці скану, `audio/scan_loop.mp3` — гудіння сканера
  - Керування: Space / E — дрон на скан, S — скан без дрона (як у грі), A — автоскан, ЛКМ — крутити камеру, колесо — зум
- `project.godot` — engine configuration (main scene: `scanner_test.tscn`)
- `icon.svg` — project icon

## Requirements

- Godot 4.7 or newer

## Getting started

Open the project folder in Godot, or run it from the command line:

```bash
godot --path .
```
