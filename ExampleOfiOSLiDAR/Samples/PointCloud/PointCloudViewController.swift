//
//  ViewController.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/01/07.
//

import ARKit
import Metal
import MetalKit
import CoreImage

// FLIR
import UIKit
import ThermalSDK

// Depth
import RealityKit

// Roll pitch yaw
import CoreMotion

class PointCloudViewController: UIViewController, UIGestureRecognizerDelegate, CLLocationManagerDelegate {

    
    @IBOutlet weak var mtkView: MTKView!
    
    // ARKit
    private var session: ARSession!
    var alphaTexture: MTLTexture?
    
    // Metal
    private let device = MTLCreateSystemDefaultDevice()!
    private var commandQueue: MTLCommandQueue!
    private var matteGenerator: ARMatteGenerator!
    lazy private var textureCache: CVMetalTextureCache = {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        return cache!
    }()
    
    
    // FLIR
    var discovery: FLIRDiscovery?
    var camera: FLIRCamera?

    @IBOutlet weak var centerSpotLabel: UILabel!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var distanceSlider: UISlider!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var rgbimageView: UIImageView!
    
    @IBOutlet weak var shootingPeriodLabel: UILabel!
    @IBOutlet weak var shootingPeriodSlider: UISlider!
    

    var thermalStreamer: FLIRThermalStreamer?
    var stream: FLIRStream?
    var fusion: FLIRFusion?
    
    var thermal_img: UIImage!
    var rgb_img: UIImage!
    var flir_img: FLIRThermalImage!
    
    var save_cnt: Int = 0
    
    var shootingPeriodInt: Int = 1
    
    var shootingStart: Bool = false
    
    let fm:LocalFileManager = LocalFileManager.instance
    
    let renderQueue = DispatchQueue(label: "render")

    var flir_on: Bool = false
    // FLIR
    
    let locationManager = CLLocationManager()
    var locValue =  CLLocationCoordinate2D()
    var altitude: Double = 0.0
    var timestamp: Date = Date()
    
    var motionManager    = CMMotionManager()
    var roll = 0.0
    var pitch = 0.0
    var yaw = 0.0
    @IBOutlet weak var rollLabel: UILabel!
    @IBOutlet weak var pitchLabel: UILabel!
    @IBOutlet weak var yawLabel: UILabel!
    //////////
    var depth_img: UIImage!
    @IBOutlet weak var depthImageView: UIImageView!
    var iPhone_rgb_img: UIImage!
    @IBOutlet weak var iPhone_rgb_imgView: UIImageView!
    ///////////
    
    // Metronome - Timelapse
    @IBOutlet weak var bpmLabel: UILabel!
    @IBOutlet weak var tickLabel: UILabel!
    
