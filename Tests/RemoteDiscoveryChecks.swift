import Foundation
@main struct RemoteDiscoveryChecks {
    static func main() {
        assert(matchesRemoteName("T6-Remote", advertisedName: nil))
        assert(matchesRemoteName(nil, advertisedName: "t6 remote"))
        assert(matchesRemoteName("", advertisedName: "T6"))
        assert(!matchesRemoteName(nil, advertisedName: nil))
        assert(!matchesRemoteName("Headphones", advertisedName: "Keyboard"))
        print("Remote discovery checks passed")
    }
}
