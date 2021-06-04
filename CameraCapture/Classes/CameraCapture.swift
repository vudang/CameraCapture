//
//  CameraCapture.swift
//  CameraCapture
//
//  Created by PetrBobak@me.com on 29/11/2019.
//  Copyright © 2019 PetrBobak@me.com. All rights reserved.
//
// https://developer.apple.com/library/content/documentation/DeviceInformation/Reference/iOSDeviceCompatibility/Cameras/Cameras.html
// iPhone 5S
// – maximal camera resolution: 3264x2448
// – no format with videoDimensions: 640x480 and HRSI: 3264x2448
// – if session.preset is set to .photo –> videoDimensions is 640x852

import AVFoundation
import CoreVideo
import UIKit
import os.log
import VideoToolbox

public protocol CameraCaptureDelegate: class {
    /**
     Notifies the delegate that a new video frame was written.
     
     - parameters:
        - capture:   The instance of CameraCapture class.
        - frame:     A `CMSampleBuffer` object containing the video frame data and additional information about the frame, such as its format and presentation time. If you need the `UIImage` representation call `CameraCapture.convert(...)` method.
     */
    func cameraCapture(_ capture: CameraCapture, didCaptureVideoFrame frame: CMSampleBuffer)
    
    /**
     Provides the delegate with the captured image resulting from a photo capture.
     
     - parameters:
        - capture:   The instance of CameraCapture class.
        - photo:     An object containing the captured image pixel buffer. If you need the `UIImage` representation call `CameraCapture.convert(...)` method.
        - error:     If the capture process could not proceed successfully, an error object describing the failure; otherwise, nil.
     */
    func cameraCapture(_ capture: CameraCapture, didCapturePhoto photo: CVPixelBuffer?, error: Error?)
}

public protocol CameraCaptureSystemPressureDelegate: class {
    /**
     Notifies the delegate that the torch availability has changed.
     
     - parameters:
        - capture:   The instance of CameraCapture class.
        - isTorchAvailable: Indicates whether the torch is currently available for use.
     */
    func cameraCapture(_ capture: CameraCapture, torchAvailabilityDidChange isTorchAvailable: Bool)
    
    /**
     Notifies the delegate that the system pressure has changed.
     
     - parameters:
        - capture:   The instance of CameraCapture class.
        - systemPressureState: Information about OS and hardware status affecting capture system performance and availability.
     */
    func cameraCapture(_ capture: CameraCapture, systemPressureDidChange systemPressureState: AVCaptureDevice.SystemPressureState)
    
    /**
     Notifies the delegate that the capture session interuption state has changed.
     
     - parameters:
        - capture:   The instance of CameraCapture class.
        - isInterrupted: Indicates whether the session is currently interupted or not.
        - systemPressureState: Identification of the reason a capture session was interrupted.
     */
    func cameraCapture(_ capture: CameraCapture, captureSessionInterruptionDidChange isInterrupted: Bool, interruptionReason: AVCaptureSession.InterruptionReason?)
}

public struct CameraCaptureConfiguration {
    // Default values
    var (device, videoZoomFactor) = CameraCaptureConfiguration.defaultDevice()
    var maxHRSI = true
    var videoHeightRange = 480...1080
    var aspectRatio43 = true
    var preferredFrameRate = 60
    var autoFocusRangeRestriction = AVCaptureDevice.AutoFocusRangeRestriction.none
    
    private static let qualityToHeightMap: [AVCaptureSession.Preset : Int] = [
        .hd1920x1080   : 1080,
        .hd1280x720    : 720,
        .iFrame960x540 : 540,
        .vga640x480    : 480,
        ]
    
    public init() {}
    
    /**
     Initializes the camera configuration with the given the quality level `previewQuality` of the preview output.
     
     - parameters:
        - previewQuality: A constant value indicating the quality level of the preview output. Currently supported only: `vga640x480`, `iFrame960x540`, `hd1280x720`, `hd1920x1080`, otherwise the behaviour is not defined.
     */
    public init(device: AVCaptureDevice? = nil, previewQuality: AVCaptureSession.Preset) {
        self.device = device ?? self.device
        self.videoHeightRange = CameraCaptureConfiguration.qualityToHeightMap[previewQuality]!...CameraCaptureConfiguration.qualityToHeightMap[previewQuality]!
    }
    
