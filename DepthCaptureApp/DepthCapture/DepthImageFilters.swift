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

import CoreImage

enum MaskParams {
  static let slope: CGFloat = 4.0
  static let sharpSlope: CGFloat = 10.0
  static let width: CGFloat = 0.1
}

class DepthImageFilters {
  func createHighPassMask(for depthImage: CIImage,
                          withFocus focus: CGFloat,
                          andScale scale: CGFloat,
                          isSharp: Bool = false) -> CIImage {
    let s = isSharp ? MaskParams.sharpSlope : MaskParams.slope
    let filterWidth =  2 / s + MaskParams.width
    let b = -s * (focus - filterWidth / 2)

    let mask = depthImage
      .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: s, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: s, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: s, w: 0),
        "inputBiasVector": CIVector(x: b, y: b, z: b, w: 0)
      ])
      .applyingFilter("CIColorClamp")
      .applyingFilter("CIBicubicScaleTransform", parameters: [
        "inputScale": scale
      ])

    return mask
  }

  func createBandPassMask(for depthImage: CIImage,
                          withFocus focus: CGFloat,
                          andScale scale: CGFloat) -> CIImage {
    let s1 = MaskParams.slope
    let s2 = -MaskParams.slope
    let filterWidth =  2 / MaskParams.slope + MaskParams.width
    let b1 = -s1 * (focus - filterWidth / 2)
    let b2 = -s2 * (focus + filterWidth / 2)

    let mask0 = depthImage
      .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: s1, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: s1, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: s1, w: 0),
        "inputBiasVector": CIVector(x: b1, y: b1, z: b1, w: 0)
      ])
      .applyingFilter("CIColorClamp")

    let mask1 = depthImage
      .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: s2, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: s2, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: s2, w: 0),
        "inputBiasVector": CIVector(x: b2, y: b2, z: b2, w: 0)
      ])
      .applyingFilter("CIColorClamp")

    let combinedMask = mask0.applyingFilter("CIDarkenBlendMode", parameters: [
      "inputBackgroundImage": mask1
    ])

    let mask = combinedMask.applyingFilter("CIBicubicScaleTransform", parameters: [
      "inputScale": scale
    ])

    return mask
  }

  func comic(image: CIImage, mask: CIImage) -> CIImage {
    let bg = image.applyingFilter("CIComicEffect")

    return image.applyingFilter("CIBlendWithMask", parameters: [
      "inputBackgroundImage": bg,
      "inputMaskImage": mask
    ])
  }

  func greenScreen(image: CIImage,
                   background: CIImage,
                   mask: CIImage) -> CIImage {
    let crop = CIVector(x: 0,
                        y: 0,
                        z: image.extent.size.width,
                        w: image.extent.size.height)

    let croppedBG = background.applyingFilter("CICrop", parameters: [
      "inputRectangle": crop
    ])

    return image.applyingFilter("CIBlendWithMask", parameters: [
      "inputBackgroundImage": croppedBG,
      "inputMaskImage": mask
    ])
  }

  func blur(image: CIImage, mask: CIImage) -> CIImage {
    let blurRadius: CGFloat = 10

    let crop = CIVector(x: 0,
                        y: 0,
                        z: image.extent.size.width,
                        w: image.extent.size.height)

    let invertedMask = mask.applyingFilter("CIColorInvert")

    let blurred = image.applyingFilter("CIMaskedVariableBlur", parameters: [
      "inputMask": invertedMask,
      "inputRadius": blurRadius
    ])

    return blurred.applyingFilter("CICrop", parameters: [
      "inputRectangle": crop
    ])
  }
}
