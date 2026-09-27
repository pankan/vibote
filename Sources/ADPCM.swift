import Foundation

// IMA/DVI ADPCM: four-bit codes, high nibble first on the ATV transport.
struct ADPCM {
    var predictor = 0
    var index = 0
    static let adjust = [-1,-1,-1,-1,2,4,6,8]
    static let steps = [7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,22385,24623,27086,29794,32767]
    mutating func decode(_ bytes: [UInt8]) -> [Int16] {
        var result: [Int16] = []; result.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            for code in [Int(byte >> 4), Int(byte & 15)] {
                let step = Self.steps[index]
                var delta = step >> 3
                if code & 1 != 0 { delta += step >> 2 }
                if code & 2 != 0 { delta += step >> 1 }
                if code & 4 != 0 { delta += step }
                predictor = min(32767, max(-32768, predictor + (code & 8 == 0 ? delta : -delta)))
                index = min(88, max(0, index + Self.adjust[code & 7]))
                result.append(Int16(predictor))
            }
        }
        return result
    }
}