    /**
     Initializes the camera configuration with the given paremeters.
     
     - parameters:
        - todo:
     */
    public init(device: AVCaptureDevice? = nil, maxHRSI: Bool, videoHeightRange: CountableClosedRange<Int>, aspectRatio43: Bool, preferredFrameRate: Int, autoFocusRangeRestriction: AVCaptureDevice.AutoFocusRangeRestriction) {
        self.device = device ?? self.device
        self.maxHRSI = maxHRSI
        self.videoHeightRange = videoHeightRange
        self.aspectRatio43 = aspectRatio43
        self.preferredFrameRate = preferredFrameRate
        self.autoFocusRangeRestriction = autoFocusRangeRestriction
    }
    
    /**
     Initializes the camera configuration with the given paremeters.
     
     - parameters:
        - previewQuality: A constant value indicating the quality level of the preview output. Currently supported only: `vga640x480`, `iFrame960x540`, `hd1280x720`, `hd1920x1080`, otherwise the behaviour is not defined.
     */
    public init(device: AVCaptureDevice? = nil, maxHRSI: Bool, previewQuality: AVCaptureSession.Preset, aspectRatio43: Bool, preferredFrameRate: Int, autoFocusRangeRestriction: AVCaptureDevice.AutoFocusRangeRestriction) {
        self.init(device: device,
                  maxHRSI: maxHRSI,
                  videoHeightRange: CameraCaptureConfiguration.qualityToHeightMap[previewQuality]!...CameraCaptureConfiguration.qualityToHeightMap[previewQuality]!,
                  aspectRatio43: aspectRatio43,
                  preferredFrameRate: preferredFrameRate,
                  autoFocusRangeRestriction: autoFocusRangeRestriction)
    }
    
    static public func availableDevices(position: AVCaptureDevice.Position) -> [AVCaptureDevice]? {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes:
                                                                    [.builtInDualCamera,
                                                                     .builtInDualWideCamera,
                                                                     .builtInTripleCamera,
                                                                     .builtInWideAngleCamera,
                                                                     .builtInUltraWideCamera,
                                                                     .builtInTelephotoCamera,
                                                                    ],
                                                                mediaType: .video, position: position)
        
        return discoverySession.devices
    }
    
    static public func defaultDevice() -> (AVCaptureDevice?, CGFloat) {
        if let device = UIDevice.current.model,
           device.type == "iPhone" && device.major == 13 && device.minor == 4 {
            // iPhone 12 Pro Max
            return (AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back), CGFloat(2.8))
        } else {
            // other iPhones and iPads
            let device = AVCaptureDevice.default(for: AVMediaType.video)
            return (device, device?.videoZoomFactor ?? CGFloat(1.0))
        }
    }
}

public class CameraCapture: NSObject {
    // MARK: Private properties
    private var cameraAdjustmentObservers = [NSKeyValueObservation]()
    private var systemPressureObservers = [NSKeyValueObservation]()
    
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera session queue")
    private let sampleQueue = DispatchQueue(label: "sample buffer queue")
    private let photoQueue = DispatchQueue(label: "photo session queue")
    private var currentCameraDevice: AVCaptureDevice?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    // MARK: Public properties
    public var isAdjustingFocus = true
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public weak var delegate: CameraCaptureDelegate?
    public weak var systemPressureDelegate: CameraCaptureSystemPressureDelegate?
    public var frameDimensions: CMVideoDimensions {
        get {
            return CMVideoFormatDescriptionGetDimensions((currentCameraDevice?.activeFormat.formatDescription)!)
        }
    }
    
    public var isRunning: Bool {
        return session.isRunning
    }
    
    deinit {
        removeCameraAdjustmentObservers()
        removeSystemPressureObservers()
        removeDeviceObservers()
    }
    
    // MARK: Public methods
    public func configure(completion: @escaping (Bool) -> Void) {
        let defaultConfiguration = CameraCaptureConfiguration()
        configure(configuration: defaultConfiguration) { (success) in
            completion(success)
        }
    }
    
