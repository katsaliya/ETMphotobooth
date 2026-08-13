//
//  Sharesheet.swift
//  RecieptPhotoBooth
//
//  Created by Kataliya Sungkamee on 8/7/26.
//

import SwiftUI

/// Thin wrapper around UIActivityViewController so SwiftUI can present
/// the native share sheet (AirDrop, Messages, Save Image, etc.) for the
/// "airdrop" star button on the review screen.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
