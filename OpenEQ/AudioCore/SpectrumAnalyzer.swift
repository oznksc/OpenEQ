//
//  SpectrumAnalyzer.swift
//  OpenEQ
//
//  Created by Antigravity on 26.06.2026.
//

import Foundation
import Accelerate
import AVFoundation

struct SpectrumAnalysis {
    let levels: [Float]
    let leftPeak: Float
    let rightPeak: Float
    let peakLevel: Float
    let isClipping: Bool
}

final class SpectrumAnalyzer {
    static let barCount = 64

    private let fftSize: Int = 1024
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    private var window: [Float]
    private var previousLevels: [Float]
    private var smoothedLevels: [Float]
    private var monoSamples: [Float]
    private var windowedSamples: [Float]
    private var magnitudes: [Float]

    // Statically allocated buffers to reduce work inside the audio tap callback.
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var binRanges: [(start: Int, end: Int)] = []
    private var cachedSampleRate: Double = 0

    init() {
        self.log2n = vDSP_Length(10) // log2(1024) = 10
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        self.window = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        self.previousLevels = [Float](repeating: 0.0, count: Self.barCount)
        self.smoothedLevels = [Float](repeating: 0.0, count: Self.barCount)
        self.monoSamples = [Float](repeating: 0.0, count: fftSize)
        self.windowedSamples = [Float](repeating: 0.0, count: fftSize)
        self.magnitudes = [Float](repeating: 0.0, count: fftSize / 2)

        self.realBuffer = [Float](repeating: 0.0, count: fftSize / 2)
        self.imagBuffer = [Float](repeating: 0.0, count: fftSize / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Converts an audio tap buffer into spectrum bars plus simple peak/clipping metadata.
    func analyze(buffer: AVAudioPCMBuffer) -> SpectrumAnalysis? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameLength = Int(buffer.frameLength)
        guard frameLength >= fftSize else { return nil }

        updateBinRangesIfNeeded(sampleRate: buffer.format.sampleRate)

        let channelCount = max(1, min(Int(buffer.format.channelCount), 2))
        let leftPeak = peak(in: channelData[0], frameLength: frameLength)
        let rightPeak = channelCount > 1 ? peak(in: channelData[1], frameLength: frameLength) : leftPeak
        let peakLevel = max(leftPeak, rightPeak)

        if channelCount > 1 {
            for index in 0..<fftSize {
                monoSamples[index] = (channelData[0][index] + channelData[1][index]) * 0.5
            }
        } else {
            monoSamples.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress?.update(from: channelData[0], count: fftSize)
            }
        }

        // The tap provides PCM. We downmix to mono, window it, FFT it, then bin it into 64 bars.
        vDSP_vmul(monoSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        realBuffer.withUnsafeMutableBufferPointer { rPtr in
            imagBuffer.withUnsafeMutableBufferPointer { iPtr in
                var splitComplex = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)

                windowedSamples.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))

        for index in 0..<Self.barCount {
            let range = binRanges[index]
            var sum: Float = 0.0
            let count = max(1, range.end - range.start)

            for bin in range.start..<range.end {
                sum += magnitudes[bin]
            }

            let average = sum / Float(count)
            let db = 10 * log10(average + 1e-9)
            let normalized = max(0.0, min(1.0, (db + 60.0) / 55.0))
            let smoothing: Float = normalized > previousLevels[index] ? 0.45 : 0.12
            let smoothed = (normalized * smoothing) + (previousLevels[index] * (1.0 - smoothing))

            smoothedLevels[index] = smoothed
            previousLevels[index] = smoothed
        }

        return SpectrumAnalysis(
            levels: smoothedLevels,
            leftPeak: leftPeak,
            rightPeak: rightPeak,
            peakLevel: peakLevel,
            isClipping: peakLevel >= 0.96
        )
    }

