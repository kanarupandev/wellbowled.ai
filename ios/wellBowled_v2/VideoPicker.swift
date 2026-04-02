import SwiftUI
import PhotosUI
import AVFoundation

struct VideoPicker: UIViewControllerRepresentable {
    let onPick: (Delivery) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (Delivery) -> Void

        init(onPick: @escaping (Delivery) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier("public.movie") else {
                picker.dismiss(animated: true)
                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { [weak self] url, error in
                guard let url else {
                    DispatchQueue.main.async { picker.dismiss(animated: true) }
                    return
                }

                // Copy to app documents (the provided URL is temporary)
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let dest = docs.appendingPathComponent("upload_\(Int(Date().timeIntervalSince1970)).\(url.pathExtension)")
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)

                Task {
                    if let delivery = await Delivery.from(url: dest) {
                        await MainActor.run {
                            self?.onPick(delivery)
                        }
                    } else {
                        await MainActor.run {
                            picker.dismiss(animated: true)
                        }
                    }
                }
            }
        }
    }
}
