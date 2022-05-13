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
    var flirBatt: FLIRBattery?
    
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
    
    var flir_img: FLIRThermalImage!
    
    var save_cnt: Int = 0
    
    var shootingPeriodInt: Int = 1
    
    var shootingStart: Bool = false
    
    let fm:LocalFileManager = LocalFileManager.instance
    
    let renderQueue = DispatchQueue(label: "render")

    var flir_on: Bool = false
    
    var pm:FLIRPaletteManager = FLIRPaletteManager.init()
    var t_min:Double!
    var t_max:Double!
    var t_average:Double!
    @IBOutlet weak var minLabel: UILabel!
    @IBOutlet weak var maxLabel: UILabel!
    @IBOutlet weak var averageLabel: UILabel!
    @IBOutlet weak var batteryLabel: UILabel!
    let thermalImage:FLIRThermalImageFile! = FLIRThermalImageFile()
    // FLIR
    
    let locationManager = CLLocationManager()
    var locValue =  CLLocationCoordinate2D()
    @IBOutlet weak var LatLabel: UILabel!
    @IBOutlet weak var LonLabel: UILabel!
    @IBOutlet weak var altitudeLabel: UILabel!
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
    var depth_img: CIImage!
    var rgb_img: UIImage!
    @IBOutlet weak var depthImageView: UIImageView!
    var iPhone_rgb_img: UIImage!
    @IBOutlet weak var iPhone_rgb_imgView: UIImageView!
    ///////////
    
    // Metronome - Timelapse
    @IBOutlet weak var bpmLabel: UILabel!
    @IBOutlet weak var tickLabel: UILabel!
    
    // Point cloud
    var isSavingFile = false
    private lazy var library: MTLLibrary = device.makeDefaultLibrary()!
    
    let myMetronome = Metronome()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        myMetronome.onTick = { (nextTick) in
            self.animateTick()
            
            // Save functions..
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
        //let metronomeBpm = Int(myMetronome.bpm)
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
                            ["thermal": ["min": self.t_min, "max": self.t_max, "avg": self.t_average]],
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
    
    func updateImgs()
    {
        // iPhone RGB & Depth
        let depth_ROI = CGRect(x: 0, y: 0, width: 1440, height: 1920)
        //self.iPhone_rgb_img = session.currentFrame?.ColorTransformedImage(orientation: tiffOrientation)
        self.iPhone_rgb_img = session.currentFrame?.ColorTransformedImage(orientation: orientation, viewPort: depth_ROI)
        
        self.iPhone_rgb_imgView.image = self.iPhone_rgb_img
        
        //self.depth_img = session.currentFrame?.depthMapTransformedImage(orientation: orientation, viewPort: depth_ROI)
        //self.depth_img = session.currentFrame?.depthMapTransformedNormalizedImage(orientation: orientation, viewPort: depth_ROI)
        guard let pixelBuffer = session.currentFrame?.sceneDepth?.depthMap else { return }
        let pixelBufferSave: CVPixelBuffer!
        do
        {
            try pixelBufferSave = pixelBuffer.copy()

        } catch{
            pixelBufferSave = pixelBuffer
        }
        self.depth_img = CIImage(cvPixelBuffer: pixelBufferSave).oriented(tiffOrientation)
        //self.depth_img = session.currentFrame?.depthMapTransformedImageCIImage(orientation: tiffOrientation)
        
        let pixelBufferCopy: CVPixelBuffer!
        do
        {
            try pixelBufferCopy = pixelBuffer.copy()

        } catch{
            pixelBufferCopy = pixelBuffer
        }
        
        pixelBufferCopy.normalize()
        let ciImage = CIImage(cvPixelBuffer: pixelBufferCopy).oriented(tiffOrientation)
        self.depthImageView.image = UIImage(ciImage: ciImage)
    }
    
    func processFLIR(){
        
        //let thermalImage = FLIRThermalImageFile()
        
        let path = self.fm.getPathForImage(name: "flir_jpg/IMG_\(self.save_cnt)")?.path
        
        if !FileManager.default.fileExists(atPath: path!)
        {

        
        
            thermalImage.open(path!)
            thermalImage.setTemperatureUnit(.CELSIUS)

            let theFileName = (path! as NSString).lastPathComponent
            let ir_name = theFileName.replacingOccurrences(of: ".jpg", with: "_IR")
            let rgb_name = theFileName.replacingOccurrences(of: ".jpg", with: "_RGB")
            
            let ir_path = self.fm.getPathForImageExt(subdir: "flir_processed", name: ir_name, ext: "png")
            let rgb_path = self.fm.getPathForImageExt(subdir: "flir_processed", name: rgb_name, ext: "png")
            
            
            if let fusion = thermalImage.getFusion() {
                //fusion.setFusionMode(FUSION_MSX_MODE)
                //msxImageView.image = thermalImage.getImage()

                fusion.setFusionMode(IR_MODE)
                //print(thermalImage.palette?.name)
                //thermalImage.palette = FLIRPalette.init()
                thermalImage.palette = self.pm.gray
                //print(thermalImage.palette?.name)
                

                
                let ir_image = thermalImage.getImage()!
                //let ir_image = UIColor.orange.image(CGSize(width: 480, height: 640))
                //let new_ir_image = ir_image.rotate(radians: 0) // Rotate 180 degrees
                //saveJpg(image: ir_image!, path: ir_path!)
                self.fm.savePng(image: ir_image, path: ir_path!)


                fusion.setFusionMode(VISUAL_MODE)
                let rgb_image = thermalImage.getImage()!
                //let rgb_image = UIColor.orange.image(CGSize(width: 480, height: 640))
                //let new_rgb_image = rgb_image.rotate(radians: 0) // Rotate 180 degrees
                //saveJpg(image: rgb_image!, path: rgb_path!)
                self.fm.savePng(image: rgb_image, path: rgb_path!)
            }
            
            if let statistics = thermalImage.getStatistics() {
                self.t_min = statistics.getMin().value
                //minLabel.text = "\(self.t_min)"
                self.t_max = statistics.getMax().value
                //maxLabel.text = "\(self.t_max)"
                self.t_average = statistics.getAverage().value
                //averageLabel.text = "\(self.t_average)"
            }
            
        }

    }
    
    func saveFiles()
    {
        // Update imges
        // updateImgs()
        
        // Code for background saving process
        let bgQueue = OperationQueue()
        bgQueue.addOperation {
            // Create folder
            self.fm.createFolderIfNeeded()
            // Get Next cnt
            self.save_cnt = self.fm.getNextCnt(subDir: "depth_tiff")
            
            // Save FLIR Image
            if self.flir_on{
                if (self.flir_img != nil){
                    let path = self.fm.getPathForImage(name: "flir_jpg/IMG_\(self.save_cnt)")?.path
                    do
                    {
                        try self.flir_img.save(as:path!)
                    } catch{
                        print("Save failed \(error)")
                    }
                }
            }
            

            // Save iPhone jpg
            let rgb_path = self.fm.getPathForImageExt(subdir: "rgb_jpg", name: "IMG_\(self.save_cnt)", ext: "jpg")
            // let cameraResolution = Float2(Float(self.session.currentFrame?.camera.imageResolution.width ?? 0), Float(self.session.currentFrame?.camera.imageResolution.height ?? 0))
            
//            let targetSize = CGSize(width: Int(cameraResolution[1]), height: Int(cameraResolution[0]))
//            self.iPhone_rgb_img = self.iPhone_rgb_img.scalePreservingAspectRatio(
//                targetSize: targetSize
//            )
            
            self.fm.saveJpg(image: self.iPhone_rgb_img, path: rgb_path!)
            
            // Save iPhone Depth
            let depth_url = self.fm.getPathForImageExt(subdir: "depth_tiff", name: "IMG_\(self.save_cnt)", ext: "tiff")
            let context: CIContext! = CIContext()
            do {
                try context.writeTIFFRepresentation(of: self.depth_img, to: depth_url!, format: context.workingFormat, colorSpace: context.workingColorSpace!, options: [:])
            } catch {
                print("Save TIFF failed")
                print(error)
            }
            // @TODO: Save iPhone Point cloud *.ply file
            self.renderer.savePoints()
            
            // Process FLIR Image
            if self.flir_on{
                if (self.flir_img != nil){
                    //self.processFLIR()
                }
            }
            
            // Save GPS Coordinate, Roll, Pich, Yaw
            self.saveJson()
            
            
        }
        

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
            mtkView.framebufferOnly = true
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
        
        // Acc
//        if motionManager.isAccelerometerAvailable {
//            motionManager.accelerometerUpdateInterval = 0.01
//            motionManager.startAccelerometerUpdates(to: OperationQueue.main) { (data, error) in
//                print(data)
//            }
//        }
        
        // Roll pich yaw
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval  = 0.2
            motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (data, error) in
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
        let battery = FLIRBattery()
        self.flirBatt = battery
        //try? self.flirBatt?.subscribePercentage()
  
        
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
        guard let alt = manager.location?.altitude else { return }
        
        self.locValue = locValue
        self.altitude = alt
        self.timestamp = timestamp
        
        LatLabel.text = String(format:"Lat: %.6f", locValue.latitude)
        LonLabel.text = String(format:"Lon: %.6f", locValue.longitude)
        
        altitudeLabel.text = String(format:"H: %.2f", alt)

        //print("locations = \(locValue.latitude) \(locValue.longitude)")
    }
    
    // Motion
    func outputRPY(data: CMAttitude){
       roll    = data.roll * (180.0 / .pi)
       pitch   = data.pitch * (180.0 / .pi)
       yaw     = data.yaw * (180.0 / .pi)
       rollLabel.text  = String(format: "R:%.2f°", roll)
       pitchLabel.text = String(format: "P:%.2f°", pitch)
       yawLabel.text   = String(format: "Y:%.2f°", yaw)
   }
    

}


