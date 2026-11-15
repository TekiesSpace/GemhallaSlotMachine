# Notice

Gemhalla is an original game. It uses common slot mechanics (Hold & Spin, free games, progressive jackpots) and no names, art or audio from any commercial slot machine. It is for entertainment with play money only.

## Third-party art (CC0)

**Rotating Jewels** by **KillGorack**

- Source: https://opengameart.org/content/rotating-jewels
- License: CC0 1.0, a public domain dedication: https://creativecommons.org/publicdomain/zero/1.0/
- Used: the diamond, ruby, emerald and sapphire rotation frames, plus the topaz pear recolored to teal for the Rune Gem, copied from `gemstones_256.png` into `assets/gems/gems_256.png` (one row per gem, 16 frames each) by `tools/build_gem_sheet.gd`. Attribution isn't required; it's given here with thanks.

## Covered by LICENSE (public domain)

Everything else in this repository is new work, dedicated to the public domain under the Unlicense (`LICENSE`). No credit is asked for. That includes:

- the Vault's amethyst and diamond necklace and the Wild's platinum and diamond tiara, modeled and rendered in 3D in Godot (`tools/build_necklace.gd` and `tools/build_tiara.gd`, sharing `tools/render_kit.gd`, into `assets/gems/necklace_256.png` and `tiara_256.png`);
- the rune on the Rune Gem, the card ranks, the backdrop, the icons and the interface, drawn in code (`scripts/ui/symbol_tile.gd`, `scripts/ui/background.gd`, `tools/make_icons.gd`);
- all sound effects, synthesized in code at startup (`scripts/audio/`);
- the game, the math model, the server, the tools, the screenshots and the documentation.

## Godot Engine (MIT) in the built game

The source in this repository doesn't include Godot, but every exported game does: the browser build (GitHub Pages, the Release zips, the container image) contains the Godot Engine and the third-party libraries built into it.

- Godot Engine 4.7.2, https://godotengine.org. Copyright (c) 2014-present Godot Engine contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur. MIT License: [`licenses/godot/LICENSE.txt`](licenses/godot/LICENSE.txt).
- The engine's third-party components (such as FreeType, HarfBuzz, ICU, mbedTLS, zlib and the engine's default font) and their licenses: [`licenses/godot/COPYRIGHT.txt`](licenses/godot/COPYRIGHT.txt), Godot's own list for this version.

Both files are copied into every browser build, as `GODOT-LICENSE.txt` and `GODOT-COPYRIGHT.txt`, next to this notice. They aren't covered by this repository's LICENSE.

## Other tools

.NET, ASP.NET Core and the container base images the server builds on belong to their owners and come under their own licenses (MIT for .NET and ASP.NET Core). None of them is included in this repository.
