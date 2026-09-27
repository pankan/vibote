import Foundation

/// The standard BLE Battery Level is one byte, from 0 to 100 percent.
func remoteBatteryPercentage(_ data: Data?) -> Int? {
    guard let data, data.count == 1, let value = data.first, value <= 100 else { return nil }
    return Int(value)
}
