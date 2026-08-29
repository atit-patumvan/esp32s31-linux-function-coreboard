# Reproducible Build on Linux or macOS

## Pinned inputs

Use these inputs unless a deliberate upgrade is being tested:

| Input | Pin |
|---|---|
| Public branch | `feature/function-coreboard-native-radio` |
| ESP-IDF | `a602e67b0bf9ee0806dc4e1df7afc9affedf5c33` |
| Linux toolchain release | `esp32s31-linux-gcc-15.2.0-5` |
| Container base | digest in `Dockerfile.reproducible` |
| Buildroot/Linux/OpenSBI/U-Boot | commits recorded by the superproject |

The project invokes `tools/apply_submodule_patches.sh` from `make prepare`.
Buildroot and Linux therefore appear modified after a build even when the
superproject is clean. Those changes must match the project-owned patch files;
do not commit the dirty submodule contents as new submodule revisions.

## Obtain a clean source tree

```sh
git clone --recurse-submodules \
  --branch feature/function-coreboard-native-radio \
  https://github.com/atit-patumvan/esp32s31-linux-function-coreboard.git
cd esp32s31-linux-function-coreboard
git submodule update --init --recursive
git rev-parse HEAD
git submodule status
```

For the most reproducible rebuild, use a new clone instead of reusing an old
tree containing unknown generated files.

## Native Ubuntu 24.04 build

Install host packages:

```sh
sudo apt-get update
sudo apt-get install -y \
  bc bison build-essential ca-certificates ccache cpio curl \
  device-tree-compiler file flex git gperf libffi-dev libncurses-dev \
  libssl-dev mtd-utils ninja-build python3 python3-pip \
  python3-pkg-resources python3-pyelftools python3-venv rsync \
  swig unzip wget xz-utils
```

Install the pinned ESP-IDF in a dedicated directory:

```sh
S31_IDF_DIR="$PWD/../esp-idf-s31-a602e67"
git clone --filter=blob:none https://github.com/espressif/esp-idf.git \
  "$S31_IDF_DIR"
git -C "$S31_IDF_DIR" checkout \
  a602e67b0bf9ee0806dc4e1df7afc9affedf5c33
"$S31_IDF_DIR/install.sh" esp32s31
source "$S31_IDF_DIR/export.sh"
```

Build all standard images with the pinned Linux toolchain release:

```sh
make TOOLCHAIN_RELEASE_TAG=esp32s31-linux-gcc-15.2.0-5 \
  IDF_EXPORT="$S31_IDF_DIR/export.sh" all
```

## Apple silicon macOS build

The downloaded Linux cross compiler is an x86-64 Linux binary. Do not run it
directly on macOS, and do not mix it into an ARM64 Linux container. The simple,
portable path is Docker Desktop running the complete pinned build container as
`linux/amd64`.

From the repository root:

```sh
docker build --platform linux/amd64 \
  -f Dockerfile.reproducible -t esp32s31-linux-build .
```

Build in the bind-mounted source tree:

```sh
docker run --rm --platform linux/amd64 \
  --entrypoint /bin/bash \
  -v "$PWD:/src" -w /src \
  esp32s31-linux-build -lc '
    git config --global --add safe.directory /src
    git submodule update --init --recursive
    source "$IDF_PATH/export.sh"
    make TOOLCHAIN_RELEASE_TAG=esp32s31-linux-gcc-15.2.0-5 \
      IDF_EXPORT="$IDF_PATH/export.sh" all
  '
```

Docker Desktop must have enough disk space for ESP-IDF, the downloaded
toolchain, Linux, and Buildroot outputs. The emulated amd64 build is slower than
native Linux but keeps all compiler and host-tool architectures consistent.

Flashing is normally easier from macOS itself after the container exits; the
artifacts remain under the bind-mounted `build/` directory.

## Build variants

The recommended interface for selecting variants is the
[feature build selector](feature-build-selector.md):

```sh
./tools/s31-build
```

The direct Make commands below remain useful for automation and diagnosis.

The normal image enables Wi-Fi and the experimental BLE HCI driver:

```sh
make TOOLCHAIN_RELEASE_TAG=esp32s31-linux-gcc-15.2.0-5 \
  IDF_EXPORT="$S31_IDF_DIR/export.sh" all
```

For Wi-Fi-only radio diagnosis:

```sh
make -C radio_firmware clean
make clean
make S31_WIFI_ONLY=1 \
  TOOLCHAIN_RELEASE_TAG=esp32s31-linux-gcc-15.2.0-5 \
  IDF_EXPORT="$S31_IDF_DIR/export.sh" all
```

For experimental USB mass storage:

```sh
make clean
make S31_USB_STORAGE=1 \
  TOOLCHAIN_RELEASE_TAG=esp32s31-linux-gcc-15.2.0-5 \
  IDF_EXPORT="$S31_IDF_DIR/export.sh" all
```

Clean before changing variants so a radio object or kernel configuration from
the previous variant cannot be reused accidentally.

## Expected outputs

```text
build/spl_app.bin
build/u-boot.itb
build/esp32s31_generic.dtb
build/xipImage
build/rootfs.sqfs
build/s31_full_flash.bin
```

Validate before flashing:

```sh
make layout-check
test -s build/spl_app.bin
test -s build/u-boot.itb
test -s build/esp32s31_generic.dtb
test -s build/xipImage
test -s build/rootfs.sqfs
test "$(wc -c < build/rootfs.sqfs | tr -d ' ')" -le 4194304
sha256sum build/spl_app.bin build/u-boot.itb \
  build/esp32s31_generic.dtb build/xipImage build/rootfs.sqfs
```

On macOS, replace `sha256sum` with `shasum -a 256`.

## Build failures worth recognizing

- `ESP-IDF export.sh not found`: pass the exact `IDF_EXPORT=.../export.sh`.
- Missing ILP32F picolibc: run the pinned ESP-IDF `install.sh esp32s31`; a
  generic RISC-V toolchain is insufficient for the radio payload.
- `Exec format error`: an x86-64 Linux compiler is being run on the wrong host
  architecture. Use native x86-64 Linux or the full amd64 Docker workflow.
- Rootfs over 4 MiB: do not flash it; follow the rootfs size guide.
- Submodule patch cannot apply: verify the recorded submodule commits. Do not
  force the patch onto a different upstream revision.
- Transient compiler crashes under mixed ARM/x86 emulation: discard that mixed
  environment and use the complete `linux/amd64` container.
