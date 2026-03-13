import SwiftUI
import AVFoundation
import UIKit

struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewLayerHostView {
        let view = PreviewLayerHostView(frame: .zero)
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.setPreviewLayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewLayerHostView, context: Context) {
        uiView.setPreviewLayer(previewLayer)
    }
}

final class PreviewLayerHostView: UIView {
    private var activePreviewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        activePreviewLayer?.frame = bounds
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        if activePreviewLayer !== layer {
            activePreviewLayer?.removeFromSuperlayer()
            layer.removeFromSuperlayer()
            self.layer.addSublayer(layer)
            activePreviewLayer = layer
        }
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        if layer.superlayer !== self.layer {
            layer.removeFromSuperlayer()
            self.layer.addSublayer(layer)
        }
    }
}
