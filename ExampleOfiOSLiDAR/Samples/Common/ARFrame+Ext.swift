//
//  ARFrame+Ext.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/01/14.
//

import ARKit
import UIKit

import CoreImage
import Accelerate.vImage

class EqualizationImageProcessorKernel: CIImageProcessorKernel {
    
    enum EqualizationImageProcessorError: Error {
        case equalizationOperationFailed
    }
    
    static var format = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        colorSpace: nil,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent)
    
    override class var outputFormat: CIFormat {
        return CIFormat.BGRA8
    }
    
    override class func formatForInput(at input: Int32) -> CIFormat {
        return CIFormat.L16
    }
    
    override class func process(with inputs: [CIImageProcessorInput]?,
                                arguments: [String: Any]?,
                                output: CIImageProcessorOutput) throws {
        
        guard
            let input = inputs?.first,
            let inputPixelBuffer = input.pixelBuffer,
            let outputPixelBuffer = output.pixelBuffer else {
                return
        }
        
        var sourceBuffer = vImage_Buffer()
        
        let inputCVImageFormat = vImageCVImageFormat_CreateWithCVPixelBuffer(inputPixelBuffer).takeRetainedValue()
        vImageCVImageFormat_SetColorSpace(inputCVImageFormat,
                                          CGColorSpaceCreateDeviceRGB())
        
        var error = kvImageNoError
        
        error = vImageBuffer_InitWithCVPixelBuffer(&sourceBuffer,
                                                   &format,
                                                   inputPixelBuffer,
                                                   inputCVImageFormat,
                                                   nil,
                                                   vImage_Flags(kvImageNoFlags))
        
        guard error == kvImageNoError else {
            throw EqualizationImageProcessorError.equalizationOperationFailed
        }
        defer {
            free(sourceBuffer.data)
        }
        
        var destinationBuffer = vImage_Buffer()
        
        error = vImageBuffer_Init(&destinationBuffer,
                                  sourceBuffer.height,
                                  sourceBuffer.width,
                                  format.bitsPerPixel,
                                  vImage_Flags(kvImageNoFlags))
        
        guard error == kvImageNoError else {
            throw EqualizationImageProcessorError.equalizationOperationFailed
        }
        defer {
            free(destinationBuffer.data)
        }
        
        /*
         All four channel histogram functions (i.e. those that support ARGB8888 or ARGBFFFF images)
         work equally well on four channel images with other channel orderings such as RGBA8888 or BGRAFFFF.
         */
        error = vImageEqualization_ARGB8888(
            &sourceBuffer,
            &destinationBuffer,
            vImage_Flags(kvImageLeaveAlphaUnchanged))
        
        guard error == kvImageNoError else {
            throw EqualizationImageProcessorError.equalizationOperationFailed
        }
        
        let outputCVImageFormat = vImageCVImageFormat_CreateWithCVPixelBuffer(outputPixelBuffer).takeRetainedValue()
        vImageCVImageFormat_SetColorSpace(outputCVImageFormat,
                                          CGColorSpaceCreateDeviceRGB())
        
        error = vImageBuffer_CopyToCVPixelBuffer(&destinationBuffer,
                                                 &format,
                                                 outputPixelBuffer,
                                                 outputCVImageFormat,
                                                 nil,
                                                 vImage_Flags(kvImageNoFlags))
        
        guard error == kvImageNoError else {
            throw EqualizationImageProcessorError.equalizationOperationFailed
        }
    }
}


extension ARFrame {
    func depthMapTransformedImage(orientation: UIInterfaceOrientation, viewPort: CGRect) -> UIImage? {
        guard let pixelBuffer = self.sceneDepth?.depthMap else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return UIImage(ciImage: screenTransformed(ciImage: ciImage, orientation: orientation, viewPort: viewPort))
    }
    
    func depthMapTransformedHistNormalizedImage(orientation: UIInterfaceOrientation, viewPort: CGRect) -> UIImage? {
        guard let pixelBuffer = self.sceneDepth?.depthMap else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if let result = try? EqualizationImageProcessorKernel.apply(
                withExtent: ciImage.extent,
                inputs: [ciImage],
                arguments: nil) {
            return UIImage(ciImage: screenTransformed(ciImage: result, orientation: orientation, viewPort: viewPort))
        }
        return UIImage(ciImage: screenTransformed(ciImage: ciImage, orientation: orientation, viewPort: viewPort))
    }
    
    func depthMapTransformedNormalizedImage(orientation: UIInterfaceOrientation, viewPort: CGRect) -> UIImage? {
        //guard let pixelBuffer = self.smoothedSceneDepth?.depthMap else { return nil }
        guard let pixelBuffer = self.sceneDepth?.depthMap else { return nil }
        let pixelBufferCopy: CVPixelBuffer!
        do
        {
            try pixelBufferCopy = pixelBuffer.copy()

        } catch{
            pixelBufferCopy = pixelBuffer
        }
        pixelBufferCopy.normalize()
        let ciImage = CIImage(cvPixelBuffer: pixelBufferCopy)
        return UIImage(ciImage: screenTransformed(ciImage: ciImage, orientation: orientation, viewPort: viewPort))
    }
    
