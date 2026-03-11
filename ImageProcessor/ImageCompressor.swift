import UIKit

enum ImageFormat: String, CaseIterable {
	case jpeg = "JPEG"
	case png = "PNG"
}

struct ImageCompressor {

	/// JPEG 压缩：二分查找最佳质量，必要时缩小尺寸
	static func compressAsJPEG(image: UIImage, targetBytes: Int) -> Data? {
		guard let minData = image.jpegData(compressionQuality: 0.01) else { return nil }

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

		return bestData
	}

	/// PNG 压缩：无损格式，只能通过缩小尺寸来减小体积
	static func compressAsPNG(image: UIImage, targetBytes: Int) -> Data? {
		guard let initialData = image.pngData() else { return nil }

		if initialData.count <= targetBytes {
			return initialData
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

		return bestData
	}
}