    public func configure(configuration: CameraCaptureConfiguration, completion: @escaping (Bool) -> Void) {
        sampleQueue.async {
            let success = self.configureSession(configuration: configuration)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    func configureSession(configuration: CameraCaptureConfiguration) -> Bool {
        session.beginConfiguration()

        // Get Capture Device
        guard let captureDevice = configuration.device else {
                os_log("This device has no available camera", type: .error)
            return false
        }
        
        currentCameraDevice = captureDevice
        os_log("Selected camera device: %@", currentCameraDevice ?? "No device")

        // Setup Capture Device Input
        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            os_log("Could not create AVCaptureDeviceInput", type: .error)
            return false
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            os_log("Could not add camera device input to the session", type: .error)
            return false
        }
        
        // Set the desired fromat of selected device.
        do {
            try currentCameraDevice?.setFormat(maxHRSI:             configuration.maxHRSI,
                                               videoHeightRange:    configuration.videoHeightRange,
                                               aspectRatio43:       configuration.aspectRatio43,
                                               preferredFrameRate:  configuration.preferredFrameRate)
        } catch {
            os_log("%@", type: .error, error.localizedDescription)
            return false
        }
        
        if let format = currentCameraDevice?.activeFormat {
            os_log("Selected format: %@", format)
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        previewLayer.connection?.videoOrientation = .portrait
        self.previewLayer = previewLayer

        // Setup Capture Device Output
        
        // All delegate methods are invoked on the specified dispatch queue
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        
        // Add Video Output
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.alwaysDiscardsLateVideoFrames = true
        } else {
            os_log("Could not add video output to the session", type: .error)
            return false
        }
        
        // Add Photo Output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        } else {
            os_log("Could not add photo output to the session", type: .error)
            return false
        }

        // We want the buffers to be in portrait orientation otherwise they are
        // rotated by 90 degrees. Need to set this _after_ addOutput()!
        videoOutput.connection(with: .video)?.videoOrientation = .portrait

        session.commitConfiguration()
        
        do {
            try currentCameraDevice?.lockForConfiguration()
            currentCameraDevice?.videoZoomFactor = configuration.videoZoomFactor
            print("Min zoom: ", currentCameraDevice?.minAvailableVideoZoomFactor ?? "Uknown")
            print("Max zoom: ", currentCameraDevice?.maxAvailableVideoZoomFactor ?? "Uknown")
            print("Current zoom: ", currentCameraDevice?.videoZoomFactor ?? "Uknown")
            print("videoZoomFactorUpscaleThreshold: ", currentCameraDevice?.activeFormat.videoZoomFactorUpscaleThreshold ?? "Uknown")
            
            
            currentCameraDevice?.isSubjectAreaChangeMonitoringEnabled = true
            currentCameraDevice?.autoFocusRangeRestriction = configuration.autoFocusRangeRestriction
            if let device = currentCameraDevice, device.isSmoothAutoFocusSupported {
                currentCameraDevice?.isSmoothAutoFocusEnabled = true
            }
            currentCameraDevice?.unlockForConfiguration()
        } catch {
            os_log("Could not set autoFocusRangeRestriction", type: .error)
        }
        
        // Add observers
        addCameraAdjustmentObservers()
        addSystemPressureObservers()
        addDeviceObservers()
        
        return true
    }

    public func start() {
        if !session.isRunning {
            session.startRunning()
        }
    }

    public func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    private func createPhotoSettings() -> AVCapturePhotoSettings? {
        let pixelFormatType = kCVPixelFormatType_32BGRA
        //print(photoOutput.availablePhotoPixelFormatTypes)
        guard photoOutput.availablePhotoPixelFormatTypes.contains(pixelFormatType) else {
            os_log("PhotoPixelFormatTypes is not available")
            return nil
        }
        
        let photoSettings = AVCapturePhotoSettings(format: [
            kCVPixelBufferPixelFormatTypeKey as String : pixelFormatType
            ])
        photoSettings.isHighResolutionPhotoEnabled = true
        
        return photoSettings
    }
    
