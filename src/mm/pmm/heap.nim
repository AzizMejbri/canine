import mm/pmm/frame_alloc
import kstd/[option, mem, fmt, hooks]
import drivers/output/serial as com


const 
  AllocMagic = 0x11FE'u16
  FreeMagic = 0xDEAD'u16
  NilOff = uint16.high

type
  Header {.packed.} = object
    magic, length, nextOff, prevOff: uint16  

  FrameHeader {.packed.} = object
    nextFrame: ptr FrameHeader
    used: uint64    # will only use a uint16, uint64 for 8-byte alignment, alignment wont be handled tho until later
    dummyHeader: Header

static:
  doAssert sizeof(Header) == 8, "Expected size of Header to be 8 bytes"

var gHeap: ptr FrameHeader = nil

proc isValidHeader(h: Header): bool {.inline.} =
  h.magic == AllocMagic

proc hasNextHeader(h: Header): bool {.inline.} =
  h.nextOff != NilOff

proc hasPrevHeader(h: Header): bool {.inline.} =
  h.prevOff != NilOff

proc fromOffToPtr(off: uint64, base: uint64): pointer {.inline.} =
  cast[pointer](off + base)

proc fromPtrToOff(p: pointer, base: uint64): uint16 {.inline.} =
  cast[uint16](cast[uint64](p) - base)

proc asBytes[T](p: T): ptr UncheckedArray[uint8] {.inline.} =
  when T is pointer or T is ptr:
    cast[ptr UncheckedArray[uint8]](p)
  else:
    {.error: "Attempt to transform a non pointer type to bytes".}

proc squeezeBetween(currHeader, nextHeader: ptr Header, base: uint64, sz: uint): pointer {.inline.} =
  let newHeader: ptr Header = cast[ptr Header](cast[uint64](currHeader) + currHeader.length + uint64(sizeof Header))
  newHeader.magic = AllocMagic
  newHeader.nextOff = fromPtrToOff(nextHeader, base)
  newHeader.prevOff = fromPtrToOff(currHeader, base)
  newHeader.length = cast[uint16](sz)
  let off = fromPtrToOff(newHeader, base)
  currHeader.nextOff = off
  nextHeader.prevOff = off
  cast[pointer](cast[uint64](newHeader) + cast[uint64](sizeof Header))


