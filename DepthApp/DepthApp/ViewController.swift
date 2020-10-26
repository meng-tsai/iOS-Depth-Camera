//
//  ViewController.swift
//  DepthApp
//
//  Created by Juha Eskonen on 13/03/2019.
//  Copyright © 2019 Juha Eskonen. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate, AVCaptureDepthDataOutputDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    }
    
    let captureSession = AVCaptureSession()
    let sessionOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    var previewLayer = AVCaptureVideoPreviewLayer()
    var processingQ = DispatchQueue(label: "depthOutput",
    qos: .userInteractive)
    var intrinsicPrinted = false
    var isRecording = false
    
    var picNum = 1
    
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
    private let depthCapture = DepthCapture()
    
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    
    @IBOutlet var cameraView: UIView!
    
    override func viewWillAppear(_ animated: Bool) {
        if let device = AVCaptureDevice.default(.builtInTrueDepthCamera,
                                                for: .video, position: .front) {
                
            do {
                
                let input = try AVCaptureDeviceInput(device: device )
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.locked){
                    device.focusMode = .locked
                }
                device.unlockForConfiguration()
                if captureSession.canAddInput(input){
                    captureSession.sessionPreset = AVCaptureSession.Preset.photo
                    captureSession.addInput(input)
                    
                    if captureSession.canAddOutput(sessionOutput){
                        
                        captureSession.addOutput(sessionOutput)
                        
                        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
                        previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
                        cameraView.layer.addSublayer(previewLayer)
                        
                        previewLayer.position = CGPoint(x: self.cameraView.frame.width / 2, y: self.cameraView.frame.height / 2)
                        previewLayer.bounds = cameraView.frame
                    }
                    
                    // Add depth output
                    guard captureSession.canAddOutput(depthDataOutput) else { fatalError() }
                    captureSession.addOutput(depthDataOutput)
                    
                    if let connection = depthDataOutput.connection(with: .depthData) {
                        connection.isEnabled = true
                        if (connection.isCameraIntrinsicMatrixDeliverySupported){
                            print("intrinsic supported")
                            connection.isCameraIntrinsicMatrixDeliveryEnabled = true
                        }
                        depthDataOutput.isFilteringEnabled = false
                        depthDataOutput.setDelegate(self, callbackQueue: dataOutputQueue)
                    } else {
                        print("No AVCaptureConnection")
                    }
                    
                    depthCapture.prepareForRecording()
                    
                    // TODO: Do we need to synchronize the video and depth outputs?
                    //outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [sessionOutput, depthDataOutput])
                    
                    captureSession.addOutput(movieOutput)
                    
                    captureSession.startRunning()
                }
                
            } catch {
                print("Error")
            }
        }
    }
    
    func startRecording(){
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileUrl = paths[0].appendingPathComponent("output.mov")
        movieOutput.startRecording(to: fileUrl, recordingDelegate: self)
        print(fileUrl.absoluteString)
        print("Recording started")
        self.isRecording = true
        
    }
    
    func stopRecording(){
        movieOutput.stopRecording()
        print("Stopped recording!")
        self.isRecording = false
        do {
            try depthCapture.finishRecording(success: { (url: URL) -> Void in
                print(url.absoluteString)
            })
        } catch {
            print("Error while finishing depth capture.")
        }
        
    }
    
    @IBAction func startPressed(_ sender: Any) {
        startRecording()
    }
    
    @IBAction func stopPressed(_ sender: Any) {
        stopRecording()
    }
    
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        // Write depth data to a file
        if !intrinsicPrinted{
            print (depthData.cameraCalibrationData?.intrinsicMatrix)
            intrinsicPrinted = true
            
        }
        
        if(self.isRecording) {
            depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
            outputDepth(depthDataMap: depthData.depthDataMap)
            //depthCapture.addPixelBuffers(pixelBuffer: depthData.depthDataMap)
        }
    }
    
    func outputDepth(depthDataMap: CVPixelBuffer){
        processingQ.async {
            print("saving frame \(self.picNum)")
            let width = CVPixelBufferGetWidth(depthDataMap)
            let height = CVPixelBufferGetHeight(depthDataMap)
            if (self.picNum == 1){
                print ("width = \(width), height = \(height)")
            }
            //let data = self.readBuffer(pixelBuffer: depthDataMap)
            let path: String = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            
            //var arr = Array<UInt16>(repeating: 0, count: data.count/MemoryLayout<UInt16>.stride)
            //_ = arr.withUnsafeMutableBytes { data.copyBytes(to: $0) }
            CVPixelBufferLockBaseAddress(depthDataMap, CVPixelBufferLockFlags(rawValue: 0))
            var arr = Array<Float32>(repeating: 0, count: height*width)
            let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthDataMap), to: UnsafeMutablePointer<Float>.self)

            for y in 0 ..< height {
                for x in 0 ..< width {
                    arr[y * width + x] = floatBuffer[y*width+x]
                }
            }
            CVPixelBufferUnlockBaseAddress(depthDataMap, CVPixelBufferLockFlags(rawValue: 0))
            
            if (self.picNum == 1){
                print ("arr size = \(arr.count)")
            }
            
            let dict = ["data":arr]
            var dataPath = URL(fileURLWithPath: path+"/data/")
            try? FileManager().createDirectory(at: dataPath, withIntermediateDirectories: true)
            dataPath = dataPath.appendingPathComponent("data\(self.picNum).json")
            
            if JSONSerialization.isValidJSONObject(dict) { // True
                do {
                    let rawData = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
                    try rawData.write(to: dataPath, options: .atomic)
                } catch {
                    print("Error: \(error)")
                }
            }
            else{
                print("Not Valid JSON")
            }
            self.picNum += 1
        }
        
    }
    
    func readBuffer(pixelBuffer:CVPixelBuffer) -> NSData{
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        let height = CVPixelBufferGetHeight(pixelBuffer);
        let size = bytesPerRow * height;
        //let data = NSData.dataWithBytes_length_(objc.wrap(baseAddress), objc.wrap(size));
        let data = NSData.init(bytes: baseAddress, length: size)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        return data
    }
}
