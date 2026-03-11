import SwiftUI
import PhotosUI
import Photos
import AVKit

enum ProcessMode: String, CaseIterable {
	case image = "图片"
	case video = "视频"
}

struct ContentView: View {
	@State private var processMode: ProcessMode = .image

	// 图片相关状态
	@State private var selectedImageItem: PhotosPickerItem?
	@State private var originalImage: UIImage?
	@State private var originalImageSizeKB: Int = 0
	@State private var compressedImageData: Data?
	@State private var targetImageSizeKB: String = "1024"
	@State private var selectedImageFormat: ImageFormat = .jpeg

	// 视频相关状态
	@State private var selectedVideoItem: PhotosPickerItem?
	@State private var originalVideoURL: URL?
	@State private var originalVideoSizeMB: Double = 0
	@State private var compressedVideoURL: URL?
	@State private var compressedVideoSizeMB: Double = 0
	@State private var targetVideoSizeMB: String = "10"
	@State private var videoProgress: Double = 0
	@State private var isCompressingVideo: Bool = false
	@State private var isLoadingVideo: Bool = false

	// 共用状态
	@State private var statusMessage: String = ""
	@State private var showFormatInfo: Bool = false
	@FocusState private var isInputFocused: Bool

	var body: some View {
		NavigationStack {
			VStack(spacing: 20) {
				// 模式切换
				Picker("处理模式", selection: $processMode) {
					ForEach(ProcessMode.allCases, id: \.self) { mode in
						Text(mode.rawValue).tag(mode)
					}
				}
				.pickerStyle(.segmented)
				.onChange(of: processMode) {
					statusMessage = ""
				}

				if processMode == .image {
					imageView
				} else {
					videoView
				}

				Spacer()
			}
			.padding()
			.navigationTitle(processMode == .image ? "图片压缩" : "视频压缩")
			.sheet(isPresented: $showFormatInfo) {
				FormatInfoView(mode: processMode)
			}
			.toolbar {
				ToolbarItemGroup(placement: .keyboard) {
					Spacer()
					Button("完成") {
						isInputFocused = false
					}
				}
			}
		}
	}

	// MARK: - 图片模式

	private var imageView: some View {
		VStack(spacing: 20) {
			// 图片预览
			if let img = originalImage {
				Image(uiImage: img)
					.resizable()
					.scaledToFit()
					.frame(maxHeight: 300)
					.cornerRadius(12)

				Text("原始大小: \(originalImageSizeKB) KB")
					.foregroundColor(.secondary)
			} else {
				placeholderView(text: "还没有选择图片")
			}

			// 选择图片
			PhotosPicker(selection: $selectedImageItem, matching: .images) {
				Label("选择图片", systemImage: "photo.on.rectangle")
					.font(.headline)
					.padding()
					.frame(maxWidth: .infinity)
					.background(Color.blue)
					.foregroundColor(.white)
					.cornerRadius(10)
			}
			.onChange(of: selectedImageItem) {
				loadImage()
			}

			// 格式选择
			HStack {
				Text("输出格式:")
				Picker("格式", selection: $selectedImageFormat) {
					ForEach(ImageFormat.allCases, id: \.self) { format in
						Text(format.rawValue).tag(format)
					}
				}
				.pickerStyle(.segmented)

				Button {
					showFormatInfo = true
				} label: {
					Image(systemName: "info.circle")
						.font(.title3)
						.foregroundColor(.blue)
				}
			}

			// 目标大小
			HStack {
				Text("目标大小 (KB):")
				TextField("1024", text: $targetImageSizeKB)
					.textFieldStyle(.roundedBorder)
					.keyboardType(.numberPad)
					.focused($isInputFocused)
					.frame(width: 100)
			}

			// 压缩按钮
			Button {
				compressImage()
			} label: {
				Label("开始压缩", systemImage: "arrow.down.circle")
					.font(.headline)
					.padding()
					.frame(maxWidth: .infinity)
					.background(originalImage != nil ? Color.green : Color.gray)
					.foregroundColor(.white)
					.cornerRadius(10)
			}
			.disabled(originalImage == nil)

			// 保存按钮
			if compressedImageData != nil {
				Button {
					saveImage()
				} label: {
					Label("保存到相册", systemImage: "square.and.arrow.down")
						.font(.headline)
						.padding()
						.frame(maxWidth: .infinity)
						.background(Color.orange)
						.foregroundColor(.white)
						.cornerRadius(10)
				}
			}

			statusMessageView
		}
	}

