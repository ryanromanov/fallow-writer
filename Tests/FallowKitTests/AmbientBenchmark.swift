import Foundation
import Testing
@testable import FallowKit

/// Times each ambient scene when FALLOW_BENCHMARK is set. Run with an optimized build:
/// scripts/test.sh -c release -Xswiftc -enable-testing --filter AmbientBenchmark
@Suite struct AmbientBenchmark {
    @Test func cpuShare() {
        guard ProcessInfo.processInfo.environment["FALLOW_BENCHMARK"] != nil else { return }
        for choice in AmbientChoice.allCases { time(choice) }
    }

    func time(_ choice: AmbientChoice) {
        let rate = 44_100.0, seconds = 60.0, chunk = 512
        let field = choice.makeScene(sampleRate: rate)
        var left = [Float](repeating: 0, count: chunk), right = left
        let frames = Int(rate * seconds)
        let start = DispatchTime.now().uptimeNanoseconds
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                for _ in 0..<(frames / chunk) { field.render(left: l.baseAddress!, right: r.baseAddress!, frames: chunk) }
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        print(String(format: "BENCH \(choice.title): %.3f s to render %.0f s of audio = %.2f%% of one core", elapsed, seconds, elapsed / seconds * 100))
    }
}
