# NuttX XIPFS + FDPIC module SDK

Loadable modules for NuttX whose **code is executed in place, directly out
of flash, and never copied into RAM**. Two instances of a module cost two
copies of its data and one copy of its code. Shared libraries work, and so
does C++ with global constructors.

This is the entry point for the whole feature. It covers the three pieces
that make it work, how to build the firmware, how to run the examples, and
how to write your own modules and libraries.

---

## Contents

- [How it works](#how-it-works)
- [The pieces](#the-pieces)
- [Getting the sources](#getting-the-sources)
- [The toolchain](#the-toolchain)
- [Building the firmware](#building-the-firmware)
- [Running the examples](#running-the-examples)
- [Writing a module](#writing-a-module)
- [Shared libraries](#shared-libraries)
- [C++ modules](#c-modules)
- [Why the build verifies itself](#why-the-build-verifies-itself)
- [Reference](#reference)
- [Limits](#limits)

---

## How it works

### The problem

On a microcontroller with no MMU, loading a program normally means copying
all of it into RAM. On an RP2350 you have 512 KB of RAM and 16 MB of flash,
and the flash is memory mapped and executable — the firmware itself already
runs from it. Copying a module into RAM to run it wastes the scarcest
resource to avoid using the most plentiful one.

The obstacle is that ordinary position-independent code assumes code and
data sit at a fixed offset from each other, so they have to move together.
If the code stays in flash, the data has to stay in flash too — and data has
to be writable.

### FDPIC

FDPIC breaks that assumption. A module has two loadable segments that can be
placed **completely independently**:

```
   flash (executed in place)              RAM (one copy per instance)
  ┌────────────────────────────┐         ┌────────────────────────────┐
  │ .text  .rodata             │         │ .data  .bss  .got          │
  │ read-only segment          │         │ writable segment           │
  │ mapped, never copied       │         │ copied at load             │
  └────────────────────────────┘         └────────────────────────────┘
```

Because the two are unrelated at run time, a function's address is no longer
enough to call it — the callee also needs to know where *its* data is. FDPIC
therefore represents a function pointer as a **descriptor**: a pair of words
holding the entry point and the data base.

```c
struct fdpic_desc_s
{
  uintptr_t entry;   /* where the code is  */
  uintptr_t got;     /* where its data is  */
};
```

Calling through a descriptor loads the data base into a reserved register
(**r9** on ARM) and branches. Building those descriptors is most of what the
loader does.

That reserved register is a whole-system property, not a module one. The
base firmware must be compiled with r9 reserved, because a firmware routine
that calls *back* into module code — `qsort()` with a comparison function in
the module is the standard case — has to arrive there with the module's data
base intact.

### What happens at load time

1. The read-only segment is **mapped** — the filesystem hands back a real
   flash address, and the module's text is never in RAM.
2. The writable segment is **copied** into RAM, once per running instance.
3. `DT_NEEDED` is walked, and any shared libraries are loaded the same way.
4. Relocations are applied: descriptors are filled in, imports are resolved
   against the symbol table the firmware exports.
5. `DT_INIT_ARRAY` runs — C++ global constructors, libraries before the
   modules that need them.
6. The module is entered.

On unload, `DT_FINI_ARRAY` runs, and the pin on the flash extent is dropped
so a compacting filesystem may move those blocks again.

### Why a special filesystem

Executing in place needs a file whose bytes are **physically contiguous and
directly addressable**. A normal filesystem scatters a file across blocks
and gives you no address at all. XIPFS stores each file as one contiguous,
erase-block-aligned extent, answers `BIOC_XIPBASE`, and hands out a real
flash pointer through `mmap`. It also keeps a pin refcount, so it will not
relocate code that is currently executing.

---

## The pieces

| Piece | Where | What it does |
|---|---|---|
| MTD driver | `arch/arm/src/rp23xx/rp23xx_flash_mtd.c` | The unused tail of the QSPI flash as an MTD device that answers `BIOC_XIPBASE` |
| XIPFS | `fs/xipfs/` | Contiguous-extent filesystem, `mmap` to a flash pointer, pin refcounting, power-safe metadata, manual defrag |
| FDPIC loader | `binfmt/fdpic.c` | Maps text in place, copies data per instance, resolves relocations, runs constructors |
| This SDK | here | Builds modules out of tree |

In-tree documentation, on the fork:

- [`Documentation/components/fdpic.rst`](https://github.com/casaroli/nuttx/blob/xipfs-fdpic/Documentation/components/fdpic.rst)
  — the loader: design, relocation types, dynamic tags, link flags, C++
- [`Documentation/components/filesystem/xipfs.rst`](https://github.com/casaroli/nuttx/blob/xipfs-fdpic/Documentation/components/filesystem/xipfs.rst)
  — the filesystem: extents, `mmap` semantics, pins, defragmentation

---

## Getting the sources

The feature lives on the `xipfs-fdpic` branch of two forks. Both are
needed, and they must be checked out side by side.

```sh
mkdir nuttx-elf && cd nuttx-elf

git clone -b xipfs-fdpic https://github.com/casaroli/nuttx.git nuttx
git clone -b xipfs-fdpic https://github.com/casaroli/nuttx-apps.git apps

git clone https://github.com/casaroli/nuttx-sdk.git sdk
```

- **NuttX fork:** <https://github.com/casaroli/nuttx> — branch `xipfs-fdpic`
- **Apps fork:** <https://github.com/casaroli/nuttx-apps> — branch `xipfs-fdpic`
- **This SDK:** <https://github.com/casaroli/nuttx-sdk>

The directory names matter: NuttX expects the apps tree as a sibling called
`apps`.

---

## The toolchain

Two toolchains are involved, and the split is the trick that keeps this
cheap.

**The stock Arm bare-metal toolchain does all the compiling.**
`arm-none-eabi-gcc` and `arm-none-eabi-g++` emit perfectly good FDPIC
objects for both C and C++.

**`arm-uclinuxfdpiceabi` binutils does the linking**, and that is the only
thing you cannot get off the shelf. `arm-none-eabi-ld` is configured with
the `armelf` emulation alone:

```console
$ arm-none-eabi-ld -V | head -3
GNU ld (Arm GNU Toolchain 15.2.Rel1) 2.45.1
  Supported emulations:
   armelf
```

It cannot produce an FDPIC object. It does not fail either — it marks the
output `UNIX - System V` and the loader refuses it at run time. The FDPIC
linker is the one that carries `armelf_linux_fdpiceabi`.

So the from-source dependency is **binutils alone**. No FDPIC GCC.

### 1. The bare-metal compiler

```sh
# macOS
brew install --cask gcc-arm-embedded

# Debian / Ubuntu
sudo apt install gcc-arm-none-eabi g++-arm-none-eabi

# or the official Arm builds, any host:
#   https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads
```

> **macOS caveat.** The Homebrew *formula* `arm-none-eabi-gcc` (as opposed to
> the `gcc-arm-embedded` cask) is built without newlib — it has no `math.h`
> and cannot link. If it is first on your `PATH` you will get baffling
> failures. Check with `which arm-none-eabi-gcc` before believing one.

### 2. FDPIC binutils

**Is there a prebuilt binary?** Short answer: **no, not a usable one, on any
host.** This was checked rather than assumed:

| Source | Status |
|---|---|
| Arm GNU Toolchain | `armelf` only — no FDPIC emulation |
| [Bootlin toolchains](https://toolchains.bootlin.com/) | The `armv7m` builds are the **bFLT / elf2flt** path (`arm-buildroot-uclinux-uclibceabi`), not FDPIC |
| Debian / Ubuntu / Homebrew | No `arm-uclinuxfdpiceabi` package |
| [mickael-guene/fdpic_manifest](https://github.com/mickael-guene/fdpic_manifest) | The only prebuilt FDPIC toolset ever published. Ubuntu 14.04 only, binutils 2.22, last updated 2016 — far too old |
| crosstool-NG, Buildroot | Can produce one, but they build it from source too |

Building it yourself is not the burden that implies, because it is binutils
only:

```sh
sdk/toolchain/build-binutils.sh ~/fdpic
export PATH=~/fdpic/toolchain/bin:$PATH
```

**About a minute, about 23 MB, on an ordinary filesystem.** Verify:

```console
$ arm-uclinuxfdpiceabi-ld -V | head -6
GNU ld (GNU Binutils) 2.43
  Supported emulations:
   armelf_linux_eabi
   armelfb_linux_eabi
   armelf_linux_fdpiceabi     <- the one that matters
   armelfb_linux_fdpiceabi
```

Host notes:

- **macOS (Apple silicon)** — verified; 60 s. No case-sensitive volume is
  needed for binutils.
- **Linux x86_64 / arm64** — expected to work; standard autotools build with
  no host-specific patches. Not verified here.
- **Windows** — build under WSL2 or MSYS2 and use the resulting Linux-hosted
  binaries. A native MinGW build is not something this project has tried.

You need `curl`, `tar`, `make` and a host C compiler. That is all.

### Optional: a full FDPIC GCC

`sdk/toolchain/build-toolchain.sh` also builds an FDPIC **C** compiler.
Nothing here needs it — it takes about half an hour, and on macOS it must be
built on a case-sensitive volume because GCC will not build otherwise. It is
kept for people who want an FDPIC C compiler in its own right. It has no C++
compiler (`--enable-languages=c`), which is why C++ is compiled with
`arm-none-eabi-g++` regardless.

---

## Building the firmware

Verified on a **Pimoroni Pico Plus 2** (RP2350, Cortex-M33). Also runs on
QEMU `mps2-an521`.

You need `kconfiglib` (Kconfig frontends are no longer packaged in most
places) and `genromfs`:

```sh
python3 -m venv .venv
.venv/bin/pip install kconfiglib
export PATH=$PWD/.venv/bin:$PATH
```

Then:

```sh
cd nuttx
make distclean && ./tools/configure.sh pimoroni-pico-2-plus:nsh

for o in CONFIG_MTD CONFIG_RP23XX_FLASH_MTD CONFIG_FS_XIPFS CONFIG_FDPIC \
         CONFIG_LIBC_EXECFUNCS CONFIG_EXECFUNCS_HAVE_SYMTAB \
         CONFIG_EXECFUNCS_SYSTEM_SYMTAB CONFIG_TESTING_FS_XIPFS \
         CONFIG_FS_XIPFS_FAULT_INJECT CONFIG_EXAMPLES_NXFLATXIP \
         CONFIG_LIBM_TOOLCHAIN; do
    kconfig-tweak --file .config --enable $o
done
kconfig-tweak --file .config --set-str CONFIG_TESTING_FS_XIPFS_MTD "/dev/rpflash"
kconfig-tweak --file .config --set-val CONFIG_INIT_STACKSIZE 16384

make olddefconfig && make -j8
```

Flash it:

```sh
probe-rs download --chip RP235x nuttx
probe-rs reset --chip RP235x
```

Console is UART at 115200 on GP0/GP1.

What the options are for:

| Option | Why |
|---|---|
| `CONFIG_FS_XIPFS` | The filesystem |
| `CONFIG_RP23XX_FLASH_MTD` | MTD over the unused tail of QSPI flash |
| `CONFIG_FDPIC` | The loader — **also reserves r9 across the whole firmware** |
| `CONFIG_EXECFUNCS_SYSTEM_SYMTAB` | The export list modules import from |
| `CONFIG_FS_XIPFS_FAULT_INJECT` | Power-loss injection, used by the test suite |

---

## Running the examples

The firmware embeds the prebuilt modules, so there is nothing to copy onto
the board. Over the console:

```
xipfs_test              the full suite -- 82 tests, several minutes
xipfs_test fdpic        just the module loading tests, ~20 s

nxflatxip               a module, two concurrent instances
nxflatxip solib         a shared library across two instances
nxflatxip cxx           the same in C++, checking global constructors ran
nxflatxip jmprel        a module whose imports are all in DT_JMPREL
nxflatxip defrag        fragment the filesystem, compact it, with a block map
nxflatxip bench         XIP read throughput before and after a flash write
```

`xipfs_test fdpic` is the quick confidence check that the loader is intact:

```
-- FDPIC modules --
  PASS  descriptors manufactured by the loader are callable
  PASS  a module bound entirely through DT_JMPREL runs
  PASS  a module without the FDPIC marker is refused
  PASS  a leaf library with no DT_PLTGOT reaches its own data
  PASS  one flash copy of the library, pinned once per instance
  PASS  the module's own global constructor ran
  PASS  the library's global constructor ran
  PASS  the library was constructed before the module needing it
  PASS  each instance has its own copy of the library's data
  PASS  destructors ran on unload, each with its instance's own state
  PASS  the library's pins return to zero once both instances are gone
```

These assert on properties that otherwise fail *silently* — a loader that
skips `DT_INIT_ARRAY` runs a C++ module perfectly happily with every global
left as zero. They have been checked against deliberate one-line breakages
of the loader, and each one fails when the thing it names is broken.

> **A run that stops without printing its summary is a failure, not a
> hang.** Two of these tests call into a module whose relocations must be
> right; if they are not, the module branches to an unrelocated address and
> the resulting HardFault takes the whole system down mid-test. That is
> inherent — on Cortex-M a HardFault is system-wide, not per-task — so those
> regressions show up as a dead console rather than a `FAIL` line.

---

## Writing a module

A module is a normal C program. It links against nothing: `printf`,
`qsort` and everything else are imported from the firmware's export list at
load time.

`hello.c`:

```c
#include <stdio.h>

int main(int argc, char *argv[])
{
  printf("hello from flash\n");
  return 0;
}
```

`Makefile`:

```make
MODULE = hello
SRCS   = hello.c

include /path/to/sdk/nuttx-fdpic.mk
```

```console
$ make NUTTX_DIR=/path/to/nuttx
  CC   hello.c
  LD   hello.fdpic
OK    hello.fdpic: FDPIC, entry 0x1dd, 1 imports resolved
```

Copy `hello.fdpic` onto the target's XIPFS mount and run it by path, with
`posix_spawn`, `exec`, or from NSH.

CMake works too:

```sh
cmake -DCMAKE_TOOLCHAIN_FILE=/path/to/sdk/cmake/nuttx-fdpic.cmake \
      -DNUTTX_DIR=/path/to/nuttx ..
```

```cmake
include(${NUTTX_FDPIC_SDK}/cmake/nuttx-fdpic.cmake)
nuttx_fdpic_module(hello hello.c)
```

### Two things worth knowing

**Callbacks into your code work — but only through entry points that were
taught to expect them.**

In FDPIC a function pointer is the address of a two-word *descriptor* living
in your module's writable segment, not a code address. Firmware that stores
one and later branches to it therefore jumps into RAM data. Each entry point
has to resolve the descriptor first, and that is done by hand, per function.

Safe to hand a module function to:

`qsort` · `bsearch` · `pthread_create` · `signal` · `task_create`

**Not safe** — these will fault the board:

`sigaction` · `pthread_once` · `task_spawn` · `scandir` · `mq_notify`

There is no diagnostic. The module loads, runs, and dies the moment the
firmware branches to the descriptor — a HardFault with a dead console. If
you need one of the unsupported ones, add `fdpic_callback()` at that entry
point in the firmware; see `libs/libc/signal/sig_signal.c` for the pattern,
including why the `SIG_*` sentinels have to be excluded by hand.

This all also requires the firmware to reserve r9, which `CONFIG_FDPIC=y`
arranges centrally. If callbacks misbehave, check that first.

**Each instance gets its own data.** Two concurrent instances have separate
globals while sharing one copy of the code in flash. `examples/qsorter`
demonstrates both: it fills an array, sleeps so the instances overlap, then
sorts — so shared data would show up as corruption rather than passing by
luck.

Unlike NXFLAT, taking a pointer to a `static` function is fine.

---

## Shared libraries

A library is a module with a soname and no entry point. The consumer names
it on its own link line, and records it in `DT_NEEDED`.

```make
# the library
$(MAKE) -f nuttx-fdpic.mk MODULE=libcounter SRCS=libcounter.c ENTRY=0 \
        EXTRA_LDFLAGS="-soname libcounter.so"
mv libcounter.fdpic libcounter.so

# the module that uses it
$(MAKE) -f nuttx-fdpic.mk MODULE=user SRCS=user.c LIBS=libcounter.so
```

Put the library on the target at `CONFIG_FDPIC_LIBPATH` (default
`/mnt/xipfs`) under the name in the module's `DT_NEEDED`.

Each object gets its own GOT and its own writable data, so two modules using
one library see **independent library state while sharing one copy of its
code in flash**. `examples/shared` shows this: two instances bumping a
library counter by 1 and 2 end at 3 and 6, not 9 and 9.

`EXTRA_LDFLAGS` goes straight to `ld`, so it takes bare linker flags —
`-soname libfoo.so`, not `-Wl,-soname,libfoo.so`.

---

## C++ modules

Put C++ sources in `CXXSRCS` instead of `SRCS`:

```make
MODULE  = shapes
CXXSRCS = shapes.cpp

include /path/to/sdk/nuttx-fdpic.mk
```

Global constructors and destructors work. The loader runs `DT_INIT_ARRAY`
after relocations and before entering the module, and `DT_FINI_ARRAY` on
unload — per object, libraries before the modules that need them, and
destruction in the mirror order.

`examples/cxx` is a C++ shared library and a C++ module that check exactly
that.

Three flags are set for you and are **not optional**:

- **`-fno-use-cxa-atexit`.** By default GCC registers each static object's
  destructor with `__cxa_atexit(dtor, obj, &__dso_handle)`, and
  `__dso_handle` comes from `crtbegin`, which a module does not link. The
  link fails outright with ``hidden symbol `__dso_handle' isn't defined``.
  Turning it off also puts destructors in `.fini_array`, which is what the
  loader walks — so the flag that makes the link work is also the flag that
  makes destructors run.
- **`-fno-exceptions -fno-rtti`.** Both need `libsupc++`, which a module
  linking against nothing cannot reach.

Constructors run in the task that *called the loader*, not in the module's
own task, because the module's task does not exist yet. The loader installs
the object's data base in r9 around each call. The practical consequence is
that a constructor sees the loading task's identity.

> An ignored `DT_INIT_ARRAY` does not fail loudly. The module loads,
> resolves every symbol and runs — the globals are simply left as `.bss` and
> read back zero. Nothing faults and nothing is logged; the module just
> answers wrong. That is why `examples/cxx` checks a magic number that only
> a constructor writes, rather than printing a total and looking at it.

---

## Why the build verifies itself

A module links with `-shared`, so **undefined symbols are permitted**. A
call to a function the firmware does not export links perfectly cleanly and
fails only on the target — as a bare `-ENOENT` from the loader, with no
indication of which symbol was at fault. (`binfmt` reports every loader
error as `-ENOENT`, because at the dispatch layer "the loader refused it"
and "not my format" are the same answer.)

So every build is checked against the firmware's actual export list:

```console
  CC   bad.c
  LD   bad.fdpic
FAIL  imports the firmware does not export:
        this_symbol_does_not_exist
make: *** [verify] Error 1
```

To see what is available:

```sh
make exports NUTTX_DIR=/path/to/nuttx   # count
sdk/tools/nuttx-exports /path/to/nuttx  # the list
```

The list comes from `libs/libc/exec_symtab.c`, **run through the C
preprocessor**. That matters more than it sounds: NuttX generates that file
from CSVs and puts most entries behind `#if defined(CONFIG_...)`, so reading
it textually offers every symbol that *could* be exported rather than the
ones that were — on one ordinary configuration, 127 names that were not in
the firmware at all, `dlopen` and the socket calls among them. The guards
are resolved with the same compiler that built the tree, which is why a
configured **and built** tree is required.

---

## Reference

### What is here

```
nuttx-fdpic.mk                  make fragment -- include this
cmake/nuttx-fdpic.cmake         CMake toolchain file + nuttx_fdpic_module()
toolchain/build-binutils.sh     the linker, ~1 min          <- what you need
toolchain/build-toolchain.sh    binutils + an FDPIC GCC, ~30 min (optional)
tools/nuttx-exports             list the symbols the firmware exports
tools/fdpic-verify              check a module is FDPIC and its imports resolve
tools/fdpic-embed               turn a built module into a C header
examples/hello                  smallest possible module
examples/qsorter                callbacks and per-instance data
examples/shared                 a shared library and a module that uses it
examples/cxx                    the same in C++, with global constructors
examples/funcdesc               R_ARM_FUNCDESC -- descriptors the loader makes
examples/lazybind               imports in DT_JMPREL -- the awkward link
```

The last three exist to exercise loader paths that nothing else reaches.
They are also staged and asserted on by `apps/testing/fs/xipfs`, so a
regression in the loader fails the test suite rather than waiting to be
noticed on someone's board.

### Variables

| Variable | Default | Meaning |
|---|---|---|
| `NUTTX_DIR` | *required* | A configured, **built** NuttX tree |
| `MODULE` | `module` | Output is `$(MODULE).fdpic` |
| `SRCS` / `CXXSRCS` | | C and C++ sources |
| `LIBS` | | Shared libraries to link against |
| `ENTRY` | `main` | Entry symbol; `0` for a library |
| `CPU` | `cortex-m33` | `-mcpu=` |
| `OPT` | `-Os` | |
| `ARM_TOOLCHAIN` | `arm-none-eabi` | Compiler prefix |
| `FDPIC_TOOLCHAIN` | `arm-uclinuxfdpiceabi` | Binutils prefix |
| `EXTRA_CFLAGS` / `EXTRA_CXXFLAGS` / `EXTRA_LDFLAGS` | | Appended |

### Flags that are load bearing

If you ever drive the toolchain by hand rather than through the SDK:

```sh
arm-none-eabi-gcc -mcpu=cortex-m33 -mthumb -mfdpic -fPIC -Os -fno-builtin \
    -I$NUTTX/include -D__NuttX__ -c mod.c -o mod.o

arm-uclinuxfdpiceabi-ld -m armelf_linux_fdpiceabi -shared -z now \
    -e main -o mod.fdpic mod.o
```

- **`-fPIC`** — `-mfdpic` alone does not imply PIC on the bare-metal target.
  Without it the link emits `TEXTREL`, and text relocations cannot work when
  the text is executed from read-only flash.
- **`-shared`** — this is what preserves `R_ARM_FUNCDESC_VALUE` for imports.
  Linking as a PIE with `--unresolved-symbols=ignore-all` also appears to
  work, but silently degrades every import to `R_ARM_NONE`, and the module
  branches to zero on its first call out.
- **`-m armelf_linux_fdpiceabi`** — this `ld` supports four emulations and
  will not guess.
- **`-z now`** — keeps imported descriptors in `DT_REL` rather than the lazy
  table `DT_JMPREL`. The loader binds both, so this is no longer required
  for correctness; it is what the SDK does so that `examples/lazybind`,
  which omits it, stays a distinct case.

Checking a module by hand:

```sh
arm-uclinuxfdpiceabi-readelf -h mod.fdpic   # OS/ABI must be "ARM FDPIC"
arm-uclinuxfdpiceabi-readelf -d mod.fdpic   # NEEDED, INIT_ARRAY, REL/JMPREL
arm-uclinuxfdpiceabi-readelf -r mod.fdpic   # relocations
```

---

## Limits

- **Cortex-M3 and later only** (Thumb-2). Not M0/M0+/M23 — GCC rejects
  FDPIC in Thumb-1 mode.
- **Only the link needs the FDPIC toolchain.** The compiler does not.
- **Modules cannot export symbols to other modules.** They import, from the
  firmware and from libraries they name in `DT_NEEDED`.
- **Binding is eager.** Both `DT_REL` and `DT_JMPREL` are applied at load
  time; there is no lazy PLT binding. Nothing is lost by that — a module
  carries a handful of relocations — but it does mean `dlopen`/`dlsym`
  semantics are not available.
- **Repeated loads of one library duplicate the loader's bookkeeping.** The
  flash is still shared via the pin, but there is no object registry, which
  is what `dlopen` would need.
- **C++ exceptions and RTTI are unavailable**; a module links against
  nothing and cannot reach `libsupc++`.
- **RISC-V is out of scope.** The RISC-V FDPIC psABI is an unmerged RFC.
