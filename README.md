<div align="center">
![Banner](banner.svg)
![Version](https://img.shields.io/github/v/release/Aoutnheub/mangadex-dl?style=for-the-badge&label=Version)
![License](https://img.shields.io/github/license/Aoutnheub/mangadex-dl?style=for-the-badge&label=License)

CLI utility for browsing and downloading from Mangadex
</div>

### Build from source

Requires zig version 0.11.0-dev.3950+a75531073 or later

```sh
zig build -Doptimize=ReleaseSafe
```

### Usage

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
- Read chapter (with feh) without downloading
    ```sh
    mangadex-dl -l <CHAPTER_LINK> > /tmp/links.txt && feh -Z --scale-down -f /tmp/links.txt
    ```