    func depthMapTransformedImageCIImage(orientation: CGImagePropertyOrientation) -> CIImage? {
        //guard let pixelBuffer = self.smoothedSceneDepth?.depthMap else { return nil }
        guard let pixelBuffer = self.sceneDepth?.depthMap else { return nil }
        let pixelBufferCopy: CVPixelBuffer!
        do
        {
            try pixelBufferCopy = pixelBuffer.copy()

        } catch{
            pixelBufferCopy = pixelBuffer
        }
        return CIImage(cvPixelBuffer: pixelBufferCopy).oriented(orientation)
    }
    
    func depthmapTransfromedRescaledImage(orientation: UIInterfaceOrientation, viewPort: CGRect) -> UIImage?    {
        guard let pixelBuffer = self.sceneDepth?.depthMap else { return nil }
        let pixelBufferCopy: CVPixelBuffer!
        do
        {
            try pixelBufferCopy = pixelBuffer.copy()

        } catch{
            pixelBufferCopy = pixelBuffer
        }
        
        //pixelBufferCopy.normalize()
        pixelBufferCopy.rescale(minPixel: 0, maxPixel: 10.0)

        let ciImage = CIImage(cvPixelBuffer: pixelBufferCopy)
        return UIImage(ciImage: screenTransformed(ciImage: ciImage, orientation: orientation, viewPort: viewPort))
    }

    func ConfidenceMapTransformedImage(orientation: UIInterfaceOrientation, viewPort: CGRect) -> UIImage? {
        guard let pixelBuffer = self.sceneDepth?.confidenceMap,
              let ciImage = confidenceMapToCIImage(pixelBuffer: pixelBuffer) else { return nil }
        
        return UIImage(ciImage: screenTransformed(ciImage: ciImage, orientation: orientation, viewPort: viewPort))
    }
    
    func ColorTransformedImage(orientation: UIInterfaceOrientation, viewPort: CGRect) -> UIImage? {
        let pixelBuffer = self.capturedImage
        let pixelBufferCopy: CVPixelBuffer!
        do
        {
            try pixelBufferCopy = pixelBuffer.copy()

        } catch{
            pixelBufferCopy = pixelBuffer
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBufferCopy)
        return UIImage(ciImage: screenTransformed(ciImage: ciImage, orientation: orientation, viewPort: viewPort),scale: 1.0, orientation: .up)
    }

    func confidenceMapToCIImage(pixelBuffer: CVPixelBuffer) -> CIImage? {
        func confienceValueToPixcelValue(confidenceValue: UInt8) -> UInt8 {
            guard confidenceValue <= ARConfidenceLevel.high.rawValue else {return 0}
            return UInt8(floor(Float(confidenceValue) / Float(ARConfidenceLevel.high.rawValue) * 255))
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        for i in stride(from: 0, to: bytesPerRow*height, by: MemoryLayout<UInt8>.stride) {
            let data = base.load(fromByteOffset: i, as: UInt8.self)
            let pixcelValue = confienceValueToPixcelValue(confidenceValue: data)
            base.storeBytes(of: pixcelValue, toByteOffset: i, as: UInt8.self)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return CIImage(cvPixelBuffer: pixelBuffer)
    }

    func screenTransformed(ciImage: CIImage, orientation: UIInterfaceOrientation, viewPort: CGRect) -> CIImage {
        let transform = screenTransform(orientation: orientation, viewPortSize: viewPort.size, captureSize: ciImage.extent.size)
        return ciImage.transformed(by: transform).cropped(to: viewPort)
    }

    func screenTransform(orientation: UIInterfaceOrientation, viewPortSize: CGSize, captureSize: CGSize) -> CGAffineTransform {
        let normalizeTransform = CGAffineTransform(scaleX: 1.0/captureSize.width, y: 1.0/captureSize.height)
        let flipTransform = (orientation.isPortrait) ? CGAffineTransform(scaleX: -1, y: -1).translatedBy(x: -1, y: -1) : .identity
        let displayTransform = self.displayTransform(for: orientation, viewportSize: viewPortSize)
        let toViewPortTransform = CGAffineTransform(scaleX: viewPortSize.width, y: viewPortSize.height)
        return normalizeTransform.concatenating(flipTransform).concatenating(displayTransform).concatenating(toViewPortTransform)
    }

    fileprivate func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int, textureCache: CVMetalTextureCache) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, pixelFormat,
                                                               width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }

    func buildCapturedImageTextures(textureCache: CVMetalTextureCache) -> (textureY: CVMetalTexture, textureCbCr: CVMetalTexture)? {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = self.capturedImage
        
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return nil
        }
        
        guard let capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: 0, textureCache: textureCache),
              let capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex: 1, textureCache: textureCache) else {
            return nil
        }
        
        return (textureY: capturedImageTextureY, textureCbCr: capturedImageTextureCbCr)
    }

    func buildDepthTextures(textureCache: CVMetalTextureCache) -> (depthTexture: CVMetalTexture, confidenceTexture: CVMetalTexture)? {
        guard let depthMap = self.sceneDepth?.depthMap,
            let confidenceMap = self.sceneDepth?.confidenceMap else {
                return nil
        }
        
        guard let depthTexture = createTexture(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0, textureCache: textureCache),
              let confidenceTexture = createTexture(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0, textureCache: textureCache) else {
            return nil
        }
        
        return (depthTexture: depthTexture, confidenceTexture: confidenceTexture)
    }
}
