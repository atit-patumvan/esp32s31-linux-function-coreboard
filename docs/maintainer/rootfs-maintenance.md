# Rootfs Packages, Size Budget, and Maintenance

## Fixed budget

The rootfs slot is exactly 4,194,304 bytes. `make rootfs` copies Buildroot's
SquashFS output to `build/rootfs.sqfs` and rejects an oversized image. Never
truncate an oversized filesystem and never expand it into `persist` without a
coordinated flash-map, DT, boot, packaging, and recovery migration.

Primary configuration:

```text
buildroot-external/configs/esp32s31_rootfs_defconfig
```

Board overlay and finalizer:

```text
buildroot-external/board/esp32-s31/overlay/
buildroot-external/board/esp32-s31/post-build.sh
```

## Included maintenance tools

- Dropbear SSH server
- iproute2 `ip`
- `iw`
- `ethtool` without pretty-register dumps
- iputils `tracepath` only
- GNU netcat `nc`
- curl/libcurl with mbedTLS
- CA certificate bundle
- tiny `nano` and `pico` alias
- compact project Wi-Fi/BLE/overlay/USB helpers

Large interpreters such as Python and Node.js are intentionally absent. The
future gateway should start as small C binaries or carefully bounded shell
logic.

## Curl and TLS profile

`buildroot-external/package/s31-build-tweaks/s31-build-tweaks.mk` is scoped to
this external tree. It keeps HTTP/HTTPS, IPv6, asynchronous DNS, TLS 1.2,
certificate verification, and common modern client algorithms while removing
unused protocols, server-side TLS, old ciphers, and optional APIs.

The CA bundle is:

```text
/etc/ssl/certs/ca-certificates.crt
```

`post-build.sh` retains the consolidated bundle and removes the duplicate
individual Mozilla certificate sources and hash links. It caches the bundle in
the Buildroot output so incremental finalization cannot replace it with an
empty file after those source files were removed.

Verify on target:

```sh
curl --version
wc -c /etc/ssl/certs/ca-certificates.crt
curl --fail --silent --show-error --output /dev/null \
  --write-out '%{http_code}\n' https://example.com/
```

The protocol list should contain only `http https`, and the request should
return 200 with certificate validation enabled.

## Nano/pico and terminfo

The editor uses a tiny nano configuration. `pico` is a wrapper that executes
`nano`.

On a case-insensitive macOS bind mount, ncurses may install terminfo under
hexadecimal directories such as `78/xterm`, while target ncurses searches
`x/xterm`. The finalizer creates compatibility symlinks without duplicating the
database. `/etc/profile` also maps `xterm-256color` to the included `xterm`
entry.

Verify:

```sh
ls -l /usr/share/terminfo/x/xterm
TERM=xterm-256color pico /tmp/editor-test
```

Use `Ctrl-X` to exit and `Ctrl-O`, Enter to save.

## Adding a package safely

1. Enable the smallest relevant Buildroot option in
   `esp32s31_rootfs_defconfig`.
2. Disable unused subfeatures explicitly so future Buildroot defaults do not
   grow the image silently.
3. Put S31-only package hooks in the external tree, not as unpublished edits to
   the Buildroot submodule.
4. Use `make buildroot-clean` after changing package selection or toolchain
   capability.
5. Rebuild rootfs and record its exact byte size and SHA-256.
6. Inspect the target tree and SquashFS contents for duplicate data.
7. Test the real command on hardware, including network/TLS/terminal behavior.
8. Hardware-reset and repeat the persistence and SSH fingerprint checks.

Useful host checks:

```sh
wc -c build/rootfs.sqfs
du -ah build/buildroot/target | sort -h | tail -n 40
unsquashfs -s build/rootfs.sqfs
unsquashfs -ll build/rootfs.sqfs | less
```

## Recovering size

Prefer, in order:

1. Remove packages not needed by the appliance.
2. Disable optional features/protocols in large libraries.
3. Remove duplicate generated data after confirming a compact equivalent.
4. Use tiny configurations such as nano-tiny.
5. Keep logs, caches, and runtime databases out of the immutable image.

Do not remove CA validation, SSH key persistence, recovery commands, or basic
network diagnosis merely to gain a few kilobytes. Those features are part of
the maintainable gateway baseline.

## Incremental-build caution

Buildroot does not always uninstall files that an older local package version
used to install. `post-build.sh` explicitly removes retired hosted/audio tools
for this reason. When package contents shrink or configuration changes
substantially, use `make buildroot-clean` before trusting the final size.
