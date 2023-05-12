//
//  LocalFileManager.swift
//  ExampleOfiOSLiDAR
//
//  Created by Heesup Yun on 5/5/22.
//

import Foundation
import UIKit
import simd
import UniformTypeIdentifiers
import CoreLocation
import MobileCoreServices

class LocalFileManager{
    
    static let instance = LocalFileManager()
    
    var folder_name = ""
    
    var fileURLs: [URL] = []
    
    init()
    {
        //createFolderIfNeeded()
        //getFileList()
    }
    
    func genTodayFolder() -> String    {
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd"
        return formatter.string(from: date)
    }
    
    func genTodayName() -> String {
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: date)
    }
    
    func getNextCnt(subDir: String) -> Int    {
        // Generate today folder
        self.folder_name = genTodayFolder()
        var cnt:Int = 0
        //let subDir = "flir_jpg"
        guard
            let path = FileManager
                .default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(folder_name)
                .appendingPathComponent(subDir)
                else
                {
                    return 0
                }
        let fileList = getFileList(path: path)
        //print(fileList)
        if fileList?.count == 0{
            cnt = 0
        }
        
        var max_val:Int = -1
        for (fileName) in fileList!{
            let c1 = fileName.pathComponents.count - 1
            // the filename of each file
            let v1 = fileName.pathComponents[c1].components(separatedBy: [".","_"])
            let idx = Int(v1[2])!
            if max_val < idx{
                max_val = idx
            }

        }
        cnt = max_val + 1
        return cnt
    }
    
    
    func setFolderName(inputName:String)
    {
        folder_name = inputName
    }
    
    func createFolderIfNeeded()
    {
        self.folder_name = genTodayFolder()
        //let subDirs: [String] = ["flir_jpg","flir_processed","depth_tiff","confidence_tiff", "rgb_jpg","meta_json"]
        let subDirs: [String] = ["flir_jpg","depth_tiff","confidence_tiff", "rgb_jpg","meta_json"]
        for (subDir) in subDirs{
            guard
                let path = FileManager
                    .default
                    .urls(for: .documentDirectory, in: .userDomainMask)
                    .first?
                    .appendingPathComponent(folder_name)
                    .appendingPathComponent(subDir)
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
    
    func getFileList(path: URL) -> [URL]?{
        let nilURL : [URL]!
        nilURL = []
//        guard let fileEnumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: nil, options: FileManager.DirectoryEnumerationOptions()) else { return nilURL}
        
        let fileManager = FileManager.default
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
            // process files
            // print(fileURLs)
            self.fileURLs = fileURLs
    
        } catch {
            print("Error while enumerating files \(self.getFolderURL()!.path): \(error.localizedDescription)")
        }
        
        guard let imagePath = self.fileURLs.first?.path else {
            return nilURL
        }
        return fileURLs
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
    
    func saveJpg(image: UIImage, path: URL, location: CLLocation?, roll:Double, pitch:Double, yaw:Double) {
        
//        if let jpgData = image.jpegData(compressionQuality: 0.5)
//        {
//            try? jpgData.write(to: path)
//        }
        
        let metaData = addLocation(location!, roll: roll,pitch: pitch,yaw: yaw, toImage: image)
        
        /// Saving the image to gallery
        /// Creating jpgData from UIImage (1 = original quality)
        guard let jpgData = image.jpegData(compressionQuality: 0.5) else { return }

        /// Adding metaData to jpgData
        guard let source = CGImageSourceCreateWithData(jpgData as CFData, nil), let uniformTypeIdentifier = CGImageSourceGetType(source) else {
            return
        }

        let finalData = NSMutableData(data: jpgData)
        guard let destination = CGImageDestinationCreateWithData(finalData, uniformTypeIdentifier, 1, nil) else { return }
        CGImageDestinationAddImageFromSource(destination, source, 0, metaData as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }

        /// Now write this image to directory
        if FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.removeItem(atPath: path.path)
        }

        let success = FileManager.default.createFile(atPath: path.path, contents: finalData as Data, attributes: [FileAttributeKey.protectionKey : FileProtectionType.complete])
        
        
        //let data = toJpegWithExif(image: image, metadata: metaData as NSDictionary, location: location)
        
    }
    
//    func convertCIImageToCGImage(inputImage: CIImage) -> CGImage! {
//        let context = CIContext(options: nil)
//        if context != nil {
//            return context.createCGImage(inputImage, from: inputImage.extent)
//        }
//        return nil
//    }
//    
//    func toJpegWithExif(image: UIImage, metadata: NSDictionary, location: CLLocation?) -> Data? {
//        return autoreleasepool(invoking: { () -> Data in
//            let data = NSMutableData()
//            let options = metadata.mutableCopy() as! NSMutableDictionary
//            options[ kCGImageDestinationLossyCompressionQuality ] = CGFloat(0.5)
//
//            // if location is available, add GPS data, thanks to https://gist.github.com/nitrag/343fe13f01bb0ef3692f2ae2dfe33e86
//            if ( nil != location ) {
//                let gpsData = NSMutableDictionary()
//
//                let altitudeRef = Int(location!.altitude < 0.0 ? 1 : 0)
//                let latitudeRef = location!.coordinate.latitude < 0.0 ? "S" : "N"
//                let longitudeRef = location!.coordinate.longitude < 0.0 ? "W" : "E"
//
//                // GPS metadata
//                gpsData[(kCGImagePropertyGPSLatitude as String)] = abs(location!.coordinate.latitude)
//                gpsData[(kCGImagePropertyGPSLongitude as String)] = abs(location!.coordinate.longitude)
//                gpsData[(kCGImagePropertyGPSLatitudeRef as String)] = latitudeRef
//                gpsData[(kCGImagePropertyGPSLongitudeRef as String)] = longitudeRef
//                gpsData[(kCGImagePropertyGPSAltitude as String)] = Int(abs(location!.altitude))
//                gpsData[(kCGImagePropertyGPSAltitudeRef as String)] = altitudeRef
//                gpsData[(kCGImagePropertyGPSTimeStamp as String)] = location!.timestamp.isoTime()
//                gpsData[(kCGImagePropertyGPSDateStamp as String)] = location!.timestamp.isoDate()
//                gpsData[(kCGImagePropertyGPSVersion as String)] = "2.2.0.0"
//
//                options[ kCGImagePropertyGPSDictionary as String ] = gpsData
//            }
//            
//            let imageDestinationRef = CGImageDestinationCreateWithData(data as CFMutableData, kUTTypeJPEG, 1, nil)!
//            var ciImage = CIImage(image: image)
//            var cgiImage = convertCIImageToCGImage(inputImage: ciImage!)
//            CGImageDestinationAddImage(imageDestinationRef, cgiImage!, options)
//            CGImageDestinationFinalize(imageDestinationRef)
//            return data as Data
//        })
//    }
    
    func savePng(image: UIImage, path: URL) {
        if let pngData = image.pngData()
           {
            try? pngData.write(to: path)
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
    
    func getPathForImageExt(subdir: String, name: String, ext: String) -> URL?{
        guard
            let path = FileManager
                .default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(folder_name)
                .appendingPathComponent(subdir)
                .appendingPathComponent("\(name).\(ext)") else
                {
                    print("Error getting path")
                    return nil
                }
        return path
    }
    
}

extension FileManager {
    func urls(for directory: FileManager.SearchPathDirectory, skipsHiddenFiles: Bool = true ) -> [URL]? {
        let documentsURL = urls(for: directory, in: .userDomainMask)[0]
        let fileURLs = try? contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: skipsHiddenFiles ? .skipsHiddenFiles : [] )
        return fileURLs
    }
}

