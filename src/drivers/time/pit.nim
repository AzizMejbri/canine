import globals
import kstd/option
import drivers/pic
import arch/x86_64/[port, idt, ctrl]
import drivers/output/vga
import kstd/hooks


const 
  PitPort0 = 0x40'u8
  PitPort1 = 0x41'u8        # rw
  PitPort2 = 0x42'u8        # rw
  PitCmdRegister = 0x43'u8  # r
  PitIrqLine = globals.IrqLines.pit
  PitIdtOffs = globals.IdtOffs.pit
  BaseFreq = 1193182;

type
  BinMode = enum
    Mode16Bit = 0
    BcdMode = 1

  OpMode = enum
    IOTC = (0 shl 1)        # interrupt on terminal count
    HRTOS = (1 shl 1)       # hardware retriggable one-shot
    RG = (2 shl 1)          # rate generator
    SWG = (3 shl 1)         # square wave generator                        
    SWTSTR = (4 shl 1)      # software triggered strobe
    HWTSTR = (5 shl 1)      # hardware triggered strobe

  AccessMode = enum
    LCVC = (0 shl 4)        # latch count value command
    LoByO = (1 shl 4)       # lobyte only
    HiByO = (2 shl 4)       # hibyte only
    LoHiBy = (3 shl 4)      # lobyte/hibyte

  SelChannel = enum
    Chan0 = (0 shl 6)       # Channel 0 
    Chan1 = (1 shl 6)       # Channel 1
    Chan2 = (2 shl 6)       # Channel 2
    RBCmd = (3 shl 6)       # Read-Back Command (8254 only)

  Config = object
    freq: uint32 
    binMode: BinMode
    opMode: OpMode
    accessMode: AccessMode


proc pitHandler(){.noconv, asmNoStackFrame.}
proc enable() {.inline.} =
  clearMask PitIrqLine
  setEntry PitIdtOffs, cast[uint64](cast[pointer](pitHandler)), CodeSegmentSel, InterruptGate, Ring0

proc init(conf: Option[Config]) =
  enable()
  var cfg = conf.orElse Config(
    freq: globals.PitFreq ,
    binMode: Mode16Bit,
    opMode: SWG,
    accessMode: LoHiBy
  )
  if cfg.freq == 0 or cfg.freq > BaseFreq:  cfg.freq = BaseFreq
  outb PitCmdRegister, uint8(ord(cfg.binMode) or ord(cfg.opMode) or ord(cfg.accessMode) or ord(SelChannel.Chan0))


  let divVal = BaseFreq div cfg.freq;
  let lo: uint8 = uint8(divVal and 0xFF);
  let hi: uint8 = uint8((divVal shr 8) and 0xFF);
  outb PitPort0, lo
  outb PitPort0, hi

var pitCounter: uint64 = 0

const targetPort = when PitIrqLine >= 8: SlaveCmd else: MasterCmd
proc pitIsrBody() {.exportc: "pit_isr_body", cdecl, used.}
proc pitHandler() {.noconv, asmNoStackFrame.} =
  pushAll()
  asm "call pit_isr_body"
  sendEOI PitIrqLine
  popAll()
  asm "iretq"

proc pitIsrBody() {.exportc: "pit_isr_body", cdecl, used.} =
  # setCursor 0, 0
  # put "Pit Counter: "
  # putUint pitCounter
  inc pitCounter

proc getPitCounter*(): uint64 {.inline.} = pitCounter

initAppend 130:
  init none(Config)