    let myMetronome = Metronome()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        myMetronome.onTick = { (nextTick) in
            self.animateTick()
            
            // Save functions..
            print("Save file here!")
            self.saveFiles()
        }
        updateBpm()
    }

    private func animateTick() {
        tickLabel.alpha = 1.0
        UIView.animate(withDuration: 0.35) {
            self.tickLabel.alpha = 0.0
        }
    }

    @IBAction func startMetronome(_ sender: AnyObject) {
        if myMetronome.enabled{
            myMetronome.enabled = false
            sender.setTitle("Start Rec.", for: [])
        }else{
            myMetronome.enabled = true
            sender.setTitle("Stop Rec.", for: [])
        }
    }

    @IBAction func stopMetronome(_: Any?) {
        myMetronome.enabled = false
    }

    
    @IBAction func periodSliderValueChanged(_ sender: UISlider)
    {
        self.shootingPeriodInt = Int(sender.value)
        myMetronome.bpm = 60 / Float(self.shootingPeriodInt)
        print(myMetronome.bpm)
        updateBpm()
    }
    
    @IBAction func manualCapture(_: Any?) {
        saveFiles()
        animateTick()
    }
    
    private func updateBpm() {
        let metronomeBpm = Int(myMetronome.bpm)
        //bpmLabel.text = "\(metronomeBpm)"
        self.shootingPeriodLabel.text = "\(self.shootingPeriodInt) sec"
    }
    
    func reset_sliders()
    {
        shootingPeriodSlider.minimumValue = 1
        shootingPeriodSlider.maximumValue = 10
        shootingPeriodSlider.value = 5
    }
    
    func saveJson(){
        //print("locations = \(self.locValue.latitude) \(self.locValue.longitude)")
        //print(self.altitude)
        
        //@TODO: Add more metadata
        let personArray =  [
                            ["gps": ["latitude": "\(self.locValue.latitude)", "longitude": "\(self.locValue.longitude)", "altitude": "\(self.altitude)"]],
                            ["attitude": ["roll": "\(self.roll)", "pitch": "\(self.pitch)", "yaw": "\(self.yaw)"]],
                            ["timestamp": "\(self.timestamp)"],
                            ]
        
        // Get the url of Persons.json in document directory
        let fileUrl = self.fm.getPathForImageExt(subdir: "meta_json", name: "IMG_\(self.save_cnt)", ext: "json")
        
        // Create a write-only stream
        guard let stream = OutputStream(toFileAtPath: fileUrl!.path, append: false) else { return }
        stream.open()
        defer {
            stream.close()
        }

        // Transform array into data and save it into file
        var error: NSError?
        JSONSerialization.writeJSONObject(personArray, to: stream, options: [], error: &error)

        // Handle error
        if let error = error {
            print(error)
        }
    }
    
    func saveFiles()
    {
        // Create folder
        self.fm.createFolderIfNeeded()
        // Get Next cnt
        self.save_cnt = self.fm.getNextCnt(subDir: "depth_tiff")
        
        // Save FLIR Image
        if self.flir_on{
            let path = self.fm.getPathForImage(name: "flir_jpg/IMG_\(self.save_cnt)")?.path
            do
            {
                print(path)
                try self.flir_img.save(as:path!)
                print("Save success")
            } catch{
                print("Save failed \(error)")
            }
        }

        
        // Save iPhone jpg
        //let rgb_path = self.fm.getPathForImage(name: "rgb_jpg/IMG_\(self.save_cnt)")!
        let rgb_path = self.fm.getPathForImageExt(subdir: "rgb_jpg", name: "IMG_\(self.save_cnt)", ext: "png")
        self.fm.saveJpg(image: self.iPhone_rgb_img, path: rgb_path!)
        
        
        // Save iPhone Depth
        let depth_url = self.fm.getPathForImageExt(subdir: "depth_tiff", name: "IMG_\(self.save_cnt)", ext: "tiff")
        guard let pixelBuffer = session.currentFrame?.sceneDepth?.depthMap else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(tiffOrientation)
        let context: CIContext! = CIContext()
        do {
            try context.writeTIFFRepresentation(of: ciImage, to: depth_url!, format: context.workingFormat, colorSpace: context.workingColorSpace!, options: [:])
        } catch {
            print("Save TIFF failed")
            print(error)
        }
        // @TODO: Save iPhone Point cloud
        
        // @TODO: Save GPS Coordinate, Roll, Pich, Yaw
        saveJson()
            
    
        
    }
    // Metronome
    
    
    private var texture: MTLTexture!
    lazy private var renderer = PointCloudRenderer(device: device,session: session, mtkView: mtkView)
    
    var orientation: UIInterfaceOrientation {
        guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
            fatalError()
        }
        return orientation
    }
    
    var tiffOrientation: CGImagePropertyOrientation{
        var tiffOrientation: CGImagePropertyOrientation
        switch orientation {
            case .unknown: tiffOrientation = .right
            case .portrait: tiffOrientation = .right
            case .portraitUpsideDown: tiffOrientation = .left
            case .landscapeLeft: tiffOrientation = .up
            case .landscapeRight: tiffOrientation = .down
        }
        return tiffOrientation
    }


    override func viewDidLoad() {
        func initMatteGenerator() {
            matteGenerator = ARMatteGenerator(device: device, matteResolution: .half)
        }
        func initMetal() {
            commandQueue = device.makeCommandQueue()
            mtkView.device = device
            mtkView.framebufferOnly = false
            mtkView.delegate = self
        }
        func buildConfigure() -> ARWorldTrackingConfiguration {
            let configuration = ARWorldTrackingConfiguration()

            configuration.environmentTexturing = .automatic
            if type(of: configuration).supportsFrameSemantics(.sceneDepth) {
               configuration.frameSemantics = .sceneDepth
            }

            return configuration
        }
        func runARSession() {
            let configuration = buildConfigure()
            session.run(configuration)
        }
        func initARSession() {
            session = ARSession()
            runARSession()
        }
        func createTexture() {
            let width = mtkView.currentDrawable!.texture.width
            let height = mtkView.currentDrawable!.texture.height

            let colorDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: mtkView.colorPixelFormat,
                                                                 width: height, height: width, mipmapped: false)
            colorDesc.usage = MTLTextureUsage(rawValue: MTLTextureUsage.renderTarget.rawValue | MTLTextureUsage.shaderRead.rawValue)

        }
        
        super.viewDidLoad()
        initARSession()
        initMatteGenerator()
        initMetal()
        createTexture()
        
        // FLIR
        discovery = FLIRDiscovery()
        discovery?.delegate = self
        
        // fm.createFolderIfNeeded()
        // FLIR
        
        // Metronome
        reset_sliders()
        
        // Init Location
        // Ask for Authorisation from the User.
        self.locationManager.requestAlwaysAuthorization()

        // For use in foreground
        self.locationManager.requestWhenInUseAuthorization()

        if CLLocationManager.locationServicesEnabled() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.startUpdatingLocation()
        }
        
        // Roll pich yaw
