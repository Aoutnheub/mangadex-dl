<div align="center">

![Banner](banner.svg)

![Version](https://img.shields.io/github/v/release/Aoutnheub/mangadex-dl?style=for-the-badge&label=Version&color=lawngreen)
![License](https://img.shields.io/badge/License-MIT-darkturquoise?style=for-the-badge)

CLI utility for browsing and downloading from Mangadex

</div>

### :arrow_down: Download

From [Releases](https://github.com/Aoutnheub/mangadex-dl/releases)

### :wrench: Build from source

Requires zig version *0.11.0-dev.3950+a75531073* or later

```sh
git clone https://github.com/Aoutnheub/mangadex-dl
cd mangadex-dl
zig build -Doptimize=ReleaseSafe
```

Compiled executable can be found in `zig-out/bin`

### :question: Usage

```sh
mangadex-dl [OPTIONS] <ARGUMENTS>
```

Use `mangadex-dl -h` to see all options

#### Examples

- Download chapter
    ```sh
    mangadex-dl <CHAPTER_LINK>
    ```
- Search for manga
    ```sh
    mangadex-dl --search <TITLE>
    ```
