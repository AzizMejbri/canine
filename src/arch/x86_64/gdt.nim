type
  GdtPointer {.packed.} = object
    limit: uint16
    base : uint64

  GdtEntryInfo = object
    present *: bool
    dpl     *: int
    isSystem*: bool
    typ     *: int      # low nibble of access byte
    base    *: uint32
    limit   *: uint32

var gdt64Pointer {.importc: "gdt64_pointer".}: GdtPointer

proc gdtBase*(): ptr UncheckedArray[uint64] {.inline.} =
  cast[ptr UncheckedArray[uint64]](gdt64Pointer.base)

proc gdtEntryCount*(): int {.inline.} =
  (int(gdt64Pointer.limit) + 1) shr 3  # div 8

proc decodeEntry*(raw: uint64): GdtEntryInfo =
  let access = uint8((raw shr 40) and 0xFF)
  let flags  = uint8((raw shr 48) and 0xFF)

  result.present  = (access and 0x80) != 0
  result.dpl      = int((access shr 5) and 0x3)
  result.isSystem = (access and 0x10) == 0
  result.typ      = int(access and 0xF)

  result.limit =
    uint32(raw and 0xFFFF) or
    (uint32(flags and 0xF) shl 16)
  if (flags and 0x80) != 0:
    result.limit = (result.limit shl 12) or 0xFFF

  result.base =
    uint32((raw shr 16) and 0xFFFF) or
    (uint32((raw shr 32) and 0xFF) shl 16) or
    (uint32((raw shr 56) and 0xFF) shl 24)

proc typeName*(info: GdtEntryInfo): cstring =
  if not info.present: return "not-present"
  if info.isSystem:
    case info.typ
    of 0x1: "16-bit TSS (avail)"
    of 0x2: "LDT"
    of 0x3: "16-bit TSS (busy)"
    of 0x9: "64-bit TSS (avail)"
    of 0xB: "64-bit TSS (busy)"
    of 0xC: "64-bit call gate"
    of 0xE: "64-bit interrupt gate"
    of 0xF: "64-bit trap gate"
    else:   "system/unknown"
  else:
    if (info.typ and 0x8) != 0: "code" else: "data"