//        if motionManager.isAccelerometerAvailable {
//            motionManager.accelerometerUpdateInterval = 0.01
//            motionManager.startAccelerometerUpdates(to: OperationQueue.main) { (data, error) in
//                print(data)
//            }
//        }
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval  = 0.2
            motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (data, error) in
                //print(data?.attitude)
                self.outputRPY(data:data!.attitude)
            }
        }
    }
    
    // FLIR
    func requireCamera() {
        guard camera == nil else {
            return
        }
        let camera = FLIRCamera()
        self.camera = camera
        camera.delegate = self
    }
    
    @IBAction func panGesture(_ sender: UIPanGestureRecognizer) {
        func buildXRotateMatrix() -> matrix_float4x4 {
            
            let rad = -(maxRad * Float(point.y) / cameraResolution.y).truncatingRemainder(dividingBy: Float.pi)
            //print("buildXRotateMatrix \(rad)")
            return matrix_float4x4(
                    simd_float4(1, 0,  0, 0),
                    simd_float4(0, cos(rad),  sin(rad), 0),
                    simd_float4(0, -sin(rad), cos(rad), 0),
                simd_float4(0, 0, 0, 1))
        }
        func buildYRotateMatrix() -> matrix_float4x4 {
            let rad = (maxRad * Float(point.x) / cameraResolution.x).truncatingRemainder(dividingBy: Float.pi)
            //print("buildYRotateMatrix \(rad)")
            return matrix_float4x4(
                    simd_float4(cos(rad), 0,  -sin(rad), 0 ),
                    simd_float4(0, 1,  0, 0),
                    simd_float4(sin(rad), 0,  cos(rad), 0),
                simd_float4(0, 0, 0, 1))
        }
        let maxRad = Float.pi * 0.1
        let cameraResolution = Float2(Float(session.currentFrame?.camera.imageResolution.width ?? 0), Float(session.currentFrame?.camera.imageResolution.height ?? 0))
        let point = sender.translation(in: view)

        let rotateX = buildXRotateMatrix()
        let rotateY = buildYRotateMatrix()

        renderer.modelTransform = simd_mul(simd_mul(renderer.modelTransform, rotateX),rotateY)
    }
    
    func rotatePoints(x: Float, y: Float) {
        func buildXRotateMatrix() -> matrix_float4x4 {
            let rad = x
            return matrix_float4x4(
                    simd_float4(1, 0,  0, 0),
                    simd_float4(0, cos(rad),  sin(rad), 0),
                    simd_float4(0, -sin(rad), cos(rad), 0),
                simd_float4(0, 0, 0, 1))
        }
        func buildYRotateMatrix() -> matrix_float4x4 {
            let rad = y
            return matrix_float4x4(
                    simd_float4(cos(rad), 0,  -sin(rad), 0 ),
                    simd_float4(0, 1,  0, 0),
                    simd_float4(sin(rad), 0,  cos(rad), 0),
                simd_float4(0, 0, 0, 1))
        }

        let rotateX = buildXRotateMatrix()
        let rotateY = buildYRotateMatrix()

        renderer.modelTransform = simd_mul(simd_mul(renderer.modelTransform, rotateX),rotateY)
    }
    
    func standupPoints(){
      
        //rotatePoints(x:Float(0), y:Float.pi/2)
        //rotatePoints(x:Float.pi/2, y:0)
        //rotatePoints(x:Float(0), y:-Float.pi/2)
        
        func buildXRotateMatrix(x: Float) -> matrix_float4x4 {
            let rad = x
            return matrix_float4x4(
                    simd_float4(1, 0,  0, 0),
                    simd_float4(0, cos(rad),  sin(rad), 0),
                    simd_float4(0, -sin(rad), cos(rad), 0),
                simd_float4(0, 0, 0, 1))
        }
        func buildYRotateMatrix(y: Float) -> matrix_float4x4 {
            let rad = y
            return matrix_float4x4(
                    simd_float4(cos(rad), 0,  -sin(rad), 0 ),
                    simd_float4(0, 1,  0, 0),
                    simd_float4(sin(rad), 0,  cos(rad), 0),
                simd_float4(0, 0, 0, 1))
        }

        var rotateX = buildXRotateMatrix(x:Float(0))
        var rotateY = buildYRotateMatrix(y:Float.pi/2)
        var rotation_matrix = simd_mul(rotateX,rotateY)
        
        rotateX = buildXRotateMatrix(x:Float.pi/2)
        rotateY = buildYRotateMatrix(y:Float(0))
        rotation_matrix = simd_mul(simd_mul(rotation_matrix, rotateX),rotateY)
        
        rotateX = buildXRotateMatrix(x:Float(0))
        rotateY = buildYRotateMatrix(y:-Float.pi/2)
        renderer.modelTransform = simd_mul(simd_mul(rotation_matrix, rotateX),rotateY)
        
        let cameraResolution = Float2(Float(session.currentFrame?.camera.imageResolution.width ?? 0), Float(session.currentFrame?.camera.imageResolution.height ?? 0))
        //print(cameraResolution)
    }
    
    // FLIR
    @IBAction func connectDeviceClicked(_ sender: Any) {
        self.flir_on = true
        discovery?.start(.lightning)
    }

    @IBAction func disconnectClicked(_ sender: Any) {
        self.flir_on = false
        camera?.disconnect()
    }

    @IBAction func connectEmulatorClicked(_ sender: Any) {
        self.flir_on = true
        discovery?.start(.emulator)
    }

    @IBAction func distanceSliderValueChanged(_ sender: Any) {
        if let remoteControl = self.camera?.getRemoteControl(),
           let fusionController = remoteControl.getFusionController() {
            let newDistance = distanceSlider.value
            try? fusionController.setFusionDistance(Double(newDistance))
        }
    }
    // FLIR
    
    
    // Location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let locValue: CLLocationCoordinate2D = manager.location?.coordinate else { return }
        guard let timestamp: Date = manager.location?.timestamp else { return }
        var alt = manager.location?.altitude
        
        self.locValue = locValue
        self.altitude = alt!
        self.timestamp = timestamp
        
        //print("locations = \(locValue.latitude) \(locValue.longitude)")
    }
    
    // Motion
    func outputRPY(data: CMAttitude){
       roll    = data.roll * (180.0 / M_PI)
       pitch   = data.pitch * (180.0 / M_PI)
       yaw     = data.yaw * (180.0 / M_PI)
       rollLabel.text  = String(format: "%.2f°", roll)
       pitchLabel.text = String(format: "%.2f°", pitch)
       yawLabel.text   = String(format: "%.2f°", yaw)
   }
}


