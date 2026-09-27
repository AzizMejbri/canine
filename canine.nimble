# canine.nimble
import std/strutils
import std/os

version       = "0.1.0"
author        = "Aziz Mejbri"
description   = "A small x86_64 kernel written in Nim"
license       = "MIT"
srcDir        = "."

const
  CC = "clang"
  LD = "x86_64-elf-ld"
  NIM = "nim"

  # Top-level kernel module. Change this if your entry point has a different name.
  ENTRY = "kernel.nim"

  CFLAGS    = "-m64 -ffreestanding -O2 -Wall -Wextra -I."
  NIM_FLAGS = "--os:standalone --noMain --noLinking --threads:off " &
              "--path:src " &
              "--cc:clang " &
              "--mm:none " &                # "--assertions:off " & 
              "--passC:-fno-stack-protector " &
              "--passC:-ffreestanding --passC:-m64 --passC:-O2 " &
              "--passC:-Wall --passC:-Wextra " &
              "--debugger:native " &        # tells Nim to pass -g to clang and keep Nim-level debug info
              "--lineDir:on "               # emits #line directives so GDB maps C lines back to .nim

  LINKER_FILE = "linker.ld"
  LDFLAGS     = "-m elf_x86_64 -T " & LINKER_FILE

  ISO_DIR   = "iso"
  OBJ_DIR   = "objects"
  NIM_CACHE = "nimcache"
  KERNEL    = "kernel.bin"
  ISO       = "canine.iso"

proc run(cmd: string) =
  echo "\e[32m$ ", cmd, "\e[m"
  let (output, code) = gorgeEx(cmd)
  if output.len > 0:
    echo output
    if not output.endsWith("\n"): echo ""
  if code != 0:
    echo "\e[31mFAILED (exit ", code, "): ", cmd, "\e[m"
    quit code

proc parentDirOf(p: string): string =
  let i = p.rfind('/')
  if i >= 0: p[0 ..< i] else: ""

proc needsRebuild(src, obj: string): bool =
  if not fileExists obj:
    return true
  # POSIX `test src -nt obj` exits 0 if src is newer than obj.
  let (_, code) = gorgeEx("test " & src & " -nt " & obj)
  return code == 0

proc compileObj(src, obj: string) =
  if not needsRebuild(src, obj):
    echo "\e[90m[skip] ", obj, "\e[m"
    return
  let dir = parentDirOf obj
  if dir.len > 0: mkDir dir
  run CC & " " & CFLAGS & " -c " & src & " -o " & obj

proc collectC(dir: string, objects: var seq[string]) =
  for f in listFiles dir:
    if f.endsWith ".c":
      if f.startsWith(NIM_CACHE & "/") or
         f.startsWith(OBJ_DIR & "/") or
         f.startsWith(ISO_DIR & "/"):
        continue
      let obj = OBJ_DIR & "/" & f & ".o"
      compileObj f, obj
      objects.add obj
  for d in listDirs dir:
    if d == NIM_CACHE or d == OBJ_DIR or d == ISO_DIR:
      continue
    collectC d, objects

proc collectAsm(dir: string, objects: var seq[string]) =
  for f in listFiles dir:
    if f.endsWith(".s") or f.endsWith ".S":
      if f.startsWith(NIM_CACHE & "/") or
         f.startsWith(OBJ_DIR & "/") or
         f.startsWith(ISO_DIR & "/"):
        continue
      let obj = OBJ_DIR & "/" & f & ".o"
      compileObj f, obj
      objects.add obj
  for d in listDirs dir:
    if d == NIM_CACHE or d == OBJ_DIR or d == ISO_DIR:
      continue
    collectAsm d, objects

proc doIso() =
  mkDir ISO_DIR & "/boot/grub"
  cpFile KERNEL, ISO_DIR & "/boot/" & KERNEL
  cpFile "grub.cfg", ISO_DIR & "/boot/grub/grub.cfg"
  run "grub-mkrescue -o " & ISO & " " & ISO_DIR

proc doBuild() =
  # Do NOT wipe nimcache — let Nim do incremental builds.
  mkDir OBJ_DIR
  mkDir NIM_CACHE

  echo "\e[36m[Nim] Compiling ", ENTRY, " ...\e[m"
  run NIM & " c " & NIM_FLAGS & " --nimcache:" & NIM_CACHE & " " & ENTRY

  var objects: seq[string] = @[]

  echo "\e[36m[CC] Collecting Nim-generated objects ...\e[m"
  for f in listFiles NIM_CACHE:
    if f.endsWith ".o":
      objects.add f

  echo "\e[36m[CC] Compiling project C sources ...\e[m"
  collectC ".", objects

  echo "\e[36m[AS] Compiling assembly sources ...\e[m"
  collectAsm ".", objects

  if objects.len == 0:
    echo "\e[31mNo object files to link.\e[m"
    quit 1

  # Relink only if any object is newer than the kernel.
  var needLink = not fileExists KERNEL
  if not needLink:
    for o in objects:
      if needsRebuild(o, KERNEL):
        needLink = true
        break

  if needLink:
    echo "\e[36m[LD] Linking ", KERNEL, " ...\e[m"
    run LD & " " & LDFLAGS & " -o " & KERNEL & " " & objects.join(" ")
  else:
    echo "\e[90m[LD] up to date, skipping link\e[m"

  # Only rebuild the ISO if the kernel changed.
  if not fileExists(ISO) or needsRebuild(KERNEL, ISO):
    echo "\e[34mChecking if kernel is Multiboot2 compliant...\e[m"
    let (_, exitCode) = gorgeEx "grub-file --is-x86-multiboot2 " & KERNEL
    if exitCode == 0:
      echo "\e[34mSUCCESS: Kernel is Multiboot2 compliant\e[m"
    else:
      echo "\e[31mERROR: Kernel is NOT Multiboot2 compliant\e[m"
      quit 1
  else:
    echo "\e[90m[ISO] up to date, skipping ISO rebuild\e[m"


task build, "Compile and link the kernel":
  doBuild()
  doIso()

task iso, "Create bootable ISO":
  doIso()

task emu, "Run the kernel in QEMU":
  doBuild()
  exec "qemu-system-x86_64 -cdrom " & ISO & " -serial stdio -no-reboot -d int,guest_errors"

task dbg, "Debug the kernel in QEMU using GDB":
  doBuild()
  exec "qemu-system-x86_64 -cdrom " & ISO & " -serial stdio -s -S -no-reboot -no-shutdown -d int,guest_errors -D qemu.log"

task wipe, "Remove build artifacts":
  echo "\e[36m[CLEAN] removing ", OBJ_DIR, ", ", NIM_CACHE, ", ", ISO_DIR, ", ", KERNEL, ", ", ISO, "\e[m"
  exec "rm -rf " & OBJ_DIR & " " & NIM_CACHE & " " & ISO_DIR & " " & KERNEL & " " & ISO

# task all, "Build the ISO":
#   doBuild()

task b, "Compile and link the kernel":
  doBuild()
  doIso()

task e, "Run the kernel in QEMU":
  doBuild()
  doIso()
  exec "qemu-system-x86_64 -cdrom " & ISO & " -serial stdio -no-reboot -d int,guest_errors"
