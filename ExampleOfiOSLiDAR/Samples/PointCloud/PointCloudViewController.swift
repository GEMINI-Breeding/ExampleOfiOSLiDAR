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

// Bluetooth
import CoreBluetooth

import UniformTypeIdentifiers
import MobileCoreServices

class PointCloudViewController: UIViewController, UIGestureRecognizerDelegate, CLLocationManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {

    
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
    
    //@IBOutlet weak var centerSpotLabel: UILabel!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var distanceSlider: UISlider!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var rgbimageView: UIImageView!
    @IBOutlet weak var confiimageView: UIImageView!
    
    @IBOutlet weak var shootingPeriodLabel: UILabel!
    @IBOutlet weak var shootingPeriodSlider: UISlider!
    

    var thermalStreamer: FLIRThermalStreamer?
    var stream: FLIRStream?
    var fusion: FLIRFusion?
    
    var flir_img: FLIRThermalImage!
    
    var saveCnt: Int = 0
    
    var shootingPeriodInt: Int = 1
    
    var shootingStart: Bool = false
    
    let fm:LocalFileManager = LocalFileManager.instance
    
    let renderQueue = DispatchQueue(label: "render")

    var flir_on: Bool = false
    
    var pm:FLIRPaletteManager = FLIRPaletteManager.init()
    var t_min:Double!
    var t_max:Double!
    var t_average:Double!
    var batteryPercent: Double! = Double(0.0)
    var batteryPercenPrev: Double! = Double(-1)
    var batteryStartTime:Double!
    var batteryConsumeRate: Double! = Double(100.0 / 60.0) // 100 percent per 60min
    var batteryTimeDiff:Double! = 0.0
    
    let batteryStopWatch:Stopwatch! = Stopwatch()
    @IBOutlet weak var minLabel: UILabel!
    @IBOutlet weak var maxLabel: UILabel!
    @IBOutlet weak var averageLabel: UILabel!
    @IBOutlet weak var batteryLabel: UILabel!
    let thermalImage:FLIRThermalImageFile! = FLIRThermalImageFile()
    // FLIR
    
    var location: CLLocation!
    let locationManager = CLLocationManager()
    var locValue =  CLLocationCoordinate2D()
    //@IBOutlet weak var LatLabel: UILabel!
    //@IBOutlet weak var LonLabel: UILabel!
    @IBOutlet weak var altitudeLabel: UILabel!
    var altitude: Double = 0.0
    var locationTimestamp: Date = Date()
    //var timeIntervalSince1970: Date = Date()
    
    var motionManager    = CMMotionManager()
    var roll = 0.0
    var pitch = 0.0
    var yaw = 0.0
    @IBOutlet weak var rollLabel: UILabel!
    @IBOutlet weak var pitchLabel: UILabel!
    @IBOutlet weak var yawLabel: UILabel!
    //////////
    var depth_img: CIImage!
    var confi_img: CIImage!
    var rgb_img: UIImage!
    @IBOutlet weak var depthImageView: UIImageView!
    var iPhone_rgb_img: UIImage!
    @IBOutlet weak var iPhone_rgb_imgView: UIImageView!
    ///////////
    
    // Metronome - Timelapse
    @IBOutlet weak var bpmLabel: UILabel!
    @IBOutlet weak var tickLabel: UILabel!
    var timerOn:Bool = false
    var saveNow:Bool = false
    var saveNowFlir:Bool = false
    var saveTimer:Stopwatch = Stopwatch()
    var saveImgQueue:OperationQueue = OperationQueue()
    
    // Point cloud
    var isSavingFile = false
    private lazy var library: MTLLibrary = device.makeDefaultLibrary()!
    
    let myMetronome = Metronome()
    
    // Bluetooth
    @IBOutlet weak var humidity: UILabel!
    @IBOutlet weak var humidityLabel: UILabel!
    @IBOutlet weak var temperature: UILabel!
    @IBOutlet weak var temperatureLabel: UILabel!
    @IBOutlet weak var connectionStatus: UILabel!
   
