import Foundation
import HumanCore

/// ProfileTraits.Body -> HumanSpec. Values are clamped to the HumanHD morph ranges.
enum HumanTraitsMapper {
    static func spec(_ b: ProfileTraits.Body, seed: UInt64) -> HumanSpec {
        var s = HumanSpec.random(seed: seed)
        func c(_ v: Double, _ lo: Float = 0, _ hi: Float = 1) -> Float { min(hi, max(lo, Float(v))) }
        let male = b.gender >= 0.5
        s.shape.gender = c(b.gender)
        s.shape.age = c(b.age, 18, 85)
        s.shape.height = c(b.height)
        s.shape.weight = c(b.weight)
        s.shape.muscle = c(b.muscle)
        let anc = [c(b.african), c(b.asian), c(b.caucasian)]
        let sum = max(0.01, anc.reduce(0, +))
        s.shape.african = anc[0] / sum; s.shape.asian = anc[1] / sum; s.shape.caucasian = anc[2] / sum
        s.appearance.skin = SkinTone(tone: c(b.skinTone, 0.03, 1), undertone: c(b.undertone, -0.3, 0.7), flush: 0.5)
        s.appearance.detail = SkinDetail.matching(s.shape, seed: UInt32(truncatingIfNeeded: seed % 4))
        s.appearance.detail.stubble = male ? c(b.facialHair, 0, 1.5) : 0
        s.appearance.detail.freckles = c(b.freckles)
        s.appearance.detail.tattoo = 0
        s.appearance.eyes = eyes[b.eyeColor] ?? .brown
        s.appearance.hairColor = LinearColor(hex: hex(b.hairColor) ?? 0x2A1A10)
        s.hair = HairStyle.presets[b.hairStyle] ?? (male ? .short : .long)
        s.hair.seed = seed
        s.outfit = outfits[b.outfit] ?? .casual
        if s.outfit == .summerDress && male { s.outfit = .casual }
        return s
    }

    static let eyes: [String: EyeLook] = ["brown": .brown, "darkBrown": .darkBrown, "hazel": .hazel,
                                          "green": .green, "blue": .blue, "grey": .grey]
    static let outfits: [String: Outfit] = ["casual": .casual, "smart": .smart, "business": .business, "winter": .winter,
                                            "outdoor": .outdoor, "athletic": .athletic, "biker": .biker, "summerDress": .summerDress]

    static func hex(_ s: String) -> UInt32? {
        UInt32(s.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16)
    }
}