proc alloc(sz: uint): pointer =
  doAssert sz != 0, "alloc() does not accept a sz of 0"
  const msg: string = "alloc() does not accept a variable of data size larger than " & $(FrameSize + sizeof(FrameHeader))
  doAssert sz <= FrameSize + cast[uint64](sizeof(FrameHeader)), msg
  if unlikely(gHeap == nil):
    let frameTmp = allocFrame()
    if frameTmp.isNone:
      return nil
    let frame = frameTmp.get
    # discard mem.set(cast[pointer](frame), 0, FrameSize)
    let frameHead = cast[ptr FrameHeader](frame)
    frameHead.nextFrame = nil
    frameHead.used = cast[uint64](sizeof FrameHeader)
    frameHead.dummyHeader.magic = AllocMagic
    frameHead.dummyHeader.length = 0x0
    frameHead.dummyHeader.nextOff = NilOff
    frameHead.dummyHeader.prevOff = NilOff
    gHeap = frameHead
  
  var currHeap: ptr FrameHeader = gHeap

  while currHeap.used + sz + cast[uint64](sizeof(Header)) > FrameSize:
    if currHeap.nextFrame == nil:
      let frameTmp = allocFrame()
      if frameTmp.isNone:
        return nil
      let frame = frameTmp.get
      let frameHead = cast[ptr FrameHeader](frame)
      frameHead.nextFrame = nil
      frameHead.used = cast[uint64](sizeof FrameHeader)
      frameHead.dummyHeader.magic = AllocMagic
      frameHead.dummyHeader.length = 0
      frameHead.dummyHeader.nextOff = NilOff
      frameHead.dummyHeader.prevOff = NilOff
      currHeap.nextFrame = frameHead
      currHeap = frameHead
      break
    else: currHeap = currHeap.nextFrame

  if currHeap.used == cast[uint64](sizeof(FrameHeader)):
    let currHeader = cast[ptr Header](cast[uint64](currHeap) + cast[uint64](sizeof FrameHeader))
    currHeader.magic = AllocMagic
    currHeader.length = cast[uint16](sz)
    currHeader.nextOff = NilOff
    currHeader.prevOff = NilOff
    currHeap.dummyHeader.nextOff = uint16(sizeof FrameHeader)
    result = cast[pointer](cast[uint64](currHeap) + cast[uint64](sizeof(FrameHeader) + sizeof(Header)))
    currHeap.used += sz + cast[uint64](sizeof Header)
    return

  var currHeader: ptr Header = addr currHeap.dummyHeader
  doAssert currHeader[].isValidHeader(), "Detected a corrupt heap entry"

  while currHeader[].hasNextHeader():
    doAssert currHeader[].isValidHeader(), "Detected a corrupt heap entry"
    let nextHeader = cast[ptr Header](fromOffToPtr(currHeader.nextOff, cast[uint64](currHeap)))
    if (cast[uint64](nextHeader) - cast[uint64](currHeader)) >= (currHeader.length + sz + 2 * sizeof Header):
      currHeap.used += sz + cast[uint64](sizeof Header)
      return squeezeBetween(currHeader, nextHeader, cast[uint64](currHeap), sz)
    currHeader = nextHeader
  let nextHeader: ptr Header = cast[ptr Header](cast[uint64](currHeader) + currHeader.length + cast[uint64](sizeof Header))
  nextHeader.magic = AllocMagic
  nextHeader.nextOff = NilOff
  nextHeader.prevOff = fromPtrToOff(currHeader, cast[uint64](currHeap))
  nextHeader.length = cast[uint16](sz)
  currHeader.nextOff = fromPtrToOff(nextHeader, cast[uint64](currHeap))
  result = cast[pointer](cast[uint64](nextHeader) + cast[uint64](sizeof Header))
  currHeap.used += sz + cast[uint64](sizeof Header)

proc releaseIfEmpty(prevFrame, currHeap: ptr FrameHeader) {.inline.} =
  ## If `currHeap`'s live byte count has dropped back to just the frame
  ## header, unlink it from the frame chain and push its page back to the
  ## PMM. `prevFrame` is nil iff `currHeap` is the current head of the chain.
  if currHeap.used != uint64(sizeof FrameHeader):
    return
  if prevFrame == nil:
    doAssert gHeap == currHeap, "invariant: nil prevFrame but curr isn't head"
    gHeap = currHeap.nextFrame
  else:
    prevFrame.nextFrame = currHeap.nextFrame
  freeFrame(cast[Frame](cast[uint64](currHeap)))

