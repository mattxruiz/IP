import SwiftUI
import AVFoundation
import AVKit
import PhotosUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var coverImage: UIImage?
    
    private let fpsOptions = [24, 30, 60]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if camera.isRecording {
                // TOUCH-LOCKED RECORDING COVER SCREEN
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                    } else {
                        VStack(spacing: 12) {
                            Circle()
                                .fill(Color.red.opacity(0.6))
                                .frame(width: 14, height: 14)
                            Text("RECORDING")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("Press Volume Up or Down to Stop")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                }
                .allowsHitTesting(false) // Completely blocks all screen touches
                .statusBarHidden(true)
            } else {
                // SETUP & FRAMING SCREEN
                VStack(spacing: 14) {
                    // Top Bar: Flash & Cover Image Picker
                    HStack {
                        Button {
                            camera.toggleTorch()
                        } label: {
                            Label(camera.isTorchOn ? "Flash On" : "Flash Off",
                                  systemImage: camera.isTorchOn ? "bolt.fill" : "bolt.slash")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(camera.isTorchOn ? Color.yellow.opacity(0.25) : Color.white.opacity(0.12))
                                .foregroundColor(camera.isTorchOn ? .yellow : .white)
                                .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        if !camera.statusMessage.isEmpty {
                            Text(camera.statusMessage)
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label(coverImage == nil ? "Load Cover" : "Cover Ready",
                                  systemImage: coverImage == nil ? "photo.badge.plus" : "checkmark.circle.fill")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(coverImage == nil ? Color.white.opacity(0.12) : Color.green.opacity(0.25))
                                .foregroundColor(coverImage == nil ? .white : .green)
                                .clipShape(Capsule())
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    coverImage = image
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Live Camera Viewfinder
                    ZStack(alignment: .bottomTrailing) {
                        CameraPreviewView(session: camera.session)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        // Thumbnail preview of selected cover image
                        if let coverImage {
                            Image(uiImage: coverImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.4), lineWidth: 1))
                                .padding(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Lens Selector (0.5x, 1x, Front)
                    Picker("Lens", selection: Binding(
                        get: { camera.selectedLens },
                        set: { camera.updateConfiguration(lens: $0) }
                    )) {
                        ForEach(CameraLens.allCases) { lens in
                            Text(lens.rawValue).tag(lens)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // Resolution & Frame Rate Controls
                    HStack(spacing: 12) {
                        Picker("Resolution", selection: Binding(
                            get: { camera.selectedResolution },
                            set: { camera.updateConfiguration(resolution: $0) }
                        )) {
                            ForEach(VideoResolution.allCases) { res in
                                Text(res.rawValue).tag(res)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Picker("FPS", selection: Binding(
                            get: { camera.selectedFPS },
                            set: { camera.updateConfiguration(fps: $0) }
                        )) {
                            ForEach(fpsOptions, id: \.self) { fps in
                                Text("\(fps)fps").tag(fps)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)
                    
                    // Big Record Button + Helper Text
                    VStack(spacing: 6) {
                        Button {
                            camera.startRecording()
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 76, height: 76)
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 62, height: 62)
                            }
                        }
                        
                        Text("Press Volume Up or Down while recording to stop")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        // Hardware Volume Up / Down capture event (stops recording when active)
        .onCameraCaptureEvent(isEnabled: camera.isRecording) { event in
            if event.phase == .ended {
                camera.stopRecording()
            }
        }
    }
}