    var humidityValue = 0.0
    var temperatureValue = 0.0
    var dataShown = false
    var centralManager:CBCentralManager!
    var sensorPeripheral: CBPeripheral!
    var bluetoothReady = false
    let serviceUUID = CBUUID(string: "0000ffe0-0000-1000-8000-00805f9b34fb")        // Default HM-10 service UUID
    let characteristicUUID = CBUUID(string: "0000ffe1-0000-1000-8000-00805f9b34fb") // Default HM-10 characteristic UUID
    let deviceName = "HMSoft"
    
    // Bluetooth
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        myMetronome.onTick = { (nextTick) in
            // Save functions..
            self.saveFiles()
            self.animateTick()
        }
        updateBpm()
    }

    private func animateTick() {
        tickLabel.alpha = 1.0
        UIView.animate(withDuration: 0.35) {
            self.tickLabel.alpha = 0.0
            self.tickLabel.text = String(format: "# %d", self.saveCnt)
        }
    }

    @IBAction func startMetronome(_ sender: AnyObject) {
//        if myMetronome.enabled{
//            myMetronome.enabled = false
//            sender.setTitle("Start Rec.", for: [])
//        }else{
//            myMetronome.enabled = true
//            sender.setTitle("Stop Rec.", for: [])
//        }
        
        if self.timerOn{
            self.timerOn = false
            sender.setTitle("Start Rec.", for: [])
        }else{
            self.timerOn = true
            sender.setTitle("Stop Rec.", for: [])
        }
        
    }

    @IBAction func stopMetronome(_: Any?) {
        //myMetronome.enabled = false
        
        // Stop new task
        self.timerOn = false
        
        // Wait previous task
        self.saveImgQueue.waitUntilAllOperationsAreFinished()
    }

    
    @IBAction func periodSliderValueChanged(_ sender: UISlider)
    {
        self.shootingPeriodInt = Int(sender.value)
        myMetronome.bpm = 60 / Float(self.shootingPeriodInt)
        print(myMetronome.bpm)
        updateBpm()
    }
    
    @IBAction func manualCapture(_: Any?) {
        //saveFiles()
        self.saveNow = true
        animateTick()
    }
    
    private func updateBpm() {
        //let metronomeBpm = Int(myMetronome.bpm)
        //bpmLabel.text = "\(metronomeBpm)"
        self.shootingPeriodLabel.text = "\(self.shootingPeriodInt) sec"
    }
    
    func reset_sliders()
    {
        shootingPeriodSlider.minimumValue = 0
        shootingPeriodSlider.maximumValue = 10
        shootingPeriodSlider.value = 5
    }
    
    func genFileName() -> String{
        let name = String(format: "\(self.fm.genTodayName())_IMG_%05d", self.saveCnt)
        return name
    }
    
    func saveJson(){
        //print("locations = \(self.locValue.latitude) \(self.locValue.longitude)")
        //print(self.altitude)

        // let cameraResolution = Float2(Float(self.session.currentFrame?.camera.imageResolution.width ?? 0), Float(self.session.currentFrame?.camera.imageResolution.height ?? 0))
        let iCamIntrinsics = self.session.currentFrame?.camera.intrinsics.transpose // Change columns to rows
        let iCamIntrinsicsString = String(format: "[[%f,%f,%f],[%f,%f,%f],[%f,%f,%f]]",
                                    (iCamIntrinsics![0][0]),
                                    (iCamIntrinsics![0][1]),
                                    (iCamIntrinsics![0][2]),
                                    (iCamIntrinsics![1][0]),
                                    (iCamIntrinsics![1][1]),
                                    (iCamIntrinsics![1][2]),
                                    (iCamIntrinsics![2][0]),
                                    (iCamIntrinsics![2][1]),
                                    (iCamIntrinsics![2][2])
                                    )
        //@TODO: Add more metadata
        let personArray =  ["info": ["epochTime": "\(Date().timeIntervalSince1970)", "FLIRBatteryPercent": "\(self.batteryPercent!)",
                                    "iCamIntrinsics": iCamIntrinsicsString],
                            "climate": ["temperature": "\(self.temperatureValue)", "RH": "\(self.humidityValue)"],
                            "gps": ["timestamp": "\(self.locationTimestamp)", "latitude": "\(self.locValue.latitude)", "longitude": "\(self.locValue.longitude)", "altitude": "\(self.altitude)"],
                            "attitude": ["roll": "\(self.roll)", "pitch": "\(self.pitch)", "yaw": "\(self.yaw)"],
                            "thermal": ["min": self.t_min, "max": self.t_max, "avg": self.t_average],
                            ]
        
        // Get the url of Persons.json in document directory
        let fileUrl = self.fm.getPathForImageExt(subdir: "meta_json", name: genFileName(), ext: "json")
        
        // Create a write-only stream
        guard let stream = OutputStream(toFileAtPath: fileUrl!.path, append: false) else { return }
        stream.open()
        defer {
            stream.close()
        }

        // Transform array into data and save it into file
        var error: NSError?
        JSONSerialization.writeJSONObject(personArray, to: stream, options: [.prettyPrinted, .sortedKeys], error: &error)

        // Handle error
        if let error = error {
            print(error)
        }
    }
    
    func updateImgs()
    {
        
        // Update images
        
        // iPhone RGB & Depth
        let depth_ROI = CGRect(x: 0, y: 0, width: 1440, height: 1920)
        //self.iPhone_rgb_img = session.currentFrame?.ColorTransformedImage(orientation: tiffOrientation)
        self.iPhone_rgb_img = session.currentFrame?.ColorTransformedImage(orientation: orientation, viewPort: depth_ROI)
        self.iPhone_rgb_imgView.image = self.iPhone_rgb_img
        
        //self.depth_img = session.currentFrame?.depthMapTransformedImage(orientation: orientation, viewPort: depth_ROI)
        //self.depth_img = session.currentFrame?.depthMapTransformedNormalizedImage(orientation: orientation, viewPort: depth_ROI)
        //guard let pixelBuffer = session.currentFrame?.sceneDepth?.depthMap else { return }
        //self.depth_img = CIImage(cvPixelBuffer: pixelBuffer).oriented(tiffOrientation)
        self.depth_img = session.currentFrame?.depthMapTransformedImageCIImage(orientation: tiffOrientation)
        self.depthImageView.image = session.currentFrame?.depthMapTransformedNormalizedImage(orientation: orientation, viewPort: depth_ROI)
        
        //self.confi_img = session.currentFrame?.ConfidenceMapRawImage(orientation: tiffOrientation)
        let confiBuff = session.currentFrame?.ConfidenceMapRawBuffer(orientation: tiffOrientation)
        if (confiBuff != nil){
            self.confi_img = CIImage(cvPixelBuffer: confiBuff!).oriented(tiffOrientation)
            //self.confiimageView.image = session.currentFrame?.ConfidenceMapTransformedImage(orientation: orientation, viewPort: depth_ROI)
            self.confiimageView.image = session.currentFrame?.ConfidenceMapTransformedRawImage(pixelBuffer: confiBuff!, orientation: orientation, viewPort: depth_ROI)
        }
           
    }
    
    func processFLIR(){
        
        //let thermalImage = FLIRThermalImageFile()
        
        let path = self.fm.getPathForImageExt(subdir: "flir_jpg", name: genFileName(), ext: "jpg")?.path
        
        if FileManager.default.fileExists(atPath: path!)
        {
            thermalImage.open(path!)
            thermalImage.setTemperatureUnit(.CELSIUS)
            
            let theFileName = (path! as NSString).lastPathComponent
            let ir_name = theFileName.replacingOccurrences(of: ".jpg", with: "_IR")
            let rgb_name = theFileName.replacingOccurrences(of: ".jpg", with: "_RGB")
            
            let ir_path = self.fm.getPathForImageExt(subdir: "flir_processed", name: ir_name, ext: "jpg")
            let rgb_path = self.fm.getPathForImageExt(subdir: "flir_processed", name: rgb_name, ext: "jpg")
            
            
            if let fusion = thermalImage.getFusion() {
                //fusion.setFusionMode(FUSION_MSX_MODE)
                //msxImageView.image = thermalImage.getImage()

                fusion.setFusionMode(IR_MODE)
                //print(thermalImage.palette?.name)
                //thermalImage.palette = FLIRPalette.init()
                thermalImage.palette = self.pm.gray
                //print(thermalImage.palette?.name)
                
                let ir_image = thermalImage.getImage()!
                //let new_ir_image = ir_image.rotate(radians: 0) // Rotate 180 degrees
                //self.fm.savePng(image: ir_image, path: ir_path!)
                self.fm.saveJpg(image: ir_image, path: ir_path!, location: self.location, roll: self.roll,pitch: self.pitch,yaw: self.yaw)
                
                fusion.setFusionMode(VISUAL_MODE)
                let rgb_image = thermalImage.getImage()!
                //let new_rgb_image = rgb_image.rotate(radians: 0) // Rotate 180 degrees
                //self.fm.savePng(image: rgb_image, path: rgb_path!)
                self.fm.saveJpg(image: rgb_image, path: rgb_path!, location: self.location, roll: self.roll,pitch: self.pitch,yaw: self.yaw)
            }
            
            if let statistics = thermalImage.getStatistics() {
                self.t_min = Double(statistics.getMin().asCelsius().value)
                self.t_max = Double(statistics.getMax().asCelsius().value)
                self.t_average = Double(statistics.getAverage().asCelsius().value)
            }
            
        }

    }
    
    func saveFiles()
    {
        // Save iPhone jpg
        let rgb_path = self.fm.getPathForImageExt(subdir: "rgb_jpg", name: genFileName(), ext: "jpg")
        
        self.fm.saveJpg(image: self.iPhone_rgb_img, path: rgb_path!, location: self.location, roll: self.roll,pitch: self.pitch,yaw: self.yaw)
        
        // Save iPhone Depth
        let depth_url = self.fm.getPathForImageExt(subdir: "depth_tiff", name: genFileName(), ext: "tiff")
        let context: CIContext! = CIContext()
        do {
            try context.writeTIFFRepresentation(of: self.depth_img, to: depth_url!, format: context.workingFormat, colorSpace: context.workingColorSpace!, options: [:])
        } catch {
            print("Save TIFF failed")
            print(error)
        }
        
        let confidence_url = self.fm.getPathForImageExt(subdir: "confidence_tiff", name: genFileName(), ext: "tiff")
        do {
            try context.writeTIFFRepresentation(of: self.confi_img, to: confidence_url!, format: context.workingFormat, colorSpace: context.workingColorSpace!, options: [:])
        } catch {
            print("Save TIFF failed")
            print(error)
        }
        
        // @TODO: Save iPhone Point cloud *.ply file
        // self.renderer.savePoints()
        // Save GPS Coordinate, Roll, Pich, Yaw
        self.saveJson()
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
                //configuration.frameSemantics =  [.sceneDepth, .smoothedSceneDepth]
                
                // Disable Auto focus
                if configuration.isAutoFocusEnabled{
                    configuration.isAutoFocusEnabled = false
                }
                
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
        
        
        // Bluetooth
        startUpCentralManager()
        
    }
    
    // Bluetooth
    override func didReceiveMemoryWarning() {
        
        super.didReceiveMemoryWarning()
        
    }
    
    func preferredStatusBarStyle() -> UIStatusBarStyle {

        return UIStatusBarStyle.lightContent

    }

    func startUpCentralManager(){
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
    }
    
    func sensorTagFound (advertisementData: [NSObject : AnyObject]!) -> Bool {
        
        let nameOfDeviceFound = (advertisementData as NSDictionary).object(forKey: CBAdvertisementDataLocalNameKey) as? NSString
        return (nameOfDeviceFound! as String == self.deviceName)
        
    }
    
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [NSObject : AnyObject], RSSI: NSNumber) {
        
        if self.sensorTagFound(advertisementData: advertisementData) == true {
            self.centralManager.stopScan()
            self.sensorPeripheral = peripheral
            self.sensorPeripheral.delegate = self
            self.centralManager.connect(peripheral, options: nil)
        }
        else {
            print("Not Found")
        }
        
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Function: \(#function),Line: \(#line)")
        
        //      if peripheralArray.contains(peripheral) {
        //          print("Duplicate Found.")
        //      } else {
        //        peripheralArray.append(peripheral)
        //        rssiArray.append(RSSI)
        //      }
        //
        //      peripheralFoundLabel.text = "Peripherals Found: \(peripheralArray.count)"
        self.centralManager.stopScan()
        self.sensorPeripheral = peripheral
        self.sensorPeripheral.delegate = self
        self.centralManager.connect(peripheral, options: nil)
        
        print("Peripheral Discovered: \(peripheral)")

    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        self.connectionStatus.text = "Discovering peripheral services"
        peripheral.discoverServices([serviceUUID])
    }
    
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        self.connectionStatus.text = "Disconnected"
        central.scanForPeripherals(withServices: nil, options: nil)
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        self.connectionStatus.text = "Looking at peripheral services"
        for service in peripheral.services! {
            let thisService = service as CBService
            if thisService.uuid == self.serviceUUID {
                peripheral.discoverCharacteristics(nil, for: thisService)
            }
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        self.connectionStatus.text = "Waiting for data"
               
        for charateristic in service.characteristics! {
            let thisCharacteristic = charateristic as CBCharacteristic
            if thisCharacteristic.uuid == self.characteristicUUID {
                self.sensorPeripheral.setNotifyValue(true, for: thisCharacteristic)
            }
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        self.connectionStatus.text = "Connected"
        
        let humidity = HomeSense.getHumidity(value: characteristic.value!)
        let temperature = HomeSense.getTemperature(value: characteristic.value!)
        
        self.humidityValue = Double(humidity)!
        self.temperatureValue = Double(temperature)!
        
        self.temperature.text = "Air T:\(temperature) °C"
        self.humidity.text = "RH:\(humidity) %"
        
        // Eye candy ;-)
        
//        if !self.dataShown {
//
//            self.temperature.layer.position.y += 80
//            self.humidity.layer.position.y -= 80
//
//            UIView.animate(withDuration: 0.5, animations: {
//                self.temperatureLabel.alpha = 1.0
//            })
//
//            UIView.animate(withDuration: 0.5, delay: 0.2, options: [], animations: {
//                self.humidityLabel.alpha = 1.0
//                }, completion: nil)
//
//            UIView.animate(withDuration: 0.5, delay: 0.4, options: [], animations: {
//                self.temperature.alpha = 1.0
//                self.temperature.layer.position.y -= 80
//                }, completion: nil)
//
//            UIView.animate(withDuration: 0.5, delay: 0.4, options: [], animations: {
//                self.humidity.alpha = 1.0
//                self.humidity.layer.position.y += 80
//                }, completion: nil)
//
//            UIView.animate(withDuration: 0.5, delay: 0.1, options: [], animations: {
//                self.connectionStatus.alpha = 0.0
//            }, completion: nil)
//
//            self.dataShown = true
//        }
        
    }
    
    func dissconnectDevice() {
        centralManager.stopScan()
        if((sensorPeripheral) != nil){
            centralManager.cancelPeripheralConnection(sensorPeripheral)
        }
    }
    
    func stopScanning() -> Void {
        self.connectionStatus.text = ""
        centralManager?.stopScan()
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        var msg = ""
        switch (central.state) {
        case .poweredOff:
            msg = "BLE hardware is powered off"
        case .poweredOn:
            msg = "BLE hardware is ready"
            bluetoothReady = true;
        case .resetting:
            msg = "BLE hardware is resetting"
        case .unauthorized:
            msg = "BLE state is unauthorized"
        case .unknown:
            msg = "BLE state is unknown"
        case .unsupported:
            msg = "BLE hardware is unsupported on this platform"
        }

        self.connectionStatus.text = msg
        
        if bluetoothReady {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
        
    }
    // Bluetooth
    
    
    // FLIR
    func requireCamera() {
        guard camera == nil else {
            return
        }
        let camera = FLIRCamera()
        self.camera = camera
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
        self.batteryStopWatch.start()
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
        self.location = manager.location
        guard let locValue: CLLocationCoordinate2D = manager.location?.coordinate else { return }
        guard let timestamp: Date = manager.location?.timestamp else { return }
        guard let alt = manager.location?.altitude else { return }
        
        self.locValue = locValue
        self.altitude = alt
        self.locationTimestamp = timestamp
        
//        LatLabel.text = String(format:"Lat: %.6f", locValue.latitude)
//        LonLabel.text = String(format:"Lon: %.6f", locValue.longitude)

        altitudeLabel.text = String(format:"H: %.2fm", alt)

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
        


        if self.timerOn{
            // Check queue empty and flir save ends
            if self.saveImgQueue.operationCount==0 && self.saveNowFlir == false{
                // Check time
                self.saveTimer.stop()
                if self.saveTimer.durationSeconds() > Double(self.shootingPeriodInt){
                    self.saveNow = true
                    self.updateImgs()
                    // tick animation
                    self.animateTick()
                    self.shootingPeriodLabel.text = String(format: "%.2f sec", self.saveTimer.durationSeconds())
                    self.saveTimer.start()
                }
            }
            else{
                return
            }
        }
        else{
            self.saveTimer.start()
            self.updateImgs()
        }
        
        
        //if self.timerOn == false || (self.timerOn == true && self.saveNow){
        if self.timerOn == false{ // Do not update while recording
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
        }
        
        // Work for manual & timer capture
        if self.saveNow{
            // Create folder
            self.fm.createFolderIfNeeded()
            // Update frame count
            self.saveCnt = self.fm.getNextCnt(subDir: "meta_json")
            
            // Send flag to FLIR
            if self.flir_on{
                // Save flag for flir
                self.saveNowFlir = true
            }
            
            // Add operation
            self.saveImgQueue.addOperation {
                // Save file
                self.saveFiles()
            }
            
            // Turn off saveNow flag after addOperation
            self.saveNow = false
        }
   
        
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
                    
                    self.flir_on = true
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
        
        if self.timerOn == false || (self.timerOn == true && self.saveNowFlir){
            renderQueue.async {
                
                // Update display while not recording
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
                        //self.rgb_img = image.getPhoto()
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
//                            if let spot = measurements.getAllSpots().first {
//                                self.centerSpotLabel.text = spot.getValue().description()
//                            }
                        }
                        
                        if let statistics = image.getStatistics() {
                            self.t_min = Double(statistics.getMin().asCelsius().value)
                            self.minLabel.text = String(format:"%.2f", self.t_min)
                            self.t_max = Double(statistics.getMax().asCelsius().value)
                            self.maxLabel.text = String(format:"%.2f", self.t_max)
                            self.t_average = Double(statistics.getAverage().asCelsius().value)
                            self.averageLabel.text = String(format:"%.2f", self.t_average)
                        }
                        
//                        if let remoteControl = self.camera?.getRemoteControl(),
//                           let fusionController = remoteControl.getFusionController() {
//                            let distance = fusionController.getFusionDistance()
//                            self.distanceLabel.text = "\((distance * 1000).rounded() / 1000)"
//                            self.distanceSlider.value = Float(distance)
//                        }
                        
                        // Update battery info
                        if let remoteControl = self.camera?.getRemoteControl(){
                            let batt = remoteControl.getBattery()
                            let percent = batt?.getPercentage()
                            var estimatedTime:Double = 0.0
                            
                            if percent! > 0{
                                self.batteryPercent = Double(percent!)
                                if self.batteryPercent < self.batteryPercenPrev{
                                    self.batteryStopWatch.stop()
                                    self.batteryTimeDiff = self.batteryStopWatch.durationSeconds()
                                    if self.batteryTimeDiff > 0.0 {
                                        let consumRate = ((self.batteryPercenPrev - self.batteryPercent) / self.batteryTimeDiff) * 60.0 // Consume per min
                                        self.batteryConsumeRate = (self.batteryConsumeRate + consumRate) / 2.0
                                    }
                                    self.batteryStopWatch.start()
                                    
                                }
                                self.batteryPercenPrev = self.batteryPercent
                                
                                estimatedTime = Double(self.batteryPercent) / self.batteryConsumeRate
                                self.batteryLabel.text = String(format:"FLIR:%d %% (%.1lf min left)", percent!, estimatedTime)
                            }
                        }
                        
                        self.flir_img = image
                    }
                    
                    
                    if self.saveNowFlir{
                        //let path = self.fm.getPathForImage(name: "flir_jpg/\(self.fm.genTodayName())_IMG_\(self.saveCnt)")?.path
//                        let path = self.fm.getPathForImageExt(subdir: "flir_jpg", name: self.genFileName(), ext: "jpg")?.path
//                        do
//                        {
//                            try self.flir_img.save(as:path!)
//                            self.processFLIR()
//                        } catch{
//                            print("Save failed \(error)")
//                        }
                        self.saveNowFlir = false
                    }
                    
                }
            }
        }
        
    }
}