    public func capturePhoto() {
        guard let photoSettings = createPhotoSettings() else { return }
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    public func capturePhoto(focusPointOfInterest: CGPoint) {
        guard let photoSettings = createPhotoSettings() else { return }
        
        // Focus
        print("Focusing at: \(focusPointOfInterest)")
        
        focus(atPointOfInterest: focusPointOfInterest)
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    public func expose(atPointOfInterest point: CGPoint) {
        guard let device = currentCameraDevice, device.isExposurePointOfInterestSupported else {
            os_log("Device not selected or does not support exposurePointOfInterest", type: .error)
            return
        }
        
        guard let pointInCameraSpace = previewLayer?.captureDevicePointConverted(fromLayerPoint: point) else {
            os_log("previewLayer not initialized", type: .error)
            return
        }
        
//        print("Exposure POI: \(pointInCameraSpace)")
        
        do {
            try device.lockForConfiguration()
            device.exposurePointOfInterest = pointInCameraSpace
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
        } catch {
            os_log("Device could not set exposion using exposurePointOfInterest", type: .error)
        }
    }
    
    public func focus(atPointOfInterest point: CGPoint) {
            guard let device = currentCameraDevice, device.isFocusPointOfInterestSupported else {
                os_log("Device not selected or does not support focusPointOfInterest", type: .error)
                return
            }
            
            guard let pointInCameraSpace = previewLayer?.captureDevicePointConverted(fromLayerPoint: point) else {
                os_log("previewLayer not initialized", type: .error)
                return
            }
            
//            print("Focus POI: \(pointInCameraSpace)")
            
            do {
                try device.lockForConfiguration()
                device.focusPointOfInterest = pointInCameraSpace
                currentCameraDevice?.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
            } catch {
                os_log("Device could not set exposion using focusPointOfInterest", type: .error)
            }
        }
}

// MARK: AVCaptureVideoDataOutputSampleBufferDelegate delegate
extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.cameraCapture(self, didCaptureVideoFrame: sampleBuffer)
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        print("dropped frame")
    }
}

// MARK: AVCapturePhotoCaptureDelegate delegate
extension CameraCapture: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            os_log("Error capturing photo: %@", type: .error, String(describing: error))
            self.delegate?.cameraCapture(self, didCapturePhoto: nil, error: error)
            return
        }
        
        // Get pixelBuffer representation
        guard let pixelBuffer = photo.pixelBuffer else {
            os_log("No pixelBuffer representation", type: .error)
            self.delegate?.cameraCapture(self, didCapturePhoto: nil, error: error)
            return
        }

//        photoQueue.async {
            self.delegate?.cameraCapture(self, didCapturePhoto: pixelBuffer, error: error)
//        }
    }
}

// MARK: Conversion extension
extension CameraCapture {
    private static let context = CIContext()
    
    public static func convert(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .right) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            os_log("Could not create CGImage from CIImage", type: .error)
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    public static func convert(sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            os_log("Could not obtain the CVImageBuffer from CMSampleBuffer", type: .error)
            return nil
        }
        
        return CameraCapture.convert(pixelBuffer: pixelBuffer, orientation: .up)
        
//        var cgImageOpt: CGImage?
//        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImageOpt)
//        guard let cgImage = cgImageOpt else {
//            os_log("Could not create CGImage from CVPixelBuffer", type: .error)
//            return nil
//        }
//
//        let image = UIImage(cgImage: cgImage)
//        if image.size.width == 0 || image.size.width == 0 {
//            os_log("UIImage created from CGImage is empty", type: .error)
//            return nil
//        }

//        return image
    }
}

// MARK: Adjustments
extension CameraCapture {
    public var isAdjustingCameraParameters: Bool {
        return isAdjustingExposure || isAdjustingFocus || isAdjustingWhiteBalance
    }
    
    public var isAdjustingExposure: Bool {
        return currentCameraDevice?.isAdjustingExposure ?? false
    }
    
    public var isAdjustingWhiteBalance: Bool {
        return currentCameraDevice?.isAdjustingWhiteBalance ?? false
    }
    
