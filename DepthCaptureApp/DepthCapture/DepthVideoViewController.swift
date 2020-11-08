/// Copyright (c) 2019 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import AVFoundation

class DepthVideoViewController: UIViewController {
  @IBOutlet weak var previewView: UIImageView!
  @IBOutlet weak var previewModeControl: UISegmentedControl!
  @IBOutlet weak var filterControl: UISegmentedControl!
  @IBOutlet weak var depthSlider: UISlider!

  var sliderValue: CGFloat = 0.0
  var previewMode = PreviewMode.original
  var filter = FilterType.comic
  let session = AVCaptureSession()
  let dataOutputQueue = DispatchQueue(label: "video data queue",
                                      qos: .userInitiated,
                                      attributes: [],
                                      autoreleaseFrequency: .workItem)
  let background: CIImage! = CIImage(image: UIImage(named: "earth-rise")!)
  var depthMap: CIImage?
  var trueDepth: AVDepthData?
  var mask: CIImage?
  var scale: CGFloat = 0.0
  var depthFilters = DepthImageFilters()
  
  var saving = false
  var intrinsicPrinted = false
  var scalePrinted = false
  var counter = 1

  override func viewDidLoad() {
    super.viewDidLoad()

    filterControl.isHidden = true
    depthSlider.isHidden = true

    previewMode = PreviewMode(rawValue: previewModeControl.selectedSegmentIndex) ?? .original
    filter = FilterType(rawValue: filterControl.selectedSegmentIndex) ?? .comic
    sliderValue = CGFloat(depthSlider.value)

    configureCaptureSession()

    session.startRunning()
  }
  @IBAction func startSaving(_ sender: Any) {
    saving = !saving
  }
}

// MARK: - Helper Methods
extension DepthVideoViewController {
  func configureCaptureSession() {
    guard let camera = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) else {
      fatalError("No depth video camera available")
    }
    
    do {
      try camera.lockForConfiguration()
      if camera.isFocusModeSupported(.locked){
        camera.focusMode = .locked
      }
      camera.unlockForConfiguration()
    } catch{
      print("Can't lock camera focus")
    }
    
    session.sessionPreset = .photo

    do {
      let cameraInput = try AVCaptureDeviceInput(device: camera)
      session.addInput(cameraInput)
    } catch {
      fatalError(error.localizedDescription)
    }

    let videoOutput = AVCaptureVideoDataOutput()
    videoOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

    session.addOutput(videoOutput)

    let videoConnection = videoOutput.connection(with: .video)
    videoConnection?.videoOrientation = .portrait

    let depthOutput = AVCaptureDepthDataOutput()
    depthOutput.setDelegate(self, callbackQueue: dataOutputQueue)
    depthOutput.isFilteringEnabled = true
    session.addOutput(depthOutput)

    let depthConnection = depthOutput.connection(with: .depthData)
    depthOutput.isFilteringEnabled = true
    depthConnection?.videoOrientation = .portrait
    if depthConnection!.isCameraIntrinsicMatrixDeliverySupported{
      print("intrinsic supported")
      depthConnection!.isCameraIntrinsicMatrixDeliveryEnabled = true
    }

    let outputRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    let videoRect = videoOutput
      .outputRectConverted(fromMetadataOutputRect: outputRect)
    let depthRect = depthOutput
      .outputRectConverted(fromMetadataOutputRect: outputRect)

    scale =
      max(videoRect.width, videoRect.height) /
      max(depthRect.width, depthRect.height)

    do {
      try camera.lockForConfiguration()

      if let format = camera.activeDepthDataFormat,
        let range = format.videoSupportedFrameRateRanges.first  {
        camera.activeVideoMinFrameDuration = range.minFrameDuration
      }

      camera.unlockForConfiguration()
    } catch {
      fatalError(error.localizedDescription)
    }
  }
}

