#!/usr/bin/env python3
"""Reset an S31 board and run bounded shell commands over its UART console."""

import argparse
import pathlib
import re
import sys
import time

import serial


def capture(port, log, seconds, stop=None):
    deadline = time.monotonic() + seconds
    data = bytearray()
    while time.monotonic() < deadline:
        chunk = port.read(4096)
        if chunk:
            data.extend(chunk)
            log.write(chunk)
            log.flush()
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            if stop and stop(data):
                return bytes(data), True
        else:
            time.sleep(0.01)
    return bytes(data), False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="/dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--log", required=True)
    parser.add_argument("--no-reset", action="store_true")
    parser.add_argument("--blind-login", action="store_true")
    parser.add_argument("--boot-timeout", type=float, default=90)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("command", nargs="*")
    args = parser.parse_args()

    path = pathlib.Path(args.log)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("ab", buffering=0) as log, serial.Serial(
        args.port, args.baud, timeout=0.03
    ) as port:
        log.write(("\n\n=== UART REGRESSION %s ===\n" %
                   time.strftime("%Y-%m-%d %H:%M:%S %z")).encode())
        port.reset_input_buffer()
        if not args.no_reset:
            port.dtr = False
            port.rts = True
            time.sleep(0.15)
            port.rts = False
        else:
            port.write(b"\r")

        if args.blind_login:
            capture(port, log, 1)
            port.write(b"root\r")
            capture(port, log, 1)
            found = True
            boot = b"~ #"
        else:
            boot, found = capture(port, log, args.boot_timeout,
                                  lambda b: b"login:" in b or b"~ #" in b)

        if not found:
            print("\nBOOT_TIMEOUT", file=sys.stderr)
            return 2
        if b"login:" in boot and b"~ #" not in boot:
            port.write(b"root\r")
            _, found = capture(port, log, 10, lambda b: b"~ #" in b)
            if not found:
                print("\nLOGIN_TIMEOUT", file=sys.stderr)
                return 3

        for index, command in enumerate(args.command):
            marker = "__S31_CMD_%02d_%08x__" % (index, index ^ 0x31C0DE)
            payload = "%s; rc=$?; echo %s:$rc\r" % (command, marker)
            port.write(payload.encode())
            output, found = capture(
                port, log, args.timeout,
                lambda b, m=marker.encode():
                    re.search(re.escape(m) + rb":[0-9]+", b) is not None,
            )
            if not found:
                log.write(("\n=== COMMAND TIMEOUT: %s ===\n" % command).encode())
                print("\nCOMMAND_TIMEOUT: %s" % command, file=sys.stderr)
                port.write(b"\x03")
                capture(port, log, 2)
                return 4
            match = re.search(re.escape(marker.encode()) + rb":([0-9]+)", output)
            if not match or match.group(1) != b"0":
                print("\nCOMMAND_FAILED: %s" % command, file=sys.stderr)
                return 5
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
