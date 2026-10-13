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
- `skills/explosions/` — вибухи з гри: тестова сцена (`explosions_test.tscn`) з полем брил трьох тьєрів і космічних мін
  - `fx/booms.gd` — вибухи, як їх кидає `fx_director.gd` гри: брила — `vfx_air_explosion_01` у масштабі `radius × 0.42` плюс осколки її ж каменю; міна — `vfx_nuke_explosion_01` у масштабі 0.4; звуки `destroy` / `rock_break` / `death_model`
  - `vfx/binbun/` — потрібна частина паку Binbun Stylized Explosion FX (CC0): два ефекти, контролери й шейдери
  - `asteroid/` — модель звичайної брили з гри і `test_rock.gd`: брила тьєра 2-3 розколюється на два уламки тьєром менше (тріск каменю), тьєра 1 розсипається начисто
  - `mine/` — космічна міна (`space_mine.tscn` + `space_mine_skin.gd`): петля шипів, пульс неону; перед підривом червоніє і частішає
  - Керування: ЛКМ по брилі / міні — підірвати, 1 — випадкова брила, 2 — випадкова міна, A — автопідрив, R — нове поле, ЛКМ + рух — камера, колесо — зум. Порожній слот заповнюється знову за 4 с
- `project.godot` — engine configuration (main scene: `scanner_test.tscn`)
- `icon.svg` — project icon

## Requirements

- Godot 4.7 or newer

## Getting started

Open the project folder in Godot, or run it from the command line:

```bash
godot --path .
```
