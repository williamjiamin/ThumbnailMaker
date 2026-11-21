//
//  ShareSheet.swift
//  ThumbnailMaker
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    /// FEATURE-13: called with `completed` from the activity controller.
    /// A cancelled share reports false. Nil keeps existing call sites unchanged.
    var onComplete: (@MainActor (Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        if let onComplete {
            controller.completionWithItemsHandler = { _, completed, _, _ in
                Task { @MainActor in
                    onComplete(completed)
                }
            }
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) { }
}