	// MARK: - 视频模式

	private var videoView: some View {
		VStack(spacing: 20) {
			// 视频预览
			if isLoadingVideo {
				RoundedRectangle(cornerRadius: 12)
					.fill(Color.gray.opacity(0.2))
					.frame(height: 250)
					.overlay(
						VStack(spacing: 12) {
							ProgressView()
								.scaleEffect(1.5)
							Text("正在加载视频...")
								.foregroundColor(.gray)
						}
					)
			} else if let url = originalVideoURL {
				VideoPlayer(player: AVPlayer(url: url))
					.frame(height: 250)
					.cornerRadius(12)

				Text(String(format: "原始大小: %.2f MB", originalVideoSizeMB))
					.foregroundColor(.secondary)
			} else {
				placeholderView(text: "还没有选择视频")
			}

			// 选择视频
			PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
				Label("选择视频", systemImage: "video.badge.plus")
					.font(.headline)
					.padding()
					.frame(maxWidth: .infinity)
					.background(Color.blue)
					.foregroundColor(.white)
					.cornerRadius(10)
			}
			.onChange(of: selectedVideoItem) {
				loadVideo()
			}

			// 格式 + 说明
			HStack {
				Text("输出格式: HEVC (H.265)")
					.foregroundColor(.secondary)
				Spacer()
				Button {
					showFormatInfo = true
				} label: {
					Image(systemName: "info.circle")
						.font(.title3)
						.foregroundColor(.blue)
				}
			}

			// 目标大小
			HStack {
				Text("目标大小 (MB):")
				TextField("10", text: $targetVideoSizeMB)
					.textFieldStyle(.roundedBorder)
					.keyboardType(.decimalPad)
					.focused($isInputFocused)
					.frame(width: 100)
			}

			// 压缩进度
			if isCompressingVideo {
				VStack(spacing: 8) {
					ProgressView(value: videoProgress)
						.progressViewStyle(.linear)
					Text(String(format: "压缩中... %.0f%%", videoProgress * 100))
						.font(.callout)
						.foregroundColor(.secondary)
				}
			}

			// 压缩按钮
			Button {
				compressVideo()
			} label: {
				Label(isCompressingVideo ? "压缩中..." : "开始压缩", systemImage: "arrow.down.circle")
					.font(.headline)
					.padding()
					.frame(maxWidth: .infinity)
					.background(originalVideoURL != nil && !isCompressingVideo ? Color.green : Color.gray)
					.foregroundColor(.white)
					.cornerRadius(10)
			}
			.disabled(originalVideoURL == nil || isCompressingVideo)

			// 保存按钮
			if compressedVideoURL != nil {
				Button {
					saveVideo()
				} label: {
					Label("保存到相册", systemImage: "square.and.arrow.down")
						.font(.headline)
						.padding()
						.frame(maxWidth: .infinity)
						.background(Color.orange)
						.foregroundColor(.white)
						.cornerRadius(10)
				}
			}

			statusMessageView
		}
	}

	// MARK: - 共用组件

	private func placeholderView(text: String) -> some View {
		RoundedRectangle(cornerRadius: 12)
			.fill(Color.gray.opacity(0.2))
			.frame(height: 200)
			.overlay(
				Text(text)
					.foregroundColor(.gray)
			)
	}

	@ViewBuilder
	private var statusMessageView: some View {
		if !statusMessage.isEmpty {
			Text(statusMessage)
				.font(.callout)
				.foregroundColor(.blue)
				.padding()
				.frame(maxWidth: .infinity)
				.background(Color.blue.opacity(0.1))
				.cornerRadius(8)
		}
	}

	// MARK: - 图片操作

	private func loadImage() {
		Task {
			if let data = try? await selectedImageItem?.loadTransferable(type: Data.self),
			   let img = UIImage(data: data) {
				originalImage = img
				originalImageSizeKB = data.count / 1024
				compressedImageData = nil
				statusMessage = ""
			}
		}
	}

	private func compressImage() {
		guard let image = originalImage,
			  let target = Int(targetImageSizeKB) else { return }

		let targetBytes = target * 1024

		switch selectedImageFormat {
		case .jpeg:
			if let data = ImageCompressor.compressAsJPEG(image: image, targetBytes: targetBytes) {
				compressedImageData = data
				statusMessage = "✅ 压缩完成 (JPEG)！\(originalImageSizeKB) KB → \(data.count / 1024) KB"
			}
		case .png:
			if let data = ImageCompressor.compressAsPNG(image: image, targetBytes: targetBytes) {
				compressedImageData = data
				let isUnchanged = data.count / 1024 >= originalImageSizeKB
				statusMessage = isUnchanged
					? "✅ 无需压缩！PNG 原始大小已满足目标"
					: "✅ 压缩完成 (PNG)！\(originalImageSizeKB) KB → \(data.count / 1024) KB"
			}
		}
	}

	private func saveImage() {
		guard let data = compressedImageData else { return }

		PHPhotoLibrary.shared().performChanges({
			let request = PHAssetCreationRequest.forAsset()
			request.addResource(with: .photo, data: data, options: nil)
		}) { success, error in
			DispatchQueue.main.async {
				if success {
					statusMessage = "✅ 已保存到相册！大小: \(data.count / 1024) KB"
				} else {
					statusMessage = "❌ 保存失败: \(error?.localizedDescription ?? "未知错误")"
				}
			}
		}
	}

	// MARK: - 视频操作

	private func loadVideo() {
		Task {
			guard let item = selectedVideoItem else { return }
			isLoadingVideo = true
			statusMessage = ""
			compressedVideoURL = nil
			originalVideoURL = nil
			// 将视频导出到临时文件
			if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
				originalVideoURL = movie.url
				let attrs = try? FileManager.default.attributesOfItem(atPath: movie.url.path)
				let size = attrs?[.size] as? Int64 ?? 0
				originalVideoSizeMB = Double(size) / (1024.0 * 1024.0)
				videoProgress = 0
			} else {
				statusMessage = "❌ 视频加载失败"
			}
			isLoadingVideo = false
		}
	}

	private func compressVideo() {
		guard let sourceURL = originalVideoURL,
			  let targetMB = Double(targetVideoSizeMB) else { return }

		isCompressingVideo = true
		videoProgress = 0
		statusMessage = ""

		Task {
			do {
				let result = try await VideoCompressor.compressAsHEVC(
					sourceURL: sourceURL,
					targetSizeMB: targetMB,
					progress: { p in
						videoProgress = p
					}
				)
				compressedVideoURL = result.outputURL
				compressedVideoSizeMB = result.compressedSizeMB
				statusMessage = String(
					format: "✅ 压缩完成 (HEVC)！%.2f MB → %.2f MB",
					result.originalSizeMB, result.compressedSizeMB
				)
			} catch {
				statusMessage = "❌ 压缩失败: \(error.localizedDescription)"
			}
			isCompressingVideo = false
		}
	}

	private func saveVideo() {
		guard let url = compressedVideoURL else { return }

		PHPhotoLibrary.shared().performChanges({
			let request = PHAssetCreationRequest.forAsset()
			let options = PHAssetResourceCreationOptions()
			options.shouldMoveFile = false
			request.addResource(with: .video, fileURL: url, options: options)
		}) { success, error in
			DispatchQueue.main.async {
				if success {
					statusMessage = String(format: "✅ 已保存到相册！大小: %.2f MB", compressedVideoSizeMB)
				} else {
					statusMessage = "❌ 保存失败: \(error?.localizedDescription ?? "未知错误")"
				}
			}
		}
	}
}

