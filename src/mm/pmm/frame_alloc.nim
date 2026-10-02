import mm/pmm/map
import arch/x86_64/debug
import kstd/[fmt, stack, option, hooks]


const 
  MaxRegions = 256
  FrameSize* = 4096
  MaxPhyMem  = 16 * 1024 * 1024 * 1024 # later change according to MemInfo
  MaxFrames  = uint(MaxPhyMem div FrameSize)

type
  MemBlock* = object
    base*, length*: uint64

  Frame* = distinct uint64


var stackBuf: array[MaxFrames, Frame]

var gRegionCnt  : uint16 = 0
var gRegions*   : array[MaxRegions, MemBlock]

var gFrameStack : Stack[Frame]

proc alignUp(x, a: uint64): uint64   {.inline.} =
  (x + a - 1) and not (a - 1)
proc alignDown(x, a: uint64): uint64 {.inline.} =
  x and not (a - 1)

proc init() =
  gFrameStack = init[Frame, MaxFrames](addr stackBuf)
  let info = cast[pointer](cast[uint64](grub2InfoPtr))
  let kernelMem = kernelMemInfo()
  let kernelMemStart = kernelMem.start
  let kernelMemEnd = kernelMem.start + kernelMem.length
  let kStartAligned = alignDown(kernelMemStart, FrameSize)
  let kEndAligned   = alignUp(kernelMemEnd, FrameSize)

  for region in memoryMap(info):
    {.push checks:off.}
    case region.kind
    of Available:
      doAssert gRegionCnt < MaxRegions, "PMM: Phy Mem Region table overflow (MaxRegions set to `256`)"
      gRegions[gRegionCnt] = MemBlock(base: region.base, length: region.length)
      inc gRegionCnt
    else: continue
    {.pop.}

  for k in 0'u16 ..< gRegionCnt:
    let region = gRegions[k]
    var i = alignUp(region.base, FrameSize)
    let regionEnd = alignDown(region.base + region.length, FrameSize)
    while i + FrameSize <= regionEnd:
      if i + FrameSize <= kStartAligned or i >= kEndAligned:
        gFrameStack.unsafePush(cast[Frame](i))
      i += FrameSize

proc allocFrame*(): Option[Frame] =
  gFrameStack.pop()

proc freeFrame*(frame: Frame) =
  gFrameStack.unsafePush(frame)



initAppend 3:
  init()
