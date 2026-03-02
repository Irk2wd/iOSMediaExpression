import SwiftUI
import PhotosUI
import Photos

enum ImageFormat: String, CaseIterable {
	case jpeg = "JPEG"
	case png = "PNG"
}

struct ContentView: View {
	@State private var selectedItem: PhotosPickerItem?
	@State private var originalImage: UIImage?
	@State private var originalSizeKB: Int = 0
	@State private var compressedData: Data?
	@State private var targetSizeKB: String = "1024"
	@State private var statusMessage: String = ""
	@State private var selectedFormat: ImageFormat = .jpeg
	@State private var showFormatInfo: Bool = false

	var body: some View {
		NavigationStack {
			VStack(spacing: 20) {

				// 图片预览区域
				if let img = originalImage {
					Image(uiImage: img)
						.resizable()
						.scaledToFit()
						.frame(maxHeight: 300)
						.cornerRadius(12)

					Text("原始大小: \(originalSizeKB) KB")
						.foregroundColor(.secondary)
				} else {
					RoundedRectangle(cornerRadius: 12)
						.fill(Color.gray.opacity(0.2))
						.frame(height: 200)
						.overlay(
							Text("还没有选择图片")
								.foregroundColor(.gray)
						)
				}

				// 选择图片按钮
				PhotosPicker(selection: $selectedItem, matching: .images) {
					Label("选择图片", systemImage: "photo.on.rectangle")
						.font(.headline)
						.padding()
						.frame(maxWidth: .infinity)
						.background(Color.blue)
						.foregroundColor(.white)
						.cornerRadius(10)
				}
				.onChange(of: selectedItem) {
					loadImage()
				}

				// 格式选择 + 提示按钮
				HStack {
					Text("输出格式:")
					Picker("格式", selection: $selectedFormat) {
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

				// 目标大小输入
				HStack {
					Text("目标大小 (KB):")
					TextField("1024", text: $targetSizeKB)
						.textFieldStyle(.roundedBorder)
						.keyboardType(.numberPad)
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
				if compressedData != nil {
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

				// 状态信息
				if !statusMessage.isEmpty {
					Text(statusMessage)
						.font(.callout)
						.foregroundColor(.blue)
						.padding()
						.frame(maxWidth: .infinity)
						.background(Color.blue.opacity(0.1))
						.cornerRadius(8)
				}

				Spacer()
			}
			.padding()
			.navigationTitle("图片压缩工具")
			.sheet(isPresented: $showFormatInfo) {
				FormatInfoView()
			}
		}
	}

	func loadImage() {
		Task {
			if let data = try? await selectedItem?.loadTransferable(type: Data.self),
			   let img = UIImage(data: data) {
				originalImage = img
				originalSizeKB = data.count / 1024
				compressedData = nil
				statusMessage = ""
			}
		}
	}

	func compressImage() {
		guard let image = originalImage,
			  let target = Int(targetSizeKB) else { return }

		let targetBytes = target * 1024

		switch selectedFormat {
		case .jpeg:
			compressAsJPEG(image: image, targetBytes: targetBytes)
		case .png:
			compressAsPNG(image: image, targetBytes: targetBytes)
		}
	}

	// JPEG 压缩：二分查找最佳质量，必要时缩小尺寸
	func compressAsJPEG(image: UIImage, targetBytes: Int) {
		guard let minData = image.jpegData(compressionQuality: 0.01) else { return }

		var workingImage = image
		if minData.count > targetBytes {
			let ratio = sqrt(Double(targetBytes) / Double(minData.count))
			let newSize = CGSize(
				width: image.size.width * ratio,
				height: image.size.height * ratio
			)
			let renderer = UIGraphicsImageRenderer(size: newSize)
			workingImage = renderer.image { _ in
				image.draw(in: CGRect(origin: .zero, size: newSize))
			}
		}

		var low: CGFloat = 0.0
		var high: CGFloat = 1.0
		var bestData = workingImage.jpegData(compressionQuality: low)!

		for _ in 0..<20 {
			let mid = (low + high) / 2.0
			guard let data = workingImage.jpegData(compressionQuality: mid) else { break }
			if data.count > targetBytes {
				high = mid
			} else {
				low = mid
				bestData = data
			}
		}

		compressedData = bestData
		statusMessage = "✅ 压缩完成 (JPEG)！\(originalSizeKB) KB → \(bestData.count / 1024) KB"
	}

	// PNG 压缩：无损格式，只能通过缩小尺寸来减小体积
	func compressAsPNG(image: UIImage, targetBytes: Int) {
		guard let initialData = image.pngData() else { return }

		if initialData.count <= targetBytes {
			compressedData = initialData
			statusMessage = "✅ 无需压缩！PNG 原始大小已满足目标"
			return
		}

		var low: CGFloat = 0.01
		var high: CGFloat = 1.0
		var bestData = initialData

		for _ in 0..<20 {
			let mid = (low + high) / 2.0
			let newSize = CGSize(
				width: image.size.width * mid,
				height: image.size.height * mid
			)
			let renderer = UIGraphicsImageRenderer(size: newSize)
			let resizedImage = renderer.image { _ in
				image.draw(in: CGRect(origin: .zero, size: newSize))
			}
			guard let data = resizedImage.pngData() else { break }

			if data.count > targetBytes {
				high = mid
			} else {
				low = mid
				bestData = data
			}
		}

		compressedData = bestData
		statusMessage = "✅ 压缩完成 (PNG)！\(originalSizeKB) KB → \(bestData.count / 1024) KB"
	}

	func saveImage() {
		guard let data = compressedData else { return }

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
}

// 格式说明弹窗
struct FormatInfoView: View {
	@Environment(\.dismiss) var dismiss

	var body: some View {
		NavigationStack {
			ScrollView {
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
}

#Preview {
	ContentView()
}
