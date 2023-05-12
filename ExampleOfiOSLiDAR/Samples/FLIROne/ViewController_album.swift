//
//  ViewController.swift
//  OpenImageSampleSwift
//
//  Created by FLIR on 2020-08-17.
//  Copyright © 2020 FLIR Systems AB. All rights reserved.
//

import UIKit
import ThermalSDK


extension UIImage {
    convenience init?(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) {
            let rect = CGRect(origin: .zero, size: size)
            UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
            color.setFill()
            UIRectFill(rect)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            guard let cgImage = image?.cgImage else { return nil }
            self.init(cgImage: cgImage)
          }
    
    func rotate(radians: Float) -> UIImage? {
        var newSize = CGRect(origin: CGPoint.zero, size: self.size).applying(CGAffineTransform(rotationAngle: CGFloat(radians))).size
        // Trim off the extremely small float value to prevent core graphics from rounding it up
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        let context = UIGraphicsGetCurrentContext()!

        // Move origin to middle
        context.translateBy(x: newSize.width/2, y: newSize.height/2)
        // Rotate around middle
        context.rotate(by: CGFloat(radians))
        // Draw the image at its center
        self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2, width: self.size.width, height: self.size.height))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
    

}

extension UIColor {
    func image(_ size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            self.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}

class ViewController_album: UIViewController {

    @IBOutlet weak var msxImageView: UIImageView!
    @IBOutlet weak var irImageView: UIImageView!
    @IBOutlet weak var visualImageView: UIImageView!

    @IBOutlet weak var minLabel: UILabel!
    @IBOutlet weak var maxLabel: UILabel!
    @IBOutlet weak var averageLabel: UILabel!
    @IBOutlet weak var spotLabel: UILabel!
    
    let fm:LocalFileManager = LocalFileManager.instance
    var fileURLs: [URL] = []
    var pm:FLIRPaletteManager = FLIRPaletteManager.init()
    var cnt:Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()

        //guard let imagePath = Bundle.main.path(forResource: "IMG_0051", ofType: "jpg") else {
        //guard let imagePath = getPathForImage(name:"Example")?.path else {
        self.fm.setFolderName(inputName: "2022_06_09/flir_jpg")
        //self.fm.setFolderName(inputName: "2022-03-01-LidarMatching")
        //self.fm.setFolderName(inputName: "./")
        
       
        
        
        guard let fileEnumerator = FileManager.default.enumerator(at: self.fm.getFolderURL()!, includingPropertiesForKeys: nil, options: FileManager.DirectoryEnumerationOptions()) else { return }
        
        let fileManager = FileManager.default
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: self.fm.getFolderURL()!, includingPropertiesForKeys: nil)
            // process files
            print(fileURLs)
            self.fileURLs = fileURLs

        } catch {
            print("Error while enumerating files \(self.fm.getFolderURL()!.path): \(error.localizedDescription)")
        }
        
 
        
        guard let imagePath = self.fileURLs.first?.path else {
            return
        }
        let thermalImage = FLIRThermalImageFile()
        thermalImage.open(imagePath)

        thermalImage.setTemperatureUnit(.CELSIUS)
        
        
        if let fusion = thermalImage.getFusion() {
            fusion.setFusionMode(FUSION_MSX_MODE)
            //msxImageView.image = thermalImage.getImage()

            fusion.setFusionMode(IR_MODE)
            irImageView.image = thermalImage.getImage()

            fusion.setFusionMode(VISUAL_MODE)
            visualImageView.image = thermalImage.getImage()
        }

        if let statistics = thermalImage.getStatistics() {
            let min = statistics.getMin()
            minLabel.text = "\(min)"
            let max = statistics.getMax()
            maxLabel.text = "\(max)"
            let average = statistics.getAverage()
            averageLabel.text = "\(average)"
        }
        if let spot = thermalImage.measurements?.getAllSpots().first {
            spotLabel.text = "\(spot.getValue())"
        }
        
        self.fm.setFolderName(inputName: "\(self.fm.folder_name)")
        //self.fm.createFolderIfNeeded()
     
    }
    
    @IBAction func processImage(_ sender: Any) {
        
        //for file in fileURLs
        for index in 1...100
        {
            if (self.cnt < fileURLs.count){
                
                let file = fileURLs[self.cnt]
                self.cnt += 1
                
                
                print(file)
                let thermalImage = FLIRThermalImageFile()
                thermalImage.open(file.path)
                thermalImage.setTemperatureUnit(.CELSIUS)

                let theFileName = (file.path as NSString).lastPathComponent
                let ir_name = theFileName.replacingOccurrences(of: ".jpg", with: "_IR")
                let rgb_name = theFileName.replacingOccurrences(of: ".jpg", with: "_RGB")
                let ir_path = self.fm.getPathForImageExt(subdir:"../flir_jpg_processed", name: "\(ir_name)",ext:"jpg")
                let rgb_path = self.fm.getPathForImageExt(subdir:"../flir_jpg_processed", name: "\(rgb_name)",ext:"jpg")
                
                
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
                    let new_ir_image = ir_image.rotate(radians: .pi) // Rotate 180 degrees
                    irImageView.image = new_ir_image
                    //saveJpg(image: ir_image, path: ir_path!)
                    //savePng(image: new_ir_image!, path: ir_path!)


                    fusion.setFusionMode(VISUAL_MODE)
                    let rgb_image = thermalImage.getImage()!
                    //let rgb_image = UIColor.orange.image(CGSize(width: 480, height: 640))
                    let new_rgb_image = rgb_image.rotate(radians: .pi) // Rotate 180 degrees
                    visualImageView.image = new_rgb_image
                    saveJpg(image: rgb_image, path: rgb_path!)
                    //savePng(image: new_rgb_image!, path: rgb_path!)
                }
                
                if let statistics = thermalImage.getStatistics() {
                    let min = statistics.getMin()
                    minLabel.text = "\(min)"
                    let max = statistics.getMax()
                    maxLabel.text = "\(max)"
                    let average = statistics.getAverage()
                    averageLabel.text = "\(average)"
                }
                if let spot = thermalImage.measurements?.getAllSpots().first {
                    spotLabel.text = "\(spot.getValue())"
                }
                
                //usleep(10000) //will sleep for 0.1 second
                
            }
            else
            {
                print("Last file!")
                break
            }
        }
        
        
    }

    
    func savePng(image: UIImage, path: URL) {
        if let pngData = image.pngData()
           {
            try? pngData.write(to: path)
        }
    }
    
    func saveJpg(image: UIImage, path: URL) {
        if let jpgData = image.jpegData(compressionQuality: 1.0)
        {
            try? jpgData.write(to: path)
        }
    }
}