proc free(p: pointer) =
  ## the regular free function to deallocate variables from physical memory
  ## it leaves traces of old data until they're overwritten randomly, to clear traces of old allocations
  ## when freeing data, use freeClear that clear all the old metadata and data but at the cost of some speed 
  doAssert p != nil,     "Attempt to free() a nil pointer"
  doAssert gHeap != nil, "The heap is nil, meaning no allocation ever happened before calling free()"
  var prevFrame: ptr FrameHeader = nil
  var currHeap: ptr FrameHeader = gHeap
  while cast[uint64](p) notin cast[uint64](currHeap) + cast[uint64](sizeof(FrameHeader))..<cast[uint64](currHeap) + FrameSize:
    doAssert currHeap.nextFrame != nil, "Attempt to free() a pointer not allocated by our own heap"
    prevFrame = currHeap
    currHeap = currHeap.nextFrame
  doAssert cast[uint64](p) notin cast[uint64](currHeap)..<cast[uint64](currHeap) + cast[uint64](sizeof FrameHeader),
    "Attempt to delete crucial metadata from the heap"
  
  let header: ptr Header = cast[ptr Header](cast[uint64](p) - cast[uint64](sizeof Header))
  let nextHeader: ptr Header = cast[ptr Header](cast[uint64](currHeap) + header.nextOff)
  let prevHeader: ptr Header = cast[ptr Header](cast[uint64](currHeap) + header.prevOff)
  if header.prevOff == NilOff and header.nextOff == NilOff:
    currHeap.dummyHeader.nextOff = NilOff
  elif header.nextOff == NilOff:
    prevHeader.nextOff = NilOff
  elif header.prevOff == NilOff:
    currHeap.dummyHeader.nextOff = header.nextOff
    nextHeader.prevOff = NilOff
  else:
    prevHeader.nextOff = header.nextOff
    nextHeader.prevOff = header.prevOff
  currHeap.used -= header.length + cast[uint64](sizeof Header)
  releaseIfEmpty(prevFrame, currHeap)


proc freeDebug(p: pointer) =
  doAssert p != nil,     "Attempt to free() a nil pointer"
  doAssert gHeap != nil, "The heap is nil, meaning no allocation ever happened before calling free()"
  var prevFrame: ptr FrameHeader = nil
  var currHeap: ptr FrameHeader = gHeap
  while cast[uint64](p) notin cast[uint64](currHeap) + cast[uint64](sizeof(FrameHeader))..<cast[uint64](currHeap) + FrameSize:
    doAssert currHeap.nextFrame != nil, "Attempt to free() a pointer not allocated by our own heap"
    prevFrame = currHeap
    currHeap = currHeap.nextFrame
  doAssert cast[uint64](p) notin cast[uint64](currHeap)..<cast[uint64](currHeap) + cast[uint64](sizeof FrameHeader),
    "Attempt to delete crucial metadata from the heap"
  
  let header: ptr Header = cast[ptr Header](cast[uint64](p) - cast[uint64](sizeof Header))
  let nextHeader: ptr Header = cast[ptr Header](cast[uint64](currHeap) + header.nextOff)
  let prevHeader: ptr Header = cast[ptr Header](cast[uint64](currHeap) + header.prevOff)
  header.magic = FreeMagic
  if header.prevOff == NilOff and header.nextOff == NilOff:
    currHeap.dummyHeader.nextOff = NilOff
  elif header.nextOff == NilOff:
    prevHeader.nextOff = NilOff
  elif header.prevOff == NilOff:
    currHeap.dummyHeader.nextOff = header.nextOff
    nextHeader.prevOff = NilOff
  else:
    prevHeader.nextOff = header.nextOff
    nextHeader.prevOff = header.prevOff
  currHeap.used -= header.length + cast[uint64](sizeof Header)
  releaseIfEmpty(prevFrame, currHeap)

proc freeClear(p: pointer) =
  doAssert p != nil,     "Attempt to free() a nil pointer"
  doAssert gHeap != nil, "The heap is nil, meaning no allocation ever happened before calling free()"
  var prevFrame: ptr FrameHeader = nil
  var currHeap: ptr FrameHeader = gHeap
  while cast[uint64](p) notin cast[uint64](currHeap) + cast[uint64](sizeof(FrameHeader))..<cast[uint64](currHeap) + FrameSize:
    doAssert currHeap.nextFrame != nil, "Attempt to free() a pointer not allocated by our own heap"
    prevFrame = currHeap
    currHeap = currHeap.nextFrame
  doAssert cast[uint64](p) notin cast[uint64](currHeap)..<cast[uint64](currHeap) + cast[uint64](sizeof FrameHeader),
    "Attempt to delete crucial metadata from the heap"
  
  let header: ptr Header = cast[ptr Header](cast[uint64](p) - cast[uint64](sizeof Header))
  let nextHeader: ptr Header = cast[ptr Header](cast[uint64](currHeap) + header.nextOff)
  let prevHeader: ptr Header = cast[ptr Header](cast[uint64](currHeap) + header.prevOff)
  if header.prevOff == NilOff and header.nextOff == NilOff:
    currHeap.dummyHeader.nextOff = NilOff
  elif header.nextOff == NilOff:
    prevHeader.nextOff = NilOff
  elif header.prevOff == NilOff:
    currHeap.dummyHeader.nextOff = header.nextOff
    nextHeader.prevOff = NilOff
  else:
    prevHeader.nextOff = header.nextOff
    nextHeader.prevOff = header.prevOff
  discard mem.set(header, 0, header.length + cast[uint64](sizeof Header))
  currHeap.used -= header.length + cast[uint64](sizeof Header)
  releaseIfEmpty(prevFrame, currHeap)

