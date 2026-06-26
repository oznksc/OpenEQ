//
//  SpectrumAnalyzer.swift
//  OpenEQ
//
//  Created by Antigravity on 26.06.2026.
//

import Foundation
import Accelerate
import AVFoundation

final class SpectrumAnalyzer {
    private let fftSize: Int = 1024
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    
    private var window: [Float]
    private var previousLevels: [Float]
    
    // Statically allocated buffers to prevent real-time memory allocations
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    
    init() {
        self.log2n = vDSP_Length(10) // log2(1024) = 10
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        
        self.window = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        self.previousLevels = [Float](repeating: 0.0, count: 64)
        
        self.realBuffer = [Float](repeating: 0.0, count: fftSize / 2)
        self.imagBuffer = [Float](repeating: 0.0, count: fftSize / 2)
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    /// Analyzes the PCM buffer and returns 64 normalized frequency levels (0.0 to 1.0)
    func analyze(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let frameLength = Int(buffer.frameLength)
        
        // We require at least 1024 samples to perform the transform
        guard frameLength >= fftSize else { return [] }
        
        // 1. Copy samples and apply the Hanning window
        var windowedSamples = [Float](repeating: 0.0, count: fftSize)
        vDSP_vmul(channelData, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))
        
        var magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
        
        // 2. Perform raw vDSP FFT
        realBuffer.withUnsafeMutableBufferPointer { rPtr in
            imagBuffer.withUnsafeMutableBufferPointer { iPtr in
                var splitComplex = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                
                // Pack real samples into split complex representation
                windowedSamples.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }
                
                // Perform Forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                
                // Calculate magnitudes squared
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        // Scale magnitudes: forward FFT scales output by 2, power spectrum is magnitudes / N
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))
        
        // 3. Bin the 512 bins into 64 visual frequency bars
        let numBars = 64
        var bars = [Float](repeating: 0.0, count: numBars)
        let binsPerBar = (fftSize / 2) / numBars // 512 / 64 = 8 bins per bar
        
        for i in 0..<numBars {
            var sum: Float = 0.0
            for j in 0..<binsPerBar {
                sum += magnitudes[i * binsPerBar + j]
            }
            let avg = sum / Float(binsPerBar)
            
            // Convert to decibels (dB = 10 * log10(Power))
            let db = 10 * log10(avg + 1e-9)
            
            // Map decibel range [-60 dB, -5 dB] to normalized [0.0, 1.0] range
            let minDb: Float = -60.0
            let maxDb: Float = -5.0
            let normalized = max(0.0, min(1.0, (db - minDb) / (maxDb - minDb)))
            
            // Apply exponential decay filter to smooth out transitions (60% history, 40% current)
            let smoothed = (normalized * 0.4) + (previousLevels[i] * 0.6)
            bars[i] = smoothed
            previousLevels[i] = smoothed
        }
        
        return bars
    }
}
