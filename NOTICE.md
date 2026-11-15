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

Godot Engine, .NET and the other tools used to build Gemhalla belong to their owners and come under their own licenses; none of them is included in this repository.
