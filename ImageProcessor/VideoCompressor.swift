@preconcurrency import AVFoundation
import VideoToolbox
import UIKit

struct VideoCompressor {

	struct Result {
		let outputURL: URL
		let originalSizeMB: Double
		let compressedSizeMB: Double
	}

	/// 压缩视频为 HEVC 格式，通过目标文件大小(MB)控制码率
	/// - Parameters:
	///   - sourceURL: 源视频路径
	///   - targetSizeMB: 目标文件大小（MB）
	///   - progress: 进度回调 (0.0 ~ 1.0)
	/// - Returns: 压缩结果
	static func compressAsHEVC(
		sourceURL: URL,
		targetSizeMB: Double,
		progress: @escaping (Double) -> Void
	) async throws -> Result {
		let asset = AVURLAsset(url: sourceURL)

		let duration = try await asset.load(.duration)
		let durationSeconds = CMTimeGetSeconds(duration)
		guard durationSeconds > 0 else {
			throw CompressorError.invalidVideo
		}

		let originalSize = fileSize(at: sourceURL)
		let originalSizeMB = Double(originalSize) / (1024.0 * 1024.0)

		// 计算目标码率 (bps)
		// 目标大小(bytes) = targetSizeMB * 1024 * 1024
		// 码率(bps) = 目标大小(bytes) * 8 / 时长(秒)
		// 预留 5% 给音频和容器开销
		let targetBytes = targetSizeMB * 1024.0 * 1024.0
		let targetBitRate = Int(targetBytes * 8.0 * 0.95 / durationSeconds)

		// 获取源视频的视频轨道信息
		guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
			throw CompressorError.noVideoTrack
		}

		let naturalSize = try await videoTrack.load(.naturalSize)
		let transform = try await videoTrack.load(.preferredTransform)
		let correctedSize = naturalSize.applying(transform)
		let videoWidth = abs(correctedSize.width)
		let videoHeight = abs(correctedSize.height)

		// 输出路径
		let outputURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathExtension("mov")

		// 配置 AVAssetWriter
		let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

		// 视频输出设置 - HEVC 编码
		let videoSettings: [String: Any] = [
			AVVideoCodecKey: AVVideoCodecType.hevc,
			AVVideoWidthKey: videoWidth,
			AVVideoHeightKey: videoHeight,
			AVVideoCompressionPropertiesKey: [
				AVVideoAverageBitRateKey: targetBitRate,
				AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
			]
		]
		let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
		videoInput.transform = transform
		videoInput.expectsMediaDataInRealTime = false

		guard writer.canAdd(videoInput) else {
			throw CompressorError.cannotAddInput
		}
		writer.add(videoInput)

		// 音频输出设置 - AAC 编码
		var audioInput: AVAssetWriterInput?
		if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
			let audioSettings: [String: Any] = [
				AVFormatIDKey: kAudioFormatMPEG4AAC,
				AVNumberOfChannelsKey: 2,
				AVSampleRateKey: 44100,
				AVEncoderBitRateKey: 128_000,
			]
			let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
			input.expectsMediaDataInRealTime = false
			if writer.canAdd(input) {
				writer.add(input)
				audioInput = input
			}
		}

		// 配置 AVAssetReader
		let reader = try AVAssetReader(asset: asset)

		let videoOutput = AVAssetReaderTrackOutput(
			track: videoTrack,
			outputSettings: [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
			]
		)
		videoOutput.alwaysCopiesSampleData = false
		guard reader.canAdd(videoOutput) else {
			throw CompressorError.cannotAddOutput
		}
		reader.add(videoOutput)

		var audioOutput: AVAssetReaderTrackOutput?
		if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
			let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
			output.alwaysCopiesSampleData = false
			if reader.canAdd(output) {
				reader.add(output)
				audioOutput = output
			}
		}

		// 开始读写
		reader.startReading()
		writer.startWriting()
		writer.startSession(atSourceTime: .zero)

		// 写入视频数据
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video.queue")) {
				while videoInput.isReadyForMoreMediaData {
					if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
						let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
						let currentProgress = CMTimeGetSeconds(pts) / durationSeconds
						DispatchQueue.main.async {
							progress(min(currentProgress, 1.0))
						}
						videoInput.append(sampleBuffer)
					} else {
						videoInput.markAsFinished()
						continuation.resume()
						return
					}
				}
			}
		}

		// 写入音频数据
		if let audioInput = audioInput, let audioOutput = audioOutput {
			await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
				audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.queue")) {
					while audioInput.isReadyForMoreMediaData {
						if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
							audioInput.append(sampleBuffer)
						} else {
							audioInput.markAsFinished()
							continuation.resume()
							return
						}
					}
				}
			}
		}

		// 完成写入
		await writer.finishWriting()

		guard writer.status == .completed else {
			throw writer.error ?? CompressorError.writeFailed
		}

		let compressedSize = fileSize(at: outputURL)
		let compressedSizeMB = Double(compressedSize) / (1024.0 * 1024.0)

		return Result(
			outputURL: outputURL,
			originalSizeMB: originalSizeMB,
			compressedSizeMB: compressedSizeMB
		)
	}

	private static func fileSize(at url: URL) -> Int64 {
		(try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
	}

	enum CompressorError: LocalizedError {
		case invalidVideo
		case noVideoTrack
		case cannotAddInput
		case cannotAddOutput
		case writeFailed

		var errorDescription: String? {
			switch self {
			case .invalidVideo: return "无效的视频文件"
			case .noVideoTrack: return "视频中没有找到视频轨道"
			case .cannotAddInput: return "无法添加写入通道"
			case .cannotAddOutput: return "无法添加读取通道"
			case .writeFailed: return "视频写入失败"
			}
		}
	}
}
