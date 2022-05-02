//
//  ViewController.swift
//  FLIROneCameraSwift
//
//  Created by FLIR on 2020-08-13.
//  Copyright © 2020 FLIR Systems AB. All rights reserved.
//  Modified by Heesup Yun
//

import UIKit
import ThermalSDK


class ViewController: UIViewController {
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
    
    var save_cnt: Int = 0
    
    var shootingPeriodInt: Int = 1
    
    var shootingStart: Bool = false
    
    let fm:LocalFileManager = LocalFileManager.instance
    
    let renderQueue = DispatchQueue(label: "render")

    override func viewDidLoad() {
        super.viewDidLoad()

        discovery = FLIRDiscovery()
        discovery?.delegate = self
        
        fm.createFolderIfNeeded()
    }

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
}

extension ViewController: FLIRDiscoveryEventDelegate {

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

extension ViewController : FLIRDataReceivedDelegate {
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

func getPathForImage(name: String) -> URL?{
    guard
        let path = FileManager
            .default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("\(name).jpg") else
            {
                print("Error getting path")
                return nil
            }
    return path
}

class LocalFileManager{
    
    static let instance = LocalFileManager()
    
    var folder_name = ""
        
    init()
    {
        createFolderIfNeeded()
    }
    
    func setFolderName(inputName:String)
    {
        folder_name = inputName
    }
    
    func createFolderIfNeeded()
    {
        guard
            let path = FileManager
                .default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(folder_name)
                .path else
                {
                    return
                }
    
        if !FileManager.default.fileExists(atPath: path)
        {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                print("Success creating folder.")
            } catch let error {
                print("Error creating folder. \(error)")
            }
        }
    }
    func getFolderURL() -> URL?
    {
        guard
            let path = FileManager
                .default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(folder_name)
                else
                {
                    return nil
                }
        
            return path
    }
    
    func deleteFolder()
    {
        guard
            let path = FileManager
                .default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(folder_name)
                .path else
                {
                    return
                }
        
        do {
            try FileManager.default.removeItem(atPath: path)
            print("Success deleting folder.")
        } catch let error {
            print("Error deleting folder.\(error)")
        }
    }
    
    func saveImage(image:UIImage, name:String) -> String
    {
        //image.jpegData(compressionQuality: 1.0)
        guard
            let data = image.jpegData(compressionQuality: 1.0),
            let path = getPathForImage(name: name)
        
                else{
                print("Error getting data.")
                return "Error getting data."
            }
        // URL for raw data that cannot be regenerated
        //let directory = FileManager.default.urls(for: .documentDirectory, in:.userDomainMask)
        // Can be regenerated
        //let directory2 = FileManager.default.urls(for: .cachesDirectory, in:.userDomainMask).first
        //let directory3 = FileManager.default.temporaryDirectory
        //let path = directory2?.appendingPathComponent("\(name).jpg")
        //print(directory)
        
        do{
            try data.write(to: path)
            print("Success saving!")
            return "Success saving!"
            
        } catch let error{
            print("Error saving. \(error)")
            return "Error saving. \(error)"
        }
        
    }
    
    
    func getImage(name: String) -> UIImage?{
        guard
            let path = getPathForImage(name: name)?.path,
                FileManager.default.fileExists(atPath: path) else{
                    print("Error getting path")
                    return nil
                }
        print(path)
        return UIImage(contentsOfFile: path)
        
    }
    
    func deleteImage(name: String) -> String
    {
        guard
            let path = getPathForImage(name: name)?.path,
            FileManager.default.fileExists(atPath: path) else{
                    print("Error getting path")
                return "Error getting path"
                }
        do {
            try FileManager.default.removeItem(atPath: path)
            print("Sucessfully deleted.")
            return "Sucessfully deleted."
        } catch let error {
            print("Error deleting image \(error)")
            return "Error deleting image \(error)"
        }
    }
    
    func getPathForImage(name: String) -> URL?{
        guard
            let path = FileManager
                .default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(folder_name)
                .appendingPathComponent("\(name).jpg") else
                {
                    print("Error getting path")
                    return nil
                }
        return path
    }
    
    func getPathForImagePNG(name: String) -> URL?{
        guard
            let path = FileManager
                .default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(folder_name)
                .appendingPathComponent("\(name).png") else
                {
                    print("Error getting path")
                    return nil
                }
        return path
    }
}

extension ViewController : FLIRStreamDelegate {
    
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