proc inb*(port: uint16): uint8 {.inline.} =
  asm """
    .intel_syntax noprefix
    in al, dx
    .att_syntax
    : "=a"(`result`)
    : "d"(`port`)
  """

proc inw*(port: uint16): uint16 {.inline.} =
  asm """
    .intel_syntax noprefix
    in ax, dx
    .att_syntax
    : "=a"(`result`)
    : "d"(`port`)
  """

proc ind*(port: uint16): uint32 {.inline.} =
  asm """
    .intel_syntax noprefix
    in eax, dx
    .att_syntax
    : "=a"(`result`)
    : "d"(`port`)
  """

proc outb*(port: uint16, data: uint8) {.inline.} =
  asm """
    .intel_syntax noprefix
    out dx, al
    .att_syntax
    :
    : "d"(`port`), "a"(`data`)
  """

proc outw*(port: uint16, data: uint16) {.inline.} =
  asm """
    .intel_syntax noprefix
    out dx, ax
    .att_syntax
    :
    : "d"(`port`), "a"(`data`)
  """

proc outd*(port: uint16, data: uint32) {.inline.} =
  asm """
    .intel_syntax noprefix
    out dx, eax
    .att_syntax
    :
    : "d"(`port`), "a"(`data`)
  """
