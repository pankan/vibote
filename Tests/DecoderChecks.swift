import Foundation
@main struct DecoderChecks {
 static func main() {
  var silence = ADPCM()
  assert(silence.decode([0,0,0]) == [0,0,0,0,0,0])
  var order = ADPCM()
  assert(order.decode([0x17]) == [1,12])
  var limits = ADPCM()
  let loud = limits.decode(Array(repeating: 0x77, count: 1000))
  assert(loud.last == 32767 && limits.index == 88)
  let negative = limits.decode(Array(repeating: 0xff, count: 1000))
  assert(negative.last == -32768 && limits.index == 88)
  var a = ADPCM(), b = ADPCM()
  let whole = a.decode([0x17,0x82,0xff,0x00])
  let split = b.decode([0x17,0x82]) + b.decode([0xff,0x00])
  assert(whole == split)
  print("ADPCM checks passed: silence, nibble order, saturation, streaming continuity")
 }
}