    func addCameraAdjustmentObservers() {
        cameraAdjustmentObservers.append(
            currentCameraDevice!.observe(\.isAdjustingExposure, options: .new, changeHandler: { (device, change) in
//                guard let isAdjustingExposure = change.newValue else { return }
//                print("isAdjustingExposure = \(isAdjustingExposure)")
        }))
        
        cameraAdjustmentObservers.append(
            currentCameraDevice!.observe(\.lensPosition, options: [.new, .old], changeHandler: { (device, change) in
                guard let lensPosition = change.newValue else { return }
//                print("lensPosition = \(lensPosition)")
                
                guard let oldValue = change.oldValue else { return }
                self.isAdjustingFocus = abs(lensPosition - oldValue) > 0.005
//                print("isAdjustingFocus = \(self.isAdjustingFocus)")
        }))
    }
    
    func removeCameraAdjustmentObservers() {
        for observer in cameraAdjustmentObservers {
            observer.invalidate()
        }
        cameraAdjustmentObservers.removeAll()
    }
}

// MARK: System Pressure Extension
extension CameraCapture {
    func addSystemPressureObservers() {
        
        // Torch Availability
        systemPressureObservers.append(
            currentCameraDevice!.observe(\.isTorchAvailable, options: [.new, .old], changeHandler: { (device, change) in
                guard let newValue = change.newValue else { return }
                
                DispatchQueue.main.async {
                    self.systemPressureDelegate?.cameraCapture(self, torchAvailabilityDidChange: newValue)
                }
        }))
        
        // System Pressure
        systemPressureObservers.append(
            currentCameraDevice!.observe(\.systemPressureState, options: [.new, .old], changeHandler: { (device, change) in
                guard let newValue = change.newValue else { return }
                
                DispatchQueue.main.async {
                    self.systemPressureDelegate?.cameraCapture(self, systemPressureDidChange: newValue)
                }
        }))
        
        // Session Interruption
        NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: nil, queue: nil) { (notification) in
            DispatchQueue.main.async {
                guard let iteruptionRawValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
                      let interuptionReason = AVCaptureSession.InterruptionReason(rawValue: iteruptionRawValue)  else {
                    return
                }
                
                self.systemPressureDelegate?.cameraCapture(self, captureSessionInterruptionDidChange: true, interruptionReason: interuptionReason)
            }
        }
        
        // Session Interruption Ended
        NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: nil, queue: nil) { (notification) in
            DispatchQueue.main.async {
                self.systemPressureDelegate?.cameraCapture(self, captureSessionInterruptionDidChange: false, interruptionReason: nil)
            }
        }
    }
    
    func removeSystemPressureObservers() {
        for observer in systemPressureObservers {
            observer.invalidate()
        }
        systemPressureObservers.removeAll()
        
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: nil)
    }
}

// MARK: Subject Area Observer
extension CameraCapture {
    func addDeviceObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(deviceSubjectAreaDidChange(_:)), name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)
    }
    
    func removeDeviceObservers() {
        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)
    }
    
    @objc func deviceSubjectAreaDidChange(_ notification: NSNotification) {
//        print("Area Chnaged!")
    }
}

// MARK: Torch extension
extension CameraCapture {
    /// Indicates whether the torch is currently available for use.
    public var isTorchAvailable: Bool {
        return currentCameraDevice?.isTorchAvailable ?? false
    }
    
    /// A Boolean value that specifies whether the capture device has a torch.
    public var hasTorch: Bool {
        return currentCameraDevice?.hasTorch ?? false
    }
    
    /// A Boolean value indicating whether the device’s torch is currently active.
    public var isTorchActive: Bool {
        return currentCameraDevice?.isTorchActive ?? false
    }
    
    /// The current torch mode.
    public var torchMode: AVCaptureDevice.TorchMode {
        get {
            return currentCameraDevice?.torchMode ?? .off
        }
        set {
            if let device = currentCameraDevice {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = newValue
                } catch {
                    os_log("Could not change the torchMode: %@", type: .error, error.localizedDescription)
                }
            }
        }
    }
    
    /// The current torch brightness level.
    public var torchLevel: Float {
        return currentCameraDevice?.torchLevel ?? 0.0
    }
    
    /// Sets the illumination level when in torch mode.
    public func setTorchModeOn(level: Float) {
        if let device = currentCameraDevice, device.hasTorch {
            do {
                try device.lockForConfiguration()
                try device.setTorchModeOn(level: level)
                device.unlockForConfiguration()
            } catch {
                os_log("Could not setTorchModeOn torch: %@", type: .error, error.localizedDescription)
            }
        }
    }
    
    // A Boolean value that specifies whether the capture device has a torch.
    public func toggleTorch(level: Float = AVCaptureDevice.maxAvailableTorchLevel) -> Bool {
        if let device = currentCameraDevice, device.hasTorch {
            do {
                try device.lockForConfiguration()
                let torchOn = device.isTorchActive
                
                if torchOn {
                    device.torchMode = .off
                } else {
                    setTorchModeOn(level: level)
                }
                device.unlockForConfiguration()
                return !torchOn
            } catch {
                os_log("Could not toggle torch: %@", type: .error, error.localizedDescription)
            }
        }
        return false
    }
}