// MARK: - 视频文件传输类型

struct VideoTransferable: Transferable {
	let url: URL

	static var transferRepresentation: some TransferRepresentation {
		FileRepresentation(contentType: .movie) { movie in
			SentTransferredFile(movie.url)
		} importing: { received in
			let tempURL = FileManager.default.temporaryDirectory
				.appendingPathComponent(UUID().uuidString)
				.appendingPathExtension("mov")
			try FileManager.default.copyItem(at: received.file, to: tempURL)
			return Self(url: tempURL)
		}
	}
}

// MARK: - 格式说明弹窗

struct FormatInfoView: View {
	@Environment(\.dismiss) var dismiss
	var mode: ProcessMode = .image

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					if mode == .image {
						imageFormatInfo
					} else {
						videoFormatInfo
					}
				}
				.padding()
			}
			.navigationTitle("格式说明")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button("关闭") {
						dismiss()
					}
				}
			}
		}
	}

	private var imageFormatInfo: some View {
		VStack(alignment: .leading, spacing: 20) {
			VStack(alignment: .leading, spacing: 8) {
				Label("JPEG", systemImage: "photo")
					.font(.title2)
					.fontWeight(.bold)

				Text("JPEG 是最常见的图片格式，采用有损压缩。通过丢弃人眼不太敏感的细节来大幅减小文件体积。")

				VStack(alignment: .leading, spacing: 4) {
					Label("压缩率高，文件小", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
					Label("适合照片、风景等色彩丰富的图片", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
					Label("不支持透明背景", systemImage: "xmark.circle.fill")
						.foregroundColor(.red)
					Label("每次保存都会损失一点画质", systemImage: "xmark.circle.fill")
						.foregroundColor(.red)
				}
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.orange.opacity(0.1))
			.cornerRadius(12)

			VStack(alignment: .leading, spacing: 8) {
				Label("PNG", systemImage: "photo.artframe")
					.font(.title2)
					.fontWeight(.bold)

				Text("PNG 采用无损压缩，不会丢失画质。要缩小文件体积，只能通过降低分辨率（缩小尺寸）来实现。")

				VStack(alignment: .leading, spacing: 4) {
					Label("画质无损，保存多少次都不会变糊", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
					Label("支持透明背景", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
					Label("适合图标、Logo、截图", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
					Label("同等画质下文件比 JPEG 大很多", systemImage: "xmark.circle.fill")
						.foregroundColor(.red)
				}
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.blue.opacity(0.1))
			.cornerRadius(12)

			VStack(alignment: .leading, spacing: 8) {
				Label("如何选择？", systemImage: "questionmark.circle")
					.font(.title2)
					.fontWeight(.bold)

				Text("手机拍的照片选 JPEG，带透明背景或需要保留像素细节的图选 PNG。")
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.green.opacity(0.1))
			.cornerRadius(12)
		}
	}

	private var videoFormatInfo: some View {
		VStack(alignment: .leading, spacing: 20) {
			VStack(alignment: .leading, spacing: 8) {
				Label("HEVC (H.265)", systemImage: "video")
					.font(.title2)
					.fontWeight(.bold)

				Text("HEVC（高效视频编码）是目前最先进的视频压缩标准之一。相比 H.264，在同等画质下可以减少约 50% 的文件体积。")

				VStack(alignment: .leading, spacing: 4) {
					Label("压缩效率极高，文件体积小", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
					Label("iPhone 7 及以上设备硬件加速", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
					Label("iOS 原生支持播放", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
					Label("部分老旧设备/平台可能不支持播放", systemImage: "xmark.circle.fill")
						.foregroundColor(.red)
				}
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.purple.opacity(0.1))
			.cornerRadius(12)

			VStack(alignment: .leading, spacing: 8) {
				Label("使用建议", systemImage: "lightbulb")
					.font(.title2)
					.fontWeight(.bold)

				VStack(alignment: .leading, spacing: 8) {
					Text("• 目标大小设置过小可能导致画面模糊，建议不低于原始大小的 20%")
					Text("• 压缩时间取决于视频时长和分辨率，请耐心等待")
					Text("• 音频会以 AAC 128kbps 编码，基本无损")
				}
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.green.opacity(0.1))
			.cornerRadius(12)
		}
	}
}

#Preview {
	ContentView()
}
