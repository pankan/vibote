import Foundation

@main struct BatteryLevelChecks {
    static func main() {
        assert(remoteBatteryPercentage(Data([0])) == 0)
        assert(remoteBatteryPercentage(Data([57])) == 57)
        assert(remoteBatteryPercentage(Data([100])) == 100)
        assert(remoteBatteryPercentage(nil) == nil)
        assert(remoteBatteryPercentage(Data()) == nil)
        assert(remoteBatteryPercentage(Data([101])) == nil)
        assert(remoteBatteryPercentage(Data([255])) == nil)
        assert(remoteBatteryPercentage(Data([50, 60])) == nil)
        print("Battery level checks passed")
    }
}
