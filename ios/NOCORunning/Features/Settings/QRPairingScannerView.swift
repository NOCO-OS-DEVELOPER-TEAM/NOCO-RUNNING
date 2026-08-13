import SwiftUI
import AVFoundation

struct QRPairingScannerView: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            AmbientField(intensity: 0.7)
            CameraPreview(onCode: { code in
                Haptics.medium()
                onCode(code)
                dismiss()
            }, permissionDenied: $permissionDenied)
            .ignoresSafeArea()

            VStack {
                GlassSurface(cornerRadius: 22, bloom: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            IntelligenceSparkle()
                            Text("NOCO AI koppeln")
                                .font(.headline)
                        }
                        Text("Scanne den QR-Code aus dem NOCO-RUNNING-Plugin auf dem Windows-PC.")
                            .font(.footnote)
                            .foregroundStyle(NocoTheme.mist)
                    }
                }
                .padding()
                Spacer()
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(NocoTheme.aurora, lineWidth: 2)
                    .frame(width: 240, height: 240)
                    .rainbowGlow(radius: 18, opacity: 0.7)
                    .overlay {
                        RainbowBloom(lineWidth: 2, cornerRadius: 28, spinning: true)
                    }
                Spacer()
                if permissionDenied {
                    Text("Kamera-Zugriff in den Einstellungen erlauben.")
                        .foregroundStyle(NocoTheme.coral)
                        .padding()
                }
                Button("Schließen") { dismiss() }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 28)
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    var onCode: (String) -> Void
    @Binding var permissionDenied: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        context.coordinator.attach(to: view, onCode: onCode) { denied in
            DispatchQueue.main.async { permissionDenied = denied }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private var onCode: ((String) -> Void)?
        private var handled = false

        func attach(to view: PreviewView, onCode: @escaping (String) -> Void, permission: @escaping (Bool) -> Void) {
            self.onCode = onCode
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configure(view: view)
                permission(false)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.configure(view: view)
                            permission(false)
                        } else {
                            permission(true)
                        }
                    }
                }
            default:
                permission(true)
            }
        }

        private func configure(view: PreviewView) {
            session.beginConfiguration()
            session.sessionPreset = .high
            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
            view.previewLayer.session = session
            session.commitConfiguration()
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !handled,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            handled = true
            session.stopRunning()
            onCode?(value)
        }
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }
}