extension PointCloudViewController: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard session.currentFrame != nil else {return}
        renderer.drawRectResized(size: size)

    }
    
//    @IBAction func rotate_points(_ sender: Any){
//        standupPoints()
//    }

    func draw(in view: MTKView) {
        func getAlphaTexture(_ commandBuffer: MTLCommandBuffer) -> MTLTexture? {
            guard let currentFrame = session.currentFrame else {
                return nil
            }

            return matteGenerator.generateMatte(from: currentFrame, commandBuffer: commandBuffer)
        }
        func buildRenderEncoder(_ commandBuffer: MTLCommandBuffer) -> MTLRenderCommandEncoder? {
            let rpd = view.currentRenderPassDescriptor
            rpd?.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            rpd?.colorAttachments[0].loadAction = .clear
            rpd?.colorAttachments[0].storeAction = .store
            return commandBuffer.makeRenderCommandEncoder(descriptor: rpd!)
        }
        guard let drawable = view.currentDrawable else {return}
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        guard let (textureY, textureCbCr) = session.currentFrame?.buildCapturedImageTextures(textureCache: textureCache) else {return}

        guard let (depthTexture, confidenceTexture) = session.currentFrame?.buildDepthTextures(textureCache: textureCache) else {return}

        guard let encoder = buildRenderEncoder(commandBuffer) else {return}
        
        //standupPoints()
        
        renderer.update(commandBuffer, renderEncoder: encoder, capturedImageTextureY: textureY, capturedImageTextureCbCr: textureCbCr, depthTexture: depthTexture, confidenceTexture: confidenceTexture)
                
        commandBuffer.present(drawable)
        
        commandBuffer.commit()
        
        commandBuffer.waitUntilCompleted()
        
        // iPhone RGB & Depth
        let depth_ROI = CGRect(x: 0, y: 0, width: 1440, height: 1920)
        self.iPhone_rgb_img = session.currentFrame?.ColorTransformedImage(orientation: orientation, viewPort: depth_ROI)
        self.iPhone_rgb_imgView.image = self.iPhone_rgb_img
        
        //self.depth_img = session.currentFrame?.depthMapTransformedImage(orientation: orientation, viewPort: depth_ROI)
        self.depth_img = session.currentFrame?.depthMapTransformedNormalizedImage(orientation: orientation, viewPort: depth_ROI)
        self.depthImageView.image = self.depth_img
        
        
    }
}

