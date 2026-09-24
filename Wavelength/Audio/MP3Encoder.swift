import AVFoundation
import LAME

nonisolated enum MP3Encoder {
  static let bitRateKbps: Int32 = 128
  static let sampleRate: Int32 = 44_100

  static func encode(_ input: URL, to output: URL) async throws {
    let asset = AVURLAsset(url: input)

    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      throw AudioError(message: "The episode does not contain an audio track.")
    }

    try await Task.detached(priority: .userInitiated) {
      try encode(asset: asset, track: track, to: output)
    }.value
  }

  private static func encode(asset: AVURLAsset, track: AVAssetTrack, to output: URL) throws {
    let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsNonInterleaved: false,
      AVNumberOfChannelsKey: 1,
      AVSampleRateKey: sampleRate,
    ])
    trackOutput.alwaysCopiesSampleData = false

    let reader = try AVAssetReader(asset: asset)

    guard reader.canAdd(trackOutput) else {
      throw AudioError(message: "The episode audio could not be decoded.")
    }

    reader.add(trackOutput)

    guard reader.startReading() else {
      throw AudioError(message: "The episode audio could not be opened.")
    }

    try? FileManager.default.removeItem(at: output)

    guard FileManager.default.createFile(atPath: output.path, contents: nil),
          let file = fopen(output.path, "wb+") else {
      reader.cancelReading()
      throw AudioError(message: "The MP3 output file could not be created.")
    }

    defer { fclose(file) }

    guard let encoder = lame_init() else {
      reader.cancelReading()
      throw AudioError(message: "The MP3 encoder could not be initialized.")
    }

    defer { lame_close(encoder) }

    lame_set_num_channels(encoder, 1)
    lame_set_in_samplerate(encoder, sampleRate)
    lame_set_out_samplerate(encoder, sampleRate)
    lame_set_mode(encoder, MONO)
    lame_set_VBR(encoder, vbr_off)
    lame_set_brate(encoder, bitRateKbps)
    lame_set_quality(encoder, 2)

    guard lame_init_params(encoder) >= 0 else {
      reader.cancelReading()
      throw AudioError(message: "The MP3 encoder could not be initialized.")
    }

    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
      try encode(sampleBuffer, with: encoder, to: file)
    }

    guard reader.status == .completed else {
      throw reader.error ?? AudioError(message: "The episode audio could not be decoded.")
    }

    var flush = [UInt8](repeating: 0, count: 7_200)
    let flushed = lame_encode_flush(encoder, &flush, Int32(flush.count))

    guard flushed >= 0 else {
      throw AudioError(message: "The episode audio could not be encoded as MP3.")
    }

    if flushed > 0, fwrite(flush, 1, Int(flushed), file) != Int(flushed) {
      throw AudioError(message: "The MP3 output file could not be written.")
    }

    fflush(file)
    lame_mp3_tags_fid(encoder, file)
  }

  private static func encode(_ sampleBuffer: CMSampleBuffer, with encoder: OpaquePointer, to file: UnsafeMutablePointer<FILE>) throws {
    guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      throw AudioError(message: "The episode audio could not be decoded.")
    }

    let byteCount = CMBlockBufferGetDataLength(block)

    guard byteCount > 0 else { return }

    let sampleCount = byteCount / MemoryLayout<Int16>.size
    var samples = [Int16](repeating: 0, count: sampleCount)
    let status = samples.withUnsafeMutableBytes { buffer in
      CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: buffer.baseAddress!)
    }

    guard status == kCMBlockBufferNoErr else {
      throw AudioError(message: "The episode audio could not be decoded.")
    }

    var mp3 = [UInt8](repeating: 0, count: Int(1.25 * Double(sampleCount)) + 7_200)
    let encoded = samples.withUnsafeMutableBufferPointer { pcm in
      lame_encode_buffer(encoder, pcm.baseAddress, pcm.baseAddress, Int32(sampleCount), &mp3, Int32(mp3.count))
    }

    guard encoded >= 0 else {
      throw AudioError(message: "The episode audio could not be encoded as MP3.")
    }

    if encoded > 0, fwrite(mp3, 1, Int(encoded), file) != Int(encoded) {
      throw AudioError(message: "The MP3 output file could not be written.")
    }
  }
}
