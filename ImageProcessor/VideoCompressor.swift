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
	static func compressAsHEVC(
		sourceURL: URL,
		targetSizeMB: Double,
		progress: @escaping @MainActor (Double) -> Void
	) async throws -> Result {
		let asset = AVURLAsset(url: sourceURL)

		let duration = try await asset.load(.duration)
		let durationSeconds = CMTimeGetSeconds(duration)
		guard durationSeconds > 0 else {
			throw CompressorError.invalidVideo
		}

		let originalSize = fileSize(at: sourceURL)
		let originalSizeMB = Double(originalSize) / (1024.0 * 1024.0)

		// 选择 HEVC 预设
		let presetName = AVAssetExportPresetHEVCHighestQuality
		guard await AVAssetExportSession.compatibility(ofExportPreset: presetName, with: asset, outputFileType: .mov) else {
			throw CompressorError.hevcNotSupported
		}

		guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
			throw CompressorError.cannotCreateExportSession
		}

		// 输出路径
		let outputURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathExtension("mov")

		exportSession.outputURL = outputURL
		exportSession.outputFileType = .mov
		exportSession.shouldOptimizeForNetworkUse = true

		// 通过 fileLengthLimit 控制目标大小
		let targetBytes = Int64(targetSizeMB * 1024.0 * 1024.0)
		exportSession.fileLengthLimit = targetBytes

		// 启动定时器轮询进度
		let progressTask = Task { @MainActor in
			while !Task.isCancelled {
				progress(Double(exportSession.progress))
				try? await Task.sleep(for: .milliseconds(200))
			}
		}

		// 执行导出
		await exportSession.export()

		// 停止进度轮询
		progressTask.cancel()
		await MainActor.run { progress(1.0) }

		// 检查结果
		switch exportSession.status {
		case .completed:
			let compressedSize = fileSize(at: outputURL)
			let compressedSizeMB = Double(compressedSize) / (1024.0 * 1024.0)
			return Result(
				outputURL: outputURL,
				originalSizeMB: originalSizeMB,
				compressedSizeMB: compressedSizeMB
			)
		case .failed:
			throw exportSession.error ?? CompressorError.writeFailed
		case .cancelled:
			throw CompressorError.cancelled
		default:
			throw CompressorError.writeFailed
		}
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
		case cancelled
		case hevcNotSupported
		case cannotCreateExportSession

		var errorDescription: String? {
			switch self {
			case .invalidVideo: return "无效的视频文件"
			case .noVideoTrack: return "视频中没有找到视频轨道"
			case .cannotAddInput: return "无法添加写入通道"
			case .cannotAddOutput: return "无法添加读取通道"
			case .writeFailed: return "视频写入失败"
			case .cancelled: return "压缩已取消"
			case .hevcNotSupported: return "此设备不支持 HEVC 编码"
			case .cannotCreateExportSession: return "无法创建导出会话"
			}
		}
	}
}
