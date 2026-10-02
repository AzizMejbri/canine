import kstd/[hooks, option, string]
import drivers/output/serial
import globals
import arch/x86_64/debug

var grub2Magic    {.importc: "grub2_magic"   .}: uint32
var grub2InfoPtr* {.importc: "grub2_info_ptr".}: uint32

const Mb2BootloaderMagic = 0x36D76289'u32

initAppend:
  doAssert grub2Magic == Mb2BootloaderMagic,
    "GRUB's MB2 Bootloader Magic was corrupt!!"

type
  Mb2TagKind* {.pure, size: 2.} = enum
    End            = 0
    Cmdline        = 1
    BootLoaderName = 2
    Module         = 3
    BasicMemInfo   = 4
    Bootdev        = 5
    Mmap           = 6
    Framebuffer    = 8

  Mb2MemKind* {.pure, size: 4.} = enum
    Available = 1
    Reserved  = 2
    Acpi      = 3
    Nvs       = 4
    Bad       = 5

  Mb2Info* {.packed.} = object
    totalSize*: uint32
    reserved*:  uint32

  Mb2Tag* {.packed.} = object
    kind*:  Mb2TagKind
    flags*: uint16
    size*:  uint32

  Mb2MmapTag* {.packed.} = object
    kind*:         Mb2TagKind
    flags*:        uint16
    size*:         uint32
    entrySize*:    uint32
    entryVersion*: uint32

  Mb2MmapEntry* {.packed.} = object
    base*:     uint64
    length*:   uint64
    kind*:     Mb2MemKind
    reserved*: uint32

  Mb2StrTag* {.packed.} = object
    kind*:  Mb2TagKind
    flags*: uint16
    size*:  uint32
    # NUL-terminated string follows at offset 8

  MemRegion* = object
    base*:   uint64
    length*: uint64
    kind*:   Mb2MemKind

  Mb2TagView* = object
    ## Tagged-union view onto a Multiboot2 tag. The `raw` pointer
    ## always points at the tag in place; branch-specific pointers
    ## alias into it.
    case kind*: Mb2TagKind
    of Mmap:
      mmap*: ptr Mb2MmapTag
    of Cmdline, BootLoaderName:
      str*: ptr Mb2StrTag
    else:
      raw*: ptr Mb2Tag

static:
  doAssert sizeof(Mb2TagKind) == 2, "Mb2TagKind must be 2 bytes"
  doAssert sizeof(Mb2MemKind) == 4, "Mb2MemKind must be 4 bytes"
  doAssert sizeof(Mb2Tag) == 8,     "Mb2Tag must be 8 bytes"
  doAssert sizeof(Mb2MmapTag) == 16, "Mb2MmapTag must be 16 bytes"
  doAssert sizeof(Mb2MmapEntry) == 24, "Mb2MmapEntry must be 24 bytes"

proc alignUp8(x: uint64): uint64 {.inline.} =
  (x + 7) and not 7'u64

proc tagAt(p: pointer): ptr Mb2Tag {.inline.} = cast[ptr Mb2Tag](p)

proc firstTag(info: pointer): pointer {.inline.} = cast[pointer](cast[uint64](info) + 8'u64)

proc nextTag(tag: pointer): pointer {.inline.} =
  let sz = uint64(tagAt(tag).size)
  cast[pointer](alignUp8(cast[uint64](tag) + sz))

proc decodeTag(p: pointer): Mb2TagView {.inline.} =
  ## Reinterpret the wire tag into a typed view. No allocation.
  let kind = tagAt(p).kind
  {.push checks:off.}
  case kind
  of Mmap:
    result = Mb2TagView(kind: Mmap, mmap: cast[ptr Mb2MmapTag](p))
  of Cmdline, BootLoaderName:
    result = Mb2TagView(kind: kind, str: cast[ptr Mb2StrTag](p))
  else:
    result = Mb2TagView(kind: kind, raw: cast[ptr Mb2Tag](p))
  {.pop.}

iterator tags*(info: pointer): Mb2TagView =
  ## Yields every tag in order. Stops at End or when the cursor
  ## exceeds totalSize.
  let infoRec = cast[ptr Mb2Info](info)
  let endTag  = cast[uint64](info) + uint64(infoRec.totalSize)

  var tag = firstTag info
  while cast[uint64](tag) + 8'u64 <= endTag:
    let v = decodeTag(tag)
    if v.kind == End: break
    yield v
    tag = nextTag tag

proc findTag*(info: pointer, want: Mb2TagKind): Option[Mb2TagView] {.inline.} =
  for t in tags(info):
    if t.kind == want:
      return some(t)

iterator memoryMap*(info: pointer): MemRegion =
  ## Yields each entry in the memory map tag with its type as an enum.
  let v = findTag(info, Mmap)
  if v.isSome:
    let mt = v.get.mmap
    let entrySize = uint64(mt.entrySize)
    let tagEnd    = cast[uint64](mt) + uint64(mt.size)

    var p = cast[uint64](mt) + uint64(sizeof(Mb2MmapTag))
    while p + uint64(sizeof(Mb2MmapEntry)) <= tagEnd:
      let e = cast[ptr Mb2MmapEntry](p)
      yield MemRegion(base: e.base, length: e.length, kind: e.kind)
      p += entrySize

# proc cmdline*(info: pointer): Option[cstring] =
#   ## Returns the kernel command line, or none if not present.
#   let v = findTag(info, Cmdline)
#   if v.isNone: return none(cstring)
#   let s = v.get.str
#   # String starts right after the 8-byte tag header.
#   some cast[cstring](cast[uint64](s) + 8'u64)
#
# proc bootloaderName*(info: pointer): Option[cstring] =
#   let v = findTag(info, BootLoaderName)
#   if v.isNone: return none(cstring)
#   let s = v.get.str
#   some cast[cstring](cast[uint64](s) + 8'u64)


proc dumpMemoryMap*(info: pointer) =
  let kernelStack = kernelStackInfo()
  let kernelMem = kernelMemInfo()
  {.push fieldChecks:off.}
  for r in memoryMap(info):
    put "base="
    putHex r.base
    put " len="
    putHex r.length
    put " kind="
    case r.kind
    of Available: put "available\n"
    of Reserved:  put "reserved\n"
    of Acpi:      put "acpi\n"
    of Nvs:       put "nvs\n"
    of Bad:       put "bad\n"
  {.pop.}
  put "sp="
  putHex kernelStack.sp
  put " kernelStackTop="
  putHex kernelStack.top
  put " kernelStopBase="
  putHex kernelStack.base
  put "\nkernelStart="
  putHex kernelMem.start
  put " kernelEnd="
  putHex kernelMem.start + kernelMem.length
  put " kernelSz="
  putHex kernelMem.length

initAppend 1:
  dumpMemoryMap cast[pointer](cast[uint64](grub2InfoPtr))