public class Stopwatch {
    public init() { }
    private var start_: TimeInterval = 0.0;
    private var end_: TimeInterval = 0.0;

    public func start() {
        start_ = NSDate().timeIntervalSince1970;
    }

    public func stop() {
        end_ = NSDate().timeIntervalSince1970;
    }

    public func durationSeconds() -> TimeInterval {
        return end_ - start_;
    }
}


func addLocation(_ location: CLLocation, roll:Double, pitch:Double, yaw:Double, toImage image: UIImage) -> Dictionary<String, Any> {

    /// Initializing the metaData dict
    var metaData: Dictionary<String, Any> = [:]

    /// Check if image already have its meta data
    if let ciImage = image.ciImage {
        metaData = ciImage.properties
    }

    /// Initializing the gpsData dict
    var gpsData: Dictionary<String, Any> = [:]
    var attiData: Dictionary<String, Any> = [:]

    /// Check if there is any gps information
    if let gps = metaData[kCGImagePropertyGPSDictionary as String] as? Dictionary<String, Any> {
        gpsData = gps
        attiData = gps
    }

    /// Adding all the required information to gpsData dictionary
    // #1. Data & Time
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    let localDate = dateFormatter.string(from: location.timestamp)
    //gpsData[kCGImagePropertyGPSTimeStamp as String] = localDate
    gpsData[(kCGImagePropertyGPSTimeStamp as String)] = location.timestamp.isoTime()
    gpsData[(kCGImagePropertyGPSDateStamp as String)] = location.timestamp.isoDate()
    gpsData[(kCGImagePropertyGPSVersion as String)] = "2.2.0.0"
    
    // #2. Latitude, Longitude
    var latitude  = location.coordinate.latitude
    var longitude = location.coordinate.longitude
    var latRef = ""
    var lngRef = ""
    if latitude < 0.0 {
        latitude *= -1.0
        latRef = "S"
    } else  {
        latRef = "N"
    }

    if longitude < 0.0 {
        longitude *= -1.0
        lngRef = "W"
    }
    else {
        lngRef = "E"
    }

    gpsData[kCGImagePropertyGPSLatitudeRef as String] = latRef
    gpsData[kCGImagePropertyGPSLongitudeRef as String] = lngRef
    gpsData[kCGImagePropertyGPSLatitude as String] = latitude
    gpsData[kCGImagePropertyGPSLongitude as String] = longitude
    
    
    

    // #3. Accuracy
    // gpsData[kCGImagePropertyGPSDOP as String] = location.horizontalAccuracy
    gpsData[kCGImagePropertyGPSHPositioningError as String] = location.horizontalAccuracy
    

    // #4. Altitude
    gpsData[kCGImagePropertyGPSAltitude as String] = location.altitude
    
    //print(gpsData)
    
    /// You can add what more you want to add into gpsData and after that
    /// Add this gpsData information into metaData dictionary
    metaData[kCGImagePropertyGPSDictionary as String] = gpsData
    
    attiData["RollDegree"] = roll
    attiData["PitchDegree"] = pitch
    attiData["YawDegree"] = yaw
    //print(attiData)
    metaData[kCGImagePropertyRawDictionary as String] = attiData
    
    // print(metaData)

    return metaData
}




extension Date {

    func isoDate() -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.dateFormat = "yyyy:MM:dd"
        return f.string(from: self)
    }

    func isoTime() -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.dateFormat = "HH:mm:ss.SSSSSS"
        return f.string(from: self)
    }
}