proc dumpHeader(h: ptr Header, base: uint64) =
  let off = cast[uint64](h) - base
  puts "  Header @ base+"
  putHexPadded(off, 4)
  puts "  magic="
  putHexPadded(uint64(h.magic), 4)
  puts "  len="
  putHexPadded(uint64(h.length), 4)
  puts "  nextOff="
  putHexPadded(uint64(h.nextOff), 4)
  puts "  prevOff="
  putHexPadded(uint64(h.prevOff), 4)
  puts "  "

  if h.magic == AllocMagic:      puts "[ALLOC]"
  elif h.magic == FreeMagic:     puts "[FREE]"
  else:                          puts "[GARBAGE]"

  if not h[].isValidHeader():
    puts " (invalid!)"
  puts "\n"

  # payload preview
  let payload = cast[uint64](h) + uint64(sizeof Header)
  hexdump(cast[pointer](payload), uint(h.length), "    payload:")

proc onChain(chain: array[64, uint16], n: int, v: uint16): bool =
  for i in 0 ..< n:
    if chain[i] == v: return true
  false

proc dumpFrame(frame: ptr FrameHeader, idx: int) =
  let base = cast[uint64](frame)
  puts "\n--- Frame "
  putUint uint64(idx)
  puts " @ "
  putHexPadded(base, 16)
  puts " ---\n"
  puts "  used = "
  putUint(frame.used)
  puts " / "
  putUint(uint64(FrameSize))
  puts "  nextFrame = "
  putHexPadded(cast[uint64](frame.nextFrame), 16)
  putc('\n')

  # ---- pass 1: active chain (dummy + live allocs) ----
  var chain: array[64, uint16]
  var chainLen = 0
  var h: ptr Header = addr frame.dummyHeader
  chain[chainLen] = uint16(cast[uint64](h) - base)
  inc chainLen
  var guard = 0
  while h[].hasNextHeader():
    h = cast[ptr Header](base + uint64(h.nextOff))
    if chainLen < chain.len:
      chain[chainLen] = uint16(cast[uint64](h) - base)
      inc chainLen
    inc guard
    if guard > 512:
      puts "  !! chain loop detected\n"
      break

  puts "  [active chain]\n"
  for i in 0 ..< chainLen:
    let p = cast[ptr Header](base + uint64(chain[i]))
    dumpHeader(p, base)

  # ---- pass 2: linear scan for orphaned (freed) headers ----
  # Headers are NOT guaranteed to be 8-aligned, because a header sits at
  # currHeader + currHeader.length + sizeof(Header) and length is arbitrary.
  # So scan byte-by-byte.
  var orphans = 0
  var off: uint64 = uint64(sizeof FrameHeader)   # skip FrameHeader itself
  let stop = uint64(FrameSize) - uint64(sizeof Header)
  while off <= stop:
    let cand = cast[ptr Header](base + off)
    if (cand.magic == AllocMagic or cand.magic == FreeMagic) and
       not onChain(chain, chainLen, uint16(off)) and
       off + uint64(sizeof Header) + uint64(cand.length) <= uint64(FrameSize):
      if orphans == 0:
        puts "  [orphaned / freed]\n"
      dumpHeader(cand, base)
      inc orphans
      # jump past this header's payload so we don't re-detect inside it
      off += uint64(sizeof Header) + uint64(cand.length)
      continue
    inc off

  if orphans == 0:
    puts "  (no orphaned headers)\n"

