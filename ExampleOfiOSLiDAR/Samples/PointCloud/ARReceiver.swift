/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A utility class that receives processed depth information.
*/

import Foundation
import SwiftUI
import Combine
import ARKit

// Receive the newest AR data from an `ARReceiver`.
protocol ARDataReceiver: AnyObject {
    func onNewARData(arData: ARData)
}

//- Tag: ARData
// Store depth-related AR data.
final class ARData {
    var depthImage: CVPixelBuffer?
    var depthSmoothImage: CVPixelBuffer?
    var colorImage: CVPixelBuffer?
    var confidenceImage: CVPixelBuffer?
    var confidenceSmoothImage: CVPixelBuffer?
    var cameraIntrinsics = simd_float3x3()
    var cameraResolution = CGSize()
}

// Configure and run an AR session to provide the app with depth-related AR data.
final class ARReceiver: NSObject, ARSessionDelegate {
    var arData = ARData()
    var arSession = ARSession()
    weak var delegate: ARDataReceiver?
    
    // Configure and start the ARSession.
    override init() {
        super.init()
        arSession.delegate = self
        start()
    }
    
    // Configure the ARKit session.
    func start() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) else { return }
        // Enable both the `sceneDepth` and `smoothedSceneDepth` frame semantics.
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        arSession.run(config)
    }
    
    func pause() {
        arSession.pause()
    }
  
    // Send required data from `ARFrame` to the delegate class via the `onNewARData` callback.
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if(frame.sceneDepth != nil) && (frame.smoothedSceneDepth != nil) {
            arData.depthImage = frame.sceneDepth?.depthMap
            arData.depthSmoothImage = frame.smoothedSceneDepth?.depthMap
            arData.confidenceImage = frame.sceneDepth?.confidenceMap
            arData.confidenceSmoothImage = frame.smoothedSceneDepth?.confidenceMap
            arData.colorImage = frame.capturedImage
            arData.cameraIntrinsics = frame.camera.intrinsics
            arData.cameraResolution = frame.camera.imageResolution
            delegate?.onNewARData(arData: arData)
        }
    }
}



func pixelBuffertoCIImage(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, rescale:Bool) -> CIImage? {
    let pixelBufferCopy: CVPixelBuffer!
    do
    {
        try pixelBufferCopy = pixelBuffer.copy()

    } catch{
        pixelBufferCopy = pixelBuffer
    }
    if rescale{
        pixelBufferCopy.rescale(minPixel: 0.0, maxPixel: 20.0)
    }
    return CIImage(cvPixelBuffer: pixelBufferCopy).oriented(orientation)
}


func pixelBuffertoUIImage(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, rescale:Bool) -> UIImage? {
    let ciImage = pixelBuffertoCIImage(pixelBuffer: pixelBuffer, orientation: orientation, rescale:rescale)
    return UIImage(ciImage:ciImage!)
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
