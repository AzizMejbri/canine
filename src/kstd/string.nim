
proc appendString*(s: var string, x: cstring)
  {.compilerproc, importc: "appendString", header: "string_trap.h".}

proc copyString*(dst: var string, src: string)
  {.compilerproc, importc: "copyString", header: "string_trap.h".}

proc nimToCStringConv*(s: string): cstring
  {.compilerproc, importc: "nimToCStringConv", header: "string_trap.h".}

proc rawNewString*(len: int): string
  {.compilerproc, importc: "rawNewString", header: "string_trap.h".}

proc setLengthStr*(s: var string, newLen: int)
  {.compilerproc, importc: "setLengthStr", header: "string_trap.h".}

proc prepareAdd*(s: var string, addLen: int): int
  {.compilerproc, importc: "prepareAdd", header: "string_trap.h".}

proc resizeString*(s: var string, addLen: int)
  {.compilerproc, importc: "resizeString", header: "string_trap.h".}

# Sequences — same category, same trap
proc rawNewSeq*(len: int): pointer
  {.compilerproc, importc: "rawNewSeq", header: "string_trap.h".}

proc setLengthSeq*(s: pointer, T: pointer, newLen: int)
  {.compilerproc, importc: "setLengthSeq", header: "string_trap.h".}