// MARK: AVCaptureDevice Extension
extension AVCaptureDevice {
    private func maxHRSIResolution() -> CMVideoDimensions {
        var maxResolution = CMVideoDimensions(width: 0, height: 0)
        
        for format in self.formats {
            if format.highResolutionStillImageDimensions.width * format.highResolutionStillImageDimensions.height > maxResolution.width * maxResolution.height {
                maxResolution = format.highResolutionStillImageDimensions
            }
        }
        
        return maxResolution
    }
    
    /**
     Set the camera capture device format with certain parameters.
     
     - parameters:
        - maxHRSI: Specifies that High Resolution Still Image have to be equal to maximal resolution of the capture device.
        - videoHeightRange: Range of video frame height (eg. 640...1080).
        - aspectRatio43: Specifies that the aspect of video frame have to be 4:3.
        - preferredFrameRate: Prefered frame rate of video frame capture. This criterion doesn't have to be satisfied.
     
     The lowest possible resolution that satisfies all the parameters is selected.
     
     Throws error if all criterios could not be satisfied.
     */
    
    func setFormat(maxHRSI: Bool, videoHeightRange: CountableClosedRange<Int>, aspectRatio43: Bool, preferredFrameRate: Int = 30) throws {
        var desiredFPSFormat: AVCaptureDevice.Format?
        var appropriateFormat: AVCaptureDevice.Format?
        let deviceMaxResolution = maxHRSIResolution()
        
        os_log("Max HRSI resolution: %@", String(describing: deviceMaxResolution))
        
        for format in self.formats {
            
            // Only format with Max HRSI filter
            if maxHRSI && format.highResolutionStillImageDimensions.width * format.highResolutionStillImageDimensions.height <
                deviceMaxResolution.width * deviceMaxResolution.height
            { continue }
            
            // Only format with aspetratio 4:3 filter (4:3 is periodic – bad for equality check)
            if aspectRatio43 && Double(format.highResolutionStillImageDimensions.height) / Double(format.highResolutionStillImageDimensions.width) != 3.0/4.0
            { continue }
            
            // Only format with certain resolution of captured video (frame) is needed
            let videoDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if videoDimensions.height < videoHeightRange.lowerBound || videoDimensions.height > videoHeightRange.upperBound
            { continue }
            
            // Select format with desired frame rate
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= Double(preferredFrameRate) && range.minFrameRate <= Double(preferredFrameRate) {
                    desiredFPSFormat = format
                    break
                }
            }
            
            // Set desired format if exists
            if let format = desiredFPSFormat {
                try self.lockForConfiguration()
                self.activeFormat = format
                
                // https://stackoverflow.com/questions/20330174/avcapture-capturing-and-getting-framebuffer-at-60-fps-in-ios-7
                let timeValue: Int64 = Int64(1200.0 / Double(preferredFrameRate))
                let timeScale: Int32 = 1200
                self.activeVideoMinFrameDuration = CMTimeMake(value: timeValue, timescale: timeScale)
                self.activeVideoMaxFrameDuration = CMTimeMake(value: timeValue, timescale: timeScale)
                
                self.unlockForConfiguration()
                return
            }
            
            // If not yet desired FPS format found fallback
            appropriateFormat = format
        }
        
        // Desired FPS format not found
        if let format = appropriateFormat {
            try self.lockForConfiguration()
            self.activeFormat = format
            self.unlockForConfiguration()
        } else {
            // Any other format with certain resolution of captured video (frame) not found
            throw NSError(domain: "No format is appropriate.", code: 123)
        }
    }
}
