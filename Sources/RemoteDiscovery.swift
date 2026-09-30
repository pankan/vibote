import Foundation

/// Advertisement names can be present before CoreBluetooth resolves the cached name.
func matchesRemoteName(_ name: String?, advertisedName: String?) -> Bool {
    [name, advertisedName].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains("T6") }
}