# proc dumpFrame(frame: ptr FrameHeader, idx: int) =
#   puts "\n--- Frame "
#   putUint uint64(idx)
#   puts " @ "
#   putHexPadded(cast[uint64](frame), 16)
#   puts " ---\n"
#   puts "  used = "
#   putUint(frame.used)
#   puts " / "
#   putUint(uint64(FrameSize))
#   puts "  nextFrame = "
#   putHexPadded(cast[uint64](frame.nextFrame), 16)
#   putc('\n')
#
#   # Walk the header chain
#   var h: ptr Header = addr frame.dummyHeader
#   var guard = 0
#   while true:
#     dumpHeader(h, cast[uint64](frame))
#     if not h[].hasNextHeader(): break
#     h = cast[ptr Header](cast[uint64](frame) + uint64(h.nextOff))
#     inc guard
#     if guard > 256:
#       puts "  !! header chain loop detected\n"
#       break

proc dumpHeap*() =
  puts "=== HEAP DUMP ===\n"
  if gHeap == nil:
    puts "gHeap = nil (no allocations yet)\n"
    return

  var f: ptr FrameHeader = gHeap
  var i = 0
  var guard = 0
  while f != nil:
    dumpFrame(f, i)
    f = f.nextFrame
    inc i
    inc guard
    if guard > 64:
      puts "!! frame chain loop detected\n"
      break
  puts "=== END HEAP ===\n"

proc validateHeap*() =
  if gHeap == nil: return
  var f: ptr FrameHeader = gHeap
  while f != nil:
    doAssert f.dummyHeader.magic == AllocMagic,
      "heap corruption: frame dummy header has wrong magic"
    doAssert f.dummyHeader.prevOff == NilOff,
      "heap corruption: frame dummy prevOff should be NilOff"
    doAssert f.dummyHeader.length == 0,
      "heap corruption: frame dummy length should be 0"

    var sum: uint64 = uint64(sizeof FrameHeader)
    var h: ptr Header = addr f.dummyHeader
    var guard = 0

    while h[].hasNextHeader():
      let nextH = cast[ptr Header](cast[uint64](f) + uint64(h.nextOff))
      doAssert nextH.magic == AllocMagic,
        "heap corruption: chained header has non-Alloc magic"

      let expectedPrevOff =
        if h == addr f.dummyHeader: NilOff
        else: fromPtrToOff(h, cast[uint64](f))
      doAssert nextH.prevOff == expectedPrevOff,
        "heap corruption: back-link mismatch"

      h = nextH
      sum += uint64(h.length) + uint64(sizeof Header)   # <- sum the NEW h, not the old one
      inc guard
      doAssert guard < 512, "heap corruption: header chain too long"

    # no post-loop add — the last real header was counted on the iteration that reached it
    doAssert sum == f.used,
      "heap corruption: frame.used does not match sum of headers"

    f = f.nextFrame

# ---- heap test --------------------------------------------------

const MaxTestFrames = 32

type HeapSnapshot = object
  frames: array[MaxTestFrames, ptr FrameHeader]
  used:   array[MaxTestFrames, uint64]
  count:  int

proc takeSnapshot(): HeapSnapshot =
  var f = gHeap
  while f != nil and result.count < MaxTestFrames:
    result.frames[result.count] = f
    result.used[result.count]   = f.used
    inc result.count
    f = f.nextFrame
  doAssert f == nil, "test: heap has more frames than MaxTestFrames"

