//
//  ViewController.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/01/07.
//

import RealityKit
import ARKit

import UIKit
import ThermalSDK


class DepthMapViewController: UIViewController {
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var depthImageView: UIImageView!
    
    
    // FLIR ///////////
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
    var depth_img: UIImage!
    var iPhone_rgb_img: UIImage!
    
    var save_cnt: Int = 0
    
    var shootingPeriodInt: Int = 1
    
    var shootingStart: Bool = false
    
    let fm:LocalFileManager = LocalFileManager.instance
    
    let renderQueue = DispatchQueue(label: "render")
    
    func requireCamera() {
        guard camera == nil else {
            return
        }
        let camera = FLIRCamera()
        self.camera = camera
        camera.delegate = self
    }

    @IBAction func connectDeviceClicked(_ sender: Any) {
        discovery?.start(.lightning)
    }

    @IBAction func disconnectClicked(_ sender: Any) {
        camera?.disconnect()
    }

    @IBAction func connectEmulatorClicked(_ sender: Any) {
        discovery?.start(.emulator)
    }

    @IBAction func distanceSliderValueChanged(_ sender: Any) {
        if let remoteControl = self.camera?.getRemoteControl(),
           let fusionController = remoteControl.getFusionController() {
            let newDistance = distanceSlider.value
            try? fusionController.setFusionDistance(Double(newDistance))
        }
    }
    
    @IBAction func periodSliderValueChanged(_ sender: UISlider)
    {
        self.shootingPeriodInt = Int(sender.value)
        self.shootingPeriodLabel.text = "\(self.shootingPeriodInt) sec"
        //print(self.shootingPeriodLabel.text)
    }
    // FLIR_END //////////
    
    var orientation: UIInterfaceOrientation {
        guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
            fatalError()
        }
        return orientation
    }
    
    @IBOutlet weak var imageViewHeight: NSLayoutConstraint!
    lazy var imageViewSize: CGSize = {
        CGSize(width: view.bounds.size.width, height: imageViewHeight.constant)
    }()

    override func viewDidLoad() {
        func buildConfigure() -> ARWorldTrackingConfiguration {
            let configuration = ARWorldTrackingConfiguration()

            configuration.environmentTexturing = .automatic
            if type(of: configuration).supportsFrameSemantics(.sceneDepth) {
               configuration.frameSemantics = .sceneDepth
            }

            return configuration
        }
        super.viewDidLoad()
        
        arView.session.delegate = self
        let configuration = buildConfigure()
        arView.session.run(configuration)
        
        // FLIR
        discovery = FLIRDiscovery()
        discovery?.delegate = self
        
        fm.createFolderIfNeeded()
        // FLIR End
    }

   
}



extension DepthMapViewController : ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let depth_ROI = CGRect(x: 0, y: 0, width: 480, height: 640)
        //self.depth_img = session.currentFrame?.depthMapTransformedImage(orientation: orientation, viewPort: depth_ROI)
        self.depth_img = session.currentFrame?.depthMapTransformedNormalizedImage(orientation: orientation, viewPort: depth_ROI)
        
        self.iPhone_rgb_img = frame.ColorTransformedImage(orientation: orientation, viewPort: depth_ROI)
        depthImageView.image = self.depth_img
    }
}

extension DepthMapViewController: FLIRDiscoveryEventDelegate {

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

extension DepthMapViewController : FLIRDataReceivedDelegate {
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

extension DepthMapViewController : FLIRStreamDelegate {
    
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
                    self.rgbimageView.image = self.rgb_img
                    
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
                        self.saveJpg(self.depth_img)
                    } catch{
                        print("Save failed \(error)")
                    }
                }
            }
        }
    }
    
    
    func documentDirectoryPath() -> URL? {
        let path = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)
        return path.first
    }
    
    func saveJpg(_ image: UIImage) {
        if let jpgData = image.jpegData(compressionQuality: 0.5),
            let path = documentDirectoryPath()?.appendingPathComponent("exampleJpg.jpg") {
            try? jpgData.write(to: path)
        }
    }
}
