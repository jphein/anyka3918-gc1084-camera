# Cross-compile toolkit

`anyka-env.sh` — source it to get the Anyka AK3918 cross-compiler on PATH.
`hello.c`      — smallest thing that proves the toolchain end to end.

Full instructions, the pinned toolchain version, the host-library trap, and how to
get a binary onto a camera: **[docs/cross-compiling.md](../../docs/cross-compiling.md)**.

The toolchain itself is NOT in this repo (45 MB of prebuilt binaries). The env
script tells you where to get it if it's missing.