proc checkUnchanged(s: HeapSnapshot) =
  var f = gHeap
  var i = 0
  while i < s.count:
    doAssert f != nil, "test: an existing frame disappeared"
    doAssert f == s.frames[i], "test: frame chain reordered"
    doAssert f.used == s.used[i], "test: frame used drifted"
    inc i
    f = f.nextFrame
  while f != nil:
    doAssert f.used == uint64(sizeof FrameHeader),
      "test: new frame is not empty"
    doAssert f.dummyHeader.magic == AllocMagic,
      "test: new frame has bad dummy magic"
    doAssert f.dummyHeader.nextOff == NilOff,
      "test: new frame has a live allocation"
    f = f.nextFrame

initAppend 255:
  block:
    puts "\n[test 1] middle-slot free + reuse\n"
    let before = takeSnapshot()

    let a = alloc 16
    let b = alloc 16
    let c = alloc 16
    doAssert a != nil and b != nil and c != nil, "test: alloc returned nil"
    doAssert a != b and b != c and a != c,          "test: allocs aliased"
    dumpHeap()

    freeDebug b
    dumpHeap()

    let d = alloc 16
    doAssert d == b, "test: middle-slot reuse failed"
    dumpHeap()

    free a; free c; free d
    checkUnchanged(before)

  block:
    puts "\n[test 2] free first alloc\n"
    let before = takeSnapshot()
    let a = alloc 16
    let b = alloc 16
    let c = alloc 16
    free a
    let d = alloc 16
    doAssert d == a, "test: first-slot reuse failed"
    free b; free c; free d
    checkUnchanged(before)

  block:
    puts "\n[test 3] free last alloc\n"
    let before = takeSnapshot()
    let a = alloc 16
    let b = alloc 16
    let c = alloc 16
    free c
    let d = alloc 16
    doAssert d == c, "test: last-slot reuse failed"
    free a; free b; free d
    checkUnchanged(before)

  block:
    puts "\n[test 4] fresh-frame fill + drain\n"
    let before = takeSnapshot()
    var ps: array[128, pointer]
    for i in 0 ..< ps.len:
      ps[i] = alloc 32
      doAssert ps[i] != nil, "test: alloc returned nil"
    dumpHeap()
    for i in countdown(ps.len - 1, 0):
      free ps[i]
    dumpHeap()
    checkUnchanged(before)

  block:
    puts "\n[test 5] multi-frame strided free\n"
    let before = takeSnapshot()
    var ps: array[200, pointer]
    for i in 0 ..< ps.len:
      ps[i] = alloc 32
      doAssert ps[i] != nil, "test: alloc returned nil"
    for i in countup(0, ps.len - 1, 3): free ps[i]
    for i in countup(1, ps.len - 1, 3): free ps[i]
    for i in countup(2, ps.len - 1, 3): free ps[i]
    dumpHeap()
    checkUnchanged(before)

  block:
    puts "\n[test 6] alloc/free churn\n"
    let before = takeSnapshot()
    for round in 0 ..< 20:
      var ps: array[40, pointer]
      for i in 0 ..< ps.len:
        ps[i] = alloc uint(8 + (i mod 24))
      for i in 0 ..< ps.len:
        free ps[i]
    checkUnchanged(before)

  block:
    puts "\n[test 7] size-1\n"
    let before = takeSnapshot()
    let small = alloc 1
    doAssert small != nil, "test: alloc returned nil"
    free small
    checkUnchanged(before)

  block:
    puts "\n[test 8] interleaved with long-lived alloc\n"
    let before = takeSnapshot()
    let keep = alloc 64
    var ps: array[20, pointer]
    for i in 0 ..< ps.len: ps[i] = alloc 32
    for i in 0 ..< ps.len:
      if (i and 1) == 0: free ps[i]
    for i in 0 ..< ps.len:
      if (i and 1) == 1: free ps[i]
    free keep
    checkUnchanged(before)

  puts "heap: all tests passed\n"
