# SSH, Console Access, and Persistent Host Keys

## Access paths

- USB-UART is the recovery and first-boot console at 115200 baud.
- Dropbear provides inbound SSH after Ethernet or Wi-Fi obtains an address.
- The rootfs includes the Dropbear server, not the Dropbear SSH client.

On macOS:

```sh
screen /dev/cu.usbserial-110 115200
```

Exit `screen` with `Ctrl-A`, `K`, `Y`.

## Login authorization

The public login key baked into an image comes from:

```text
buildroot-external/board/esp32-s31/overlay/root/.ssh/authorized_keys
```

Before building on another computer, replace or append the intended public
key. Never copy a private key into the repository or target rootfs.

Recommended host-side creation:

```sh
ssh-keygen -t ed25519 -f ./esp32s31_admin_ed25519 \
  -C 'esp32s31-admin'
```

Copy only `esp32s31_admin_ed25519.pub` into `authorized_keys`. Keep the private
file outside the repository with mode 0600.

Connect after learning the DHCP address:

```sh
ssh -i ./esp32s31_admin_ed25519 root@BOARD_IP
```

## Why host keys require a special patch

Buildroot normally points `/etc/dropbear` at `/var/run/dropbear`. Its stock
startup script may replace that symlink on a writable root. On this board the
writable root is overlayfs backed by JFFS2; replacing a lower-layer symlink can
require a whiteout representation that this combination cannot provide.

The project patch
`patches/submodules/buildroot-persistent-dropbear.patch` preserves the lower
symlink and redirects `/var/run/dropbear` to `/persist/dropbear`:

```text
/etc/dropbear -> /var/run/dropbear -> /persist/dropbear
```

Dropbear starts with `-R`, generating missing RSA, ECDSA, and ED25519 host keys
on first boot. Because the final directory is on JFFS2, subsequent boots reuse
them.

## Verify target state

```sh
ps | grep '[d]ropbear'
readlink /etc/dropbear
readlink /var/run/dropbear
ls -ld /persist/dropbear
ls -l /persist/dropbear
```

The directory should be mode 0700 and private host-key files mode 0600.

## Verify fingerprint persistence

From the host before reset:

```sh
ssh-keyscan -T 5 -t ed25519 BOARD_IP 2>/dev/null | ssh-keygen -lf -
```

Record the fingerprint, reset the board, wait for networking, and run the same
command again. The fingerprint must match. A changed fingerprint after every
boot means Dropbear is still generating keys under volatile `/run`.

When intentionally replacing a board or resetting persist, remove the old host
entry from the host's `known_hosts` only after confirming why the identity
changed. Do not bypass a surprising warning with permanent
`StrictHostKeyChecking=no`.

## Updating authorized login keys after deployment

Because `/root` is persistent through overlayfs, this survives reset:

```sh
mkdir -p /root/.ssh
chmod 700 /root/.ssh
pico /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
sync
```

Keep the current working session open while testing a second SSH connection.
This prevents lockout if the new key was pasted incorrectly.

## Recovery from SSH failure

1. Use USB-UART; do not reflash first.
2. Confirm an address with `ip -brief addr` and route with `ip route`.
3. Confirm Dropbear is running and port 22 is listening.
4. Check `/root/.ssh/authorized_keys` permissions and contents locally.
5. Check both Dropbear symlinks and `/persist/dropbear` permissions.
6. Restart Dropbear with its init script only after preserving the console.
7. Reflash rootfs only if the server binary/startup files are damaged; this
   preserves overlay data and keys.

## Security boundaries

- Wi-Fi Base64 values are plaintext-equivalent secrets.
- Raw persist backups contain host private keys and possibly authorized keys.
- The root account is the administration boundary; expose port 22 only on
  trusted networks unless firewalling and key lifecycle are deliberately
  designed.
- Rotate the baked authorized key before distributing public images intended
  for different owners.