// MARK: - Capture Video Data Delegate Methods
extension DepthVideoViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  
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
  
  func resizeImage(image: UIImage, newWidth: CGFloat) -> UIImage {
    let scale = newWidth / image.size.width
    if !scalePrinted {
        print("Original image size = ", image.size)
        print("Scale = ", scale)
        scalePrinted = true
    }
    let newHeight = image.size.height * scale
    UIGraphicsBeginImageContext(CGSize(width: newWidth, height:newHeight))
    image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height:newHeight))
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return newImage!
  }
  
  func outputImg(image: UIImage){
    if !saving {return}
    let path: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    var imagePath: URL
    var depthPath: URL
    
    imagePath = path.appendingPathComponent("color")
    try? FileManager().createDirectory(at: imagePath, withIntermediateDirectories: true)
    imagePath = imagePath.appendingPathComponent("image"+String(format: "%04d", self.counter)+".png")
    
    depthPath = path.appendingPathComponent("data")
    try? FileManager().createDirectory(at: depthPath, withIntermediateDirectories: true)
    depthPath = depthPath.appendingPathComponent("depth"+String(format: "%04d", self.counter)+".json")
    
    do{
      try image.pngData()?.write(to:imagePath, options: .atomic)
      let depthDataMap = trueDepth!.depthDataMap
      let data = readBuffer(pixelBuffer: depthDataMap)
      var arr = Array<Float32>(repeating: 0, count: data.count/MemoryLayout<Float32>.stride)
      _ = arr.withUnsafeMutableBytes { data.copyBytes(to: $0) }
      let arr_int = arr.map { (x) -> Int16 in
          let ans = Int16(lround(Double(x) * 1000))
          return ans
          //TODO: return 32767 at voids
      }
      let dict = ["data":arr_int]
      if JSONSerialization.isValidJSONObject(dict) { // True
          do {
              let rawData = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
              try rawData.write(to: depthPath, options: .atomic)
          } catch {
              print("Error: \(error)")
          }
      }
      else{
          print("Not Valid JSON")
      }
    } catch{fatalError(error.localizedDescription)}
    
    print("Saved image \(self.counter)")
    self.counter += 1
  }
  
  func captureOutput(_ output: AVCaptureOutput,
                     didOutput sampleBuffer: CMSampleBuffer,
                     from connection: AVCaptureConnection) {
    let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    let image = CIImage(cvPixelBuffer: pixelBuffer!)

    let previewImage: CIImage

    switch (previewMode, filter, mask) {
    case (.original, _, _):
      previewImage = image
    case (.depth, _, _):
      previewImage = depthMap ?? image
    case (.mask, _, let mask?):
      previewImage = mask
    case (.filtered, .comic, let mask?):
      previewImage = depthFilters.comic(image: image, mask: mask)
    case (.filtered, .greenScreen, let mask?):
      previewImage = depthFilters.greenScreen(image: image,
                                              background: background,
                                              mask: mask)
    case (.filtered, .blur, let mask?):
      previewImage = depthFilters.blur(image: image, mask: mask)
    default:
      previewImage = image
    }
    
    let displayImage = UIImage(ciImage: previewImage)
    let outPutImage = resizeImage(image:UIImage(ciImage: image), newWidth:240)
    //let depthImage = resizeImage(image:UIImage(ciImage: depthMap ?? image), newWidth:480)
    DispatchQueue.main.async { [weak self] in
      self?.previewView.image = displayImage
      self?.outputImg(image: outPutImage)
//      }
    }
  }
}

// MARK: - Slider Methods
extension DepthVideoViewController {
  @IBAction func sliderValueChanged(_ sender: UISlider) {
    sliderValue = CGFloat(depthSlider.value)
  }
}

// MARK: - Segmented Control Methods
extension DepthVideoViewController {
  @IBAction func previewModeChanged(_ sender: UISegmentedControl) {
    previewMode = PreviewMode(rawValue: previewModeControl.selectedSegmentIndex) ?? .original

    switch previewMode {
    case .mask, .filtered:
      filterControl.isHidden = false
      depthSlider.isHidden = false
    case .depth, .original:
      filterControl.isHidden = true
      depthSlider.isHidden = true
    }
  }

  @IBAction func filterTypeChanged(_ sender: UISegmentedControl) {
    filter = FilterType(rawValue: filterControl.selectedSegmentIndex) ?? .comic
  }
}

// MARK: - Capture Depth Data Delegate Methods
extension DepthVideoViewController: AVCaptureDepthDataOutputDelegate {
  func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                       didOutput depthData: AVDepthData,
                       timestamp: CMTime,
                       connection: AVCaptureConnection) {
//    guard previewMode != .original else {
//      return
//    }
    let depth: AVDepthData
    
    let trueDepthDataType = kCVPixelFormatType_DepthFloat32
    if depthData.depthDataType != trueDepthDataType {
      depth = depthData.converting(toDepthDataType: trueDepthDataType)
    } else {
      depth = depthData
    }
    
    var convertedDepth: AVDepthData

    let depthDataType = kCVPixelFormatType_DisparityFloat32
    if depthData.depthDataType != depthDataType {
      convertedDepth = depthData.converting(toDepthDataType: depthDataType)
    } else {
      convertedDepth = depthData
    }
    
    if !intrinsicPrinted{
      print(depthData.cameraCalibrationData?.intrinsicMatrix ?? "Intrinsic not initialized")
      intrinsicPrinted = true
    }
    
    let pixelBuffer = convertedDepth.depthDataMap

    let depthMap = CIImage(cvPixelBuffer: pixelBuffer)

    if previewMode == .mask || previewMode == .filtered {
      switch filter {
      case .comic:
        mask = depthFilters.createHighPassMask(for: depthMap,
                                               withFocus: sliderValue,
                                               andScale: scale)
      case .greenScreen:
        mask = depthFilters.createHighPassMask(for: depthMap,
                                               withFocus: sliderValue,
                                               andScale: scale,
                                               isSharp: true)
      case .blur:
        mask = depthFilters.createBandPassMask(for: depthMap,
                                               withFocus: sliderValue,
                                               andScale: scale)
      }
    }

    DispatchQueue.main.async { [weak self] in
      self?.depthMap = depthMap
      self?.trueDepth = depth
    }
  }
}
