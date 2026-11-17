import AVFoundation
import Photos
import UIKit

enum CameraLens: String, CaseIterable, Identifiable {
    case ultraWide = "0.5x"
    case wide = "1x"
    case front = "Front"
    
    var id: String { rawValue }
}

enum VideoResolution: String, CaseIterable, Identifiable {
    case hd720 = "720p"
    case fhd1080 = "1080p"
    case uhd4k = "4K"
    
    var id: String { rawValue }
    
    var dimensions: (width: Int32, height: Int32) {
        switch self {
        case .hd720: return (1280, 720)
        case .fhd1080: return (1920, 1080)
        case .uhd4k: return (3840, 2160)
        }
    }
}

final class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.stagecam.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    
    @Published var selectedLens: CameraLens = .wide
    @Published var selectedResolution: VideoResolution = .fhd1080
    @Published var selectedFPS: Int = 30
    @Published var isTorchOn: Bool = false
    @Published var isRecording: Bool = false
    @Published var statusMessage: String = ""
    
    override init() {
        super.init()
        requestPermissionsAndConfigure()
    }
    
    private func requestPermissionsAndConfigure() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in
                    self.sessionQueue.async {
                        self.setupSession()
                    }
                }
            }
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioIn = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioIn) {
            session.addInput(audioIn)
            audioInput = audioIn
        }
        
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        
        session.commitConfiguration()
        applyCameraConfiguration()
        
        if !session.isRunning {
            session.startRunning()
        }
    }
    
    func updateConfiguration(lens: CameraLens? = nil, resolution: VideoResolution? = nil, fps: Int? = nil) {
        if let lens { selectedLens = lens }
        if let resolution { selectedResolution = resolution }
        if let fps { selectedFPS = fps }
        
        sessionQueue.async {
            self.applyCameraConfiguration()
        }
    }
    
    private func device(for lens: CameraLens) -> AVCaptureDevice? {
        switch lens {
        case .ultraWide:
            return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        case .wide:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .front:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }
    
    private func applyCameraConfiguration() {
        guard !isRecording else { return }
        
        session.beginConfiguration()
        
        if let currentInput = videoInput {
            session.removeInput(currentInput)
            videoInput = nil
        }
        
        guard let targetDevice = device(for: selectedLens),
              let newInput = try? AVCaptureDeviceInput(device: targetDevice),
              session.canAddInput(newInput) else {
            session.commitConfiguration()
            return
        }
        
        session.addInput(newInput)
        videoInput = newInput
        
        let targetDims = selectedResolution.dimensions
        let desiredFPS = Double(selectedFPS)
        
        // Find matching format for resolution and FPS (fallback to closest supported)
        let matchingFormats = targetDevice.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supportsFPS = format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= desiredFPS && desiredFPS <= $0.maxFrameRate
            }
            return dims.width == targetDims.width && dims.height == targetDims.height && supportsFPS
        }
        
        let chosenFormat = matchingFormats.first ?? targetDevice.formats.last { format in
            format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= desiredFPS && desiredFPS <= $0.maxFrameRate
            }
        }
        
        do {
            try targetDevice.lockForConfiguration()
            if let format = chosenFormat {
                targetDevice.activeFormat = format
            }
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(selectedFPS))
            targetDevice.activeVideoMinFrameDuration = frameDuration
            targetDevice.activeVideoMaxFrameDuration = frameDuration
            
            if targetDevice.hasTorch && isTorchOn {
                try targetDevice.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else if targetDevice.hasTorch {
                targetDevice.torchMode = .off
            }
            targetDevice.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Camera config error"
            }
        }
        
        session.commitConfiguration()
    }
    
    func toggleTorch() {
        isTorchOn.toggle()
        sessionQueue.async {
            guard let device = self.videoInput?.device, device.hasTorch else {
                DispatchQueue.main.async { self.isTorchOn = false }
                return
            }
            do {
                try device.lockForConfiguration()
                if self.isTorchOn {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.isTorchOn = false }
            }
        }
    }
    
    func startRecording() {
        sessionQueue.async {
            guard !self.movieOutput.isRecording else { return }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            
            self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            DispatchQueue.main.async {
                self.isRecording = true
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }
    
    func stopRecording() {
        sessionQueue.async {
            guard self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        }) { success, _ in
            try? FileManager.default.removeItem(at: outputFileURL)
            DispatchQueue.main.async {
                self.statusMessage = success ? "Saved to Photos" : "Save failed"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.statusMessage = ""
                }
            }
        }
    }
}
