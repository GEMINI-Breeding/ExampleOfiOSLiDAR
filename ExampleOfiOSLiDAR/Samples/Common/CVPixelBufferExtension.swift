/// Copyright (c) 2020 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import AVFoundation
import UIKit

extension CVPixelBuffer {
  func normalize() {
    let width = CVPixelBufferGetWidth(self)
    let height = CVPixelBufferGetHeight(self)
    
    CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
    let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(self), to: UnsafeMutablePointer<Float>.self)
    
    var minPixel: Float = 1.0
    var maxPixel: Float = 0.0
    
    /// You might be wondering why the for loops below use `stride(from:to:step:)`
    /// instead of a simple `Range` such as `0 ..< height`?
    /// The answer is because in Swift 5.1, the iteration of ranges performs badly when the
    /// compiler optimisation level (`SWIFT_OPTIMIZATION_LEVEL`) is set to `-Onone`,
    /// which is eactly what happens when running this sample project in Debug mode.
    /// If this was a production app then it might not be worth worrying about but it is still
    /// worth being aware of.
    
    for y in stride(from: 0, to: height, by: 1) {
      for x in stride(from: 0, to: width, by: 1) {
        let pixel = floatBuffer[y * width + x]
        minPixel = min(pixel, minPixel)
        maxPixel = max(pixel, maxPixel)
      }
    }
    
      
    let range = maxPixel - minPixel
    for y in stride(from: 0, to: height, by: 1) {
      for x in stride(from: 0, to: width, by: 1) {
        let pixel = floatBuffer[y * width + x]
        floatBuffer[y * width + x] = (pixel - minPixel) / range
      }
    }
    
    CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
  }
    
    func rescale(minPixel : Float, maxPixel : Float) {
      let width = CVPixelBufferGetWidth(self)
      let height = CVPixelBufferGetHeight(self)
      
      CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
      let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(self), to: UnsafeMutablePointer<Float>.self)
      


      let range = maxPixel - minPixel
        

      for y in stride(from: 0, to: height, by: 1) {
        for x in stride(from: 0, to: width, by: 1) {
          let pixel = floatBuffer[y * width + x]
          floatBuffer[y * width + x] = (pixel - minPixel) / range
        }
      }
      
      CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
    }
}

public extension CVPixelBuffer {
    
    func copy() throws -> CVPixelBuffer {
        precondition(CFGetTypeID(self) == CVPixelBufferGetTypeID(), "copy() cannot be called on a non-CVPixelBuffer")

        var _copy: CVPixelBuffer?

        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let formatType = CVPixelBufferGetPixelFormatType(self)
        let attachments = CVBufferGetAttachments(self, .shouldPropagate)

        CVPixelBufferCreate(nil, width, height, formatType, attachments, &_copy)

        let copy = _copy!

        CVPixelBufferLockBaseAddress(self, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])

        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
        }

        let pixelBufferPlaneCount: Int = CVPixelBufferGetPlaneCount(self)


        if pixelBufferPlaneCount == 0 {
            let dest = CVPixelBufferGetBaseAddress(copy)
            let source = CVPixelBufferGetBaseAddress(self)
            let height = CVPixelBufferGetHeight(self)
            let bytesPerRowSrc = CVPixelBufferGetBytesPerRow(self)
            let bytesPerRowDest = CVPixelBufferGetBytesPerRow(copy)
            if bytesPerRowSrc == bytesPerRowDest {
                memcpy(dest, source, height * bytesPerRowSrc)
            }else {
                var startOfRowSrc = source
                var startOfRowDest = dest
                for _ in 0..<height {
                    memcpy(startOfRowDest, startOfRowSrc, min(bytesPerRowSrc, bytesPerRowDest))
                    startOfRowSrc = startOfRowSrc?.advanced(by: bytesPerRowSrc)
                    startOfRowDest = startOfRowDest?.advanced(by: bytesPerRowDest)
                }
            }

        }else {
            for plane in 0 ..< pixelBufferPlaneCount {
                let dest        = CVPixelBufferGetBaseAddressOfPlane(copy, plane)
                let source      = CVPixelBufferGetBaseAddressOfPlane(self, plane)
                let height      = CVPixelBufferGetHeightOfPlane(self, plane)
                let bytesPerRowSrc = CVPixelBufferGetBytesPerRowOfPlane(self, plane)
                let bytesPerRowDest = CVPixelBufferGetBytesPerRowOfPlane(copy, plane)

                if bytesPerRowSrc == bytesPerRowDest {
                    memcpy(dest, source, height * bytesPerRowSrc)
                }else {
                    var startOfRowSrc = source
                    var startOfRowDest = dest
                    for _ in 0..<height {
                        memcpy(startOfRowDest, startOfRowSrc, min(bytesPerRowSrc, bytesPerRowDest))
                        startOfRowSrc = startOfRowSrc?.advanced(by: bytesPerRowSrc)
                        startOfRowDest = startOfRowDest?.advanced(by: bytesPerRowDest)
                    }
                }
            }
        }
        return copy
    }
}


extension UIImage {
    func scalePreservingAspectRatio(targetSize: CGSize) -> UIImage {
        // Determine the scale factor that preserves aspect ratio
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        
        let scaleFactor = min(widthRatio, heightRatio)
        
        // Compute the new image size that preserves aspect ratio
        let scaledImageSize = CGSize(
            width: size.width * scaleFactor,
            height: size.height * scaleFactor
        )

        // Draw and return the resized UIImage
        let renderer = UIGraphicsImageRenderer(
            size: scaledImageSize
        )

        let scaledImage = renderer.image { _ in
            self.draw(in: CGRect(
                origin: .zero,
                size: scaledImageSize
            ))
        }
        
        return scaledImage
    }
}
