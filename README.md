CLI utility for browsing / downloading from mangadex

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