extension PointCloudViewController : FLIRDataReceivedDelegate {
    func onDisconnected(_ camera: FLIRCamera, withError error: Error?) {
        NSLog("\(#function) \(String(describing: error))")
        DispatchQueue.main.async {
            self.thermalStreamer = nil
            self.stream = nil
            let alert = UIAlertController(title: "Disconnected",
                                          message: "Flir One disconnected",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
}

extension PointCloudViewController: FLIRDiscoveryEventDelegate {

    func cameraFound(_ cameraIdentity: FLIRIdentity) {
        switch cameraIdentity.cameraType() {
        case .flirOne:
            requireCamera()
            guard !camera!.isConnected() else {
                return
            }
            DispatchQueue.global().async {
                do {
                    try self.camera?.connect(cameraIdentity)
                    let streams = self.camera?.getStreams()
                    guard let stream = streams?.first else {
                        NSLog("No streams found on camera!")
                        return
                    }
                    self.stream = stream
                    self.thermalStreamer = FLIRThermalStreamer(stream: stream)
                
                    stream.delegate = self
                    do {
                        try stream.start()
                    } catch {
                        NSLog("stream.start error \(error)")
                    }
                    
                    self.thermalStreamer?.withThermalImage { image in

                        // Change the camera setting
                        self.fusion = image.getFusion()
                        self.fusion?.setFusionMode(IR_MODE)
                    }
                    
                } catch {
                    NSLog("Camera connect error \(error)")
                }
            }
        case .generic:
            ()
        @unknown default:
            fatalError("unknown cameraType")
        }
    }

    func discoveryError(_ error: String, netServiceError nsnetserviceserror: Int32, on iface: FLIRCommunicationInterface) {
        NSLog("\(#function)")
    }

    func discoveryFinished(_ iface: FLIRCommunicationInterface) {
        NSLog("\(#function)")
    }

    func cameraLost(_ cameraIdentity: FLIRIdentity) {
        NSLog("\(#function)")
    }
}

extension PointCloudViewController : FLIRStreamDelegate {
    
    func onError(_ error: Error) {
        NSLog("\(#function) \(error)")
    }

    func onImageReceived() {
        renderQueue.async {
            do {
                try self.thermalStreamer?.update()
            } catch {
                NSLog("update error \(error)")
            }
                
            
            DispatchQueue.main.async {
                
                self.thermalStreamer?.withThermalImage { image in
                    
                    let thermal_image = self.thermalStreamer?.getImage()
   
                    self.thermal_img = thermal_image
                    self.imageView.image = thermal_image
                    
                    self.rgb_img = image.getPhoto()
                    //self.rgbimageView.image = self.rgb_img
                    
                    if let measurements = image.measurements {
                        if measurements.getAllSpots().isEmpty {
                            do {
                                try measurements.addSpot(CGPoint(x: CGFloat(image.getWidth()) / 2,
                                                                 y: CGFloat(image.getHeight()) / 2))
                            } catch {
                                NSLog("addSpot error \(error)")
                            }
                        }
                        if let spot = measurements.getAllSpots().first {
                            self.centerSpotLabel.text = spot.getValue().description()
                        }
                    }
                    if let remoteControl = self.camera?.getRemoteControl(),
                       let fusionController = remoteControl.getFusionController() {
                        let distance = fusionController.getFusionDistance()
                        self.distanceLabel.text = "\((distance * 1000).rounded() / 1000)"
                        self.distanceSlider.value = Float(distance)
                        
                        
                    }
                    self.flir_img = image
                    
                    if false{
                        //let path = self.documentDirectoryPath()?.appendingPathComponent("exampleJpg.jpg")?.path.absoluteString
                        //print(self.fm.getPathForImage(name: "Example"))
                        //let path = getPathForImage(name: "Example")?.path
                        let path = self.fm.getPathForImage(name: "IMG_\(self.save_cnt)")?.path
                        do
                        {
                            print(path)
                            try image.save(as:path!)
                            print("Save success")
                            self.save_cnt += 1
                        } catch{
                            print("Save failed \(error)")
                        }
                    }
                }
            }
        }
    }
    
}