    /// Converts a Core Audio input buffer into the same analysis used by AVAudioEngine taps.
    func analyze(
        bufferList: UnsafePointer<AudioBufferList>,
        frameLength: Int,
        sampleRate: Double
    ) -> SpectrumAnalysis? {
        guard frameLength >= fftSize else { return nil }

        updateBinRangesIfNeeded(sampleRate: sampleRate)

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard let firstBuffer = buffers.first, let firstData = firstBuffer.mData else {
            return nil
        }

        let firstChannelCount = max(1, Int(firstBuffer.mNumberChannels))
        let leftPeak: Float
        let rightPeak: Float

        if buffers.count >= 2,
           let leftData = buffers[0].mData,
           let rightData = buffers[1].mData {
            let left = leftData.assumingMemoryBound(to: Float.self)
            let right = rightData.assumingMemoryBound(to: Float.self)
            leftPeak = peak(in: left, frameLength: frameLength)
            rightPeak = peak(in: right, frameLength: frameLength)

            for index in 0..<fftSize {
                monoSamples[index] = (left[index] + right[index]) * 0.5
            }
        } else {
            let samples = firstData.assumingMemoryBound(to: Float.self)
            leftPeak = peakInterleaved(samples, frameLength: frameLength, channelCount: firstChannelCount, channel: 0)
            rightPeak = firstChannelCount > 1
                ? peakInterleaved(samples, frameLength: frameLength, channelCount: firstChannelCount, channel: 1)
                : leftPeak

            for frame in 0..<fftSize {
                var sum: Float = 0.0
                let baseIndex = frame * firstChannelCount

                for channel in 0..<firstChannelCount {
                    sum += samples[baseIndex + channel]
                }

                monoSamples[frame] = sum / Float(firstChannelCount)
            }
        }

        return analyzePreparedMonoSamples(
            leftPeak: leftPeak,
            rightPeak: rightPeak
        )
    }

    func reset() -> SpectrumAnalysis {
        previousLevels = [Float](repeating: 0.0, count: Self.barCount)
        smoothedLevels = [Float](repeating: 0.0, count: Self.barCount)
        return SpectrumAnalysis(
            levels: smoothedLevels,
            leftPeak: 0.0,
            rightPeak: 0.0,
            peakLevel: 0.0,
            isClipping: false
        )
    }

    private func peak(in channel: UnsafePointer<Float>, frameLength: Int) -> Float {
        var peak: Float = 0.0
        vDSP_maxmgv(channel, 1, &peak, vDSP_Length(frameLength))
        return min(1.0, peak)
    }

    private func peakInterleaved(
        _ samples: UnsafePointer<Float>,
        frameLength: Int,
        channelCount: Int,
        channel: Int
    ) -> Float {
        var peak: Float = 0.0
        vDSP_maxmgv(
            samples.advanced(by: channel),
            vDSP_Stride(channelCount),
            &peak,
            vDSP_Length(frameLength)
        )
        return min(1.0, peak)
    }

    private func analyzePreparedMonoSamples(leftPeak: Float, rightPeak: Float) -> SpectrumAnalysis {
        vDSP_vmul(monoSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        realBuffer.withUnsafeMutableBufferPointer { rPtr in
            imagBuffer.withUnsafeMutableBufferPointer { iPtr in
                var splitComplex = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)

                windowedSamples.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))

        for index in 0..<Self.barCount {
            let range = binRanges[index]
            var sum: Float = 0.0
            let count = max(1, range.end - range.start)

            for bin in range.start..<range.end {
                sum += magnitudes[bin]
            }

            let average = sum / Float(count)
            let db = 10 * log10(average + 1e-9)
            let normalized = max(0.0, min(1.0, (db + 60.0) / 55.0))
            let smoothing: Float = normalized > previousLevels[index] ? 0.45 : 0.12
            let smoothed = (normalized * smoothing) + (previousLevels[index] * (1.0 - smoothing))

            smoothedLevels[index] = smoothed
            previousLevels[index] = smoothed
        }

        let peakLevel = max(leftPeak, rightPeak)
        return SpectrumAnalysis(
            levels: smoothedLevels,
            leftPeak: leftPeak,
            rightPeak: rightPeak,
            peakLevel: peakLevel,
            isClipping: peakLevel >= 0.96
        )
    }

    private func updateBinRangesIfNeeded(sampleRate: Double) {
        guard sampleRate != cachedSampleRate || binRanges.count != Self.barCount else {
            return
        }

        cachedSampleRate = sampleRate
        binRanges.removeAll(keepingCapacity: true)

        let minimumFrequency: Double = 20
        let maximumFrequency = min(20_000, sampleRate * 0.5)
        let minLog = log10(minimumFrequency)
        let maxLog = log10(maximumFrequency)
        let binFrequency = sampleRate / Double(fftSize)

        for index in 0..<Self.barCount {
            let startProgress = Double(index) / Double(Self.barCount)
            let endProgress = Double(index + 1) / Double(Self.barCount)
            let startFrequency = pow(10, minLog + (maxLog - minLog) * startProgress)
            let endFrequency = pow(10, minLog + (maxLog - minLog) * endProgress)

            let startBin = max(1, min((fftSize / 2) - 1, Int(startFrequency / binFrequency)))
            let endBin = max(startBin + 1, min(fftSize / 2, Int(ceil(endFrequency / binFrequency))))
            binRanges.append((start: startBin, end: endBin))
        }
    }
}
