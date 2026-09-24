import AVFoundation

nonisolated enum WaveformAnalyzer {
  static let analysisSampleRate: Double = 8_000

  @concurrent static func levels(of url: URL, count: Int = Waveform.sampleCount) async throws -> [Float] {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    let duration = try await asset.load(.duration).seconds

    guard !tracks.isEmpty, duration.isFinite, duration > 0 else {
      return []
    }

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: analysisSampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    output.alwaysCopiesSampleData = false
    reader.add(output)

    guard reader.startReading() else {
      throw reader.error ?? AudioError(message: "That audio could not be analysed.")
    }

    let bucketCount = max(1, count)
    let totalFrames = max(1, duration * analysisSampleRate)
    var sums = Array(repeating: Double(0), count: bucketCount)
    var counts = Array(repeating: 0, count: bucketCount)
    var frameIndex = 0

    while let sampleBuffer = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

      let length = CMBlockBufferGetDataLength(block)
      var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)

      samples.withUnsafeMutableBytes { raw in
        _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
      }

      for sample in samples {
        let bucket = min(bucketCount - 1, Int(Double(frameIndex) / totalFrames * Double(bucketCount)))
        sums[bucket] += Double(sample * sample)
        counts[bucket] += 1
        frameIndex += 1
      }
    }

    return (0..<bucketCount).map { index in
      guard counts[index] > 0 else { return 0 }
      return Waveform.normalize(rms: Float((sums[index] / Double(counts[index])).squareRoot()))
    }
  }
}
