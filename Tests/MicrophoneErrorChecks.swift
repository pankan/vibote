import Foundation
@main struct MicrophoneErrorChecks {
 static func main() {
  assert(microphoneErrorMessage([0x0c,0x0f,0x02]).contains("asleep"))
  assert(microphoneErrorMessage([0x0c,0x0f,0x03]).contains("notifications"))
  assert(microphoneErrorMessage([0x0c,0x0f,0x80]).contains("already active"))
  assert(microphoneErrorMessage([0x0c,0x01,0x0f]).contains("0x010F"))
  assert(microphoneErrorMessage([0x0c]).contains("incomplete"))
  print("Microphone error checks passed")
 }
}
