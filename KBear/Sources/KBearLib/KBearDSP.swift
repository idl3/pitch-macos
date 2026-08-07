import Foundation

struct VocalBlendParameters {
    var mono: Float = 0
    var karaoke: Float = 0
    var dualMono: Bool = false
    var volume: Float = 1.0
}

/// Apply the Mono/Karaoke vocal-removal blend to one stereo sample.
func processStereoSample(l: Float, r: Float, params: VocalBlendParameters) -> (left: Float, right: Float) {
    let side = (l - r) * 0.5
    let total = params.mono + params.karaoke
    let blendScale = total > 1.0 ? (1.0 / total) : 1.0

    var leftSample = (params.mono + params.karaoke) * blendScale * side
    var rightSample = (params.mono - params.karaoke) * blendScale * side

    if total <= .leastNormalMagnitude {
        leftSample = l
        rightSample = r
    }

    if params.dualMono {
        rightSample = leftSample
    }

    return (leftSample * params.volume, rightSample * params.volume)
}
