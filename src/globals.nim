const IdtOffs* = (
  pit:      0x20'u8,
  keyboard: 0x21'u8,
)

const IrqLines* = (
  pit:      0x0'u8,
  keyboard: 0x1'u8,
)

const PitFreq*         = 250
const CodeSegmentSel*  = 0x08'u16
