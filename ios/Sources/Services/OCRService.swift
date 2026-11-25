import Vision
import UIKit

final class OCRService {
    static let shared = OCRService()

    private init() {}

    func recognizeText(in image: UIImage, regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), completion: @escaping (Result<[String], Error>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(OCRError.invalidImage))
            return
        }

        let request = makeTextRequest(regionOfInterest: regionOfInterest, completion: completion)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func recognizeText(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right,
        regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let request = makeTextRequest(regionOfInterest: regionOfInterest, completion: completion)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func makeTextRequest(regionOfInterest: CGRect, completion: @escaping (Result<[String], Error>) -> Void) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    completion(.success([]))
                }
                return
            }

            let texts: [String] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.35 else {
                    return nil
                }
                return candidate.string
            }

            DispatchQueue.main.async {
                completion(.success(texts))
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.regionOfInterest = regionOfInterest.clampedForVision
        return request
    }
}

enum OCRError: Error {
    case invalidImage
    case recognitionFailed
}

private extension CGRect {
    var clampedForVision: CGRect {
        let minX = max(0, min(origin.x, 1))
        let minY = max(0, min(origin.y, 1))
        let maxX = max(minX, min(origin.x + width, 1))
        let maxY = max(minY, min(origin.y + height, 1))

        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return rect.width > 0.01 && rect.height > 0.01 ? rect : CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}
