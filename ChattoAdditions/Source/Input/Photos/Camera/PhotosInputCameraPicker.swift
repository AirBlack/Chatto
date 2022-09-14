/*
 The MIT License (MIT)

 Copyright (c) 2015-present Badoo Trading Limited.

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
*/

import UIKit
import MobileCoreServices

public struct TakenMedia {
    
    public enum TakenMediaContent {
        case image(UIImage)
        case video(URL)
    }
    
    public let content: TakenMediaContent
    public let cameraType: CameraType

    public init(content: TakenMediaContent, cameraType: CameraType) {
        self.content = content
        self.cameraType = cameraType
    }
}

public protocol PhotosInputCameraPickerProtocol {
    func presentCameraPicker(onMediaTaken: @escaping (TakenMedia?) -> Void, onCameraPickerDismissed: @escaping () -> Void)
}

final class PhotosInputCameraPicker: PhotosInputCameraPickerProtocol, ImagePickerDelegate {

    private let presentingControllerProvider: () -> UIViewController?
    private var imagePicker: ImagePicker?
    private var completionBlocks: (onMediaTaken: (TakenMedia?) -> Void, onCameraPickerDismissed: () -> Void)?

    convenience init(presentingController: UIViewController?) {
        self.init(presentingControllerProvider: { [weak presentingController] in presentingController })
    }

    init(presentingControllerProvider: @escaping () -> UIViewController?) {
        self.presentingControllerProvider = presentingControllerProvider
    }

    func presentCameraPicker(onMediaTaken: @escaping (TakenMedia?) -> Void, onCameraPickerDismissed: @escaping () -> Void) {
        guard let presentingController = self.presentingControllerProvider(),
            let imagePicker = ImagePickerStore.factory.makeImagePicker(delegate: self) else {
                onMediaTaken(nil)
                onCameraPickerDismissed()
                return
        }
        self.completionBlocks = (onMediaTaken: onMediaTaken, onCameraPickerDismissed: onCameraPickerDismissed)
        self.imagePicker = imagePicker
        presentingController.present(imagePicker.controller, animated: true, completion: nil)
    }

    func imagePickerDidFinish(_ picker: ImagePicker, mediaInfo: [UIImagePickerController.InfoKey: Any]) {
        let content: TakenMedia.TakenMediaContent? = {
            let mediaType = mediaInfo[UIImagePickerController.InfoKey.mediaType] as? String
            switch mediaType {
            case "\(kUTTypeMovie as String)":
                guard let url = mediaInfo[UIImagePickerController.InfoKey.mediaURL] as? URL else {
                    return nil
                }
                
                return .video(url)
            default:
                guard let image = mediaInfo[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
                    return nil
                }
                
                return .image(image)
            }
        }()
        
        self.finishPickingContent(content, fromPicker: picker)
    }

    func imagePickerDidCancel(_ picker: ImagePicker) {
        self.finishPickingContent(nil, fromPicker: picker)
    }

    private func finishPickingContent(_ content: TakenMedia.TakenMediaContent?, fromPicker picker: ImagePicker) {
        picker.controller.dismiss(animated: true, completion: self.completionBlocks?.onCameraPickerDismissed)
        if let content = content {
            self.completionBlocks?.onMediaTaken(TakenMedia(content: content, cameraType: picker.cameraType))
        } else {
            self.completionBlocks?.onMediaTaken(nil)
        }
        self.completionBlocks = nil
        self.imagePicker = nil
    }
}