extension PointCloudViewController: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard session.currentFrame != nil else {return}
        renderer.drawRectResized(size: size)

    }
    

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
        
        // Point clouds
        guard let drawable = view.currentDrawable else {return}
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        guard let (textureY, textureCbCr) = session.currentFrame?.buildCapturedImageTextures(textureCache: textureCache) else {return}

        guard let (depthTexture, confidenceTexture) = session.currentFrame?.buildDepthTextures(textureCache: textureCache) else {return}

        guard let encoder = buildRenderEncoder(commandBuffer) else {return}
        
        renderer.update(commandBuffer, renderEncoder: encoder, capturedImageTextureY: textureY, capturedImageTextureCbCr: textureCbCr, depthTexture: depthTexture, confidenceTexture: confidenceTexture)
                
        commandBuffer.present(drawable)
        
        commandBuffer.commit()

        commandBuffer.waitUntilCompleted()
        
        // RGB, Depth
        updateImgs()
        //if myMetronome.enabled==false{
        //}
        
   
        
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
   
                    //self.thermal_img = thermal_image
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
                    
                    if let statistics = image.getStatistics() {
                        self.t_min = Double(statistics.getMin().asCelsius().value)
                        self.minLabel.text = String(format:"%.2f", self.t_min)
                        self.t_max = Double(statistics.getMax().asCelsius().value)
                        self.maxLabel.text = String(format:"%.2f", self.t_max)
                        self.t_average = Double(statistics.getAverage().asCelsius().value)
                        self.averageLabel.text = String(format:"%.2f", self.t_average)
                    }
                    
                    if let remoteControl = self.camera?.getRemoteControl(),
                       let fusionController = remoteControl.getFusionController() {
                        let distance = fusionController.getFusionDistance()
                        self.distanceLabel.text = "\((distance * 1000).rounded() / 1000)"
                        self.distanceSlider.value = Float(distance)
                    }
                    self.flir_img = image
                    //print(self.flirBatt?.getPercentage())
                    self.batteryLabel.text = String(format:"%d",50 )
                }
            }
        }
    }
    
}
