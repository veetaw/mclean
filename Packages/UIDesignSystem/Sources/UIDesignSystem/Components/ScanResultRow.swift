import AppKit
import Foundation
import SwiftUI

/// A single scan-result line: icon, title, subtitle, size, an optional
/// safety tier badge, and a trailing action button.
///
/// Deliberately takes plain values (not a `CoreScanEngine.ScanItem`) —
/// `UIDesignSystem` has no dependency on feature packages. Callers map their
/// own model into these parameters at the call site, including deciding
/// whether an item warrants a real `icon` (e.g. resolving `.app` bundle
/// semantics is the caller's job, not this view's — see
/// `MainAppUI.ScanItemRowDisplay`). This view only renders whatever it's
/// given; it never resolves or caches an icon/name itself.
@available(macOS 26.0, *)
public struct ScanResultRow: View {
    private let systemImage: String
    private let icon: NSImage?
    private let title: String
    private let subtitle: String
    private let sizeBytes: Int64?
    private let safetyTier: DSSafetyTier?
    private let actionLabel: String
    private let actionVariant: DSButtonVariant
    private let action: () -> Void

    public init(
        systemImage: String,
        icon: NSImage? = nil,
        title: String,
        subtitle: String,
        sizeBytes: Int64?,
        safetyTier: DSSafetyTier? = nil,
        actionLabel: String = "Review",
        actionVariant: DSButtonVariant = .secondary,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.sizeBytes = sizeBytes
        self.safetyTier = safetyTier
        self.actionLabel = actionLabel
        self.actionVariant = actionVariant
        self.action = action
    }

    public var body: some View {
        HStack(spacing: DSSpacing.medium) {
            // `icon` (e.g. a real app icon from `NSWorkspace`) takes priority
            // over the SF Symbol fallback when the caller has one — callers
            // are expected to have already cached it, so reading it here on
            // every `body` evaluation is just a dictionary-cached property
            // access, not fresh disk I/O.
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                Text(title)
                    .font(DSTypography.heading)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: DSSpacing.small)

            if let safetyTier {
                SafetyBadge(safetyTier)
            }

            if let sizeBytes {
                Text(Self.formattedSize(sizeBytes))
                    .font(DSTypography.caption.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(minWidth: 64, alignment: .trailing)
            }

            Button(actionLabel, action: action)
                .dsButtonStyle(actionVariant)
                .controlSize(.small)
        }
        .padding(.vertical, DSSpacing.small)
        .padding(.horizontal, DSSpacing.medium)
    }

    /// Formats a byte count the way Finder does (`ByteCountFormatter`,
    /// `.file` style), so sizes read consistently with the rest of macOS.
    public static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

@available(macOS 26.0, *)
#Preview("Scan Result Rows") {
    ZStack {
        DSColor.background.ignoresSafeArea()

        VStack(spacing: DSSpacing.xSmall) {
            GlassCard {
                VStack(spacing: 0) {
                    ScanResultRow(
                        systemImage: "shippingbox",
                        title: "pip cache",
                        subtitle: "~/Library/Caches/pip",
                        sizeBytes: 812_000_000,
                        safetyTier: .safeAuto,
                        actionLabel: "Clean",
                        actionVariant: .primary
                    ) {}

                    Divider().opacity(0.3)

                    ScanResultRow(
                        systemImage: "hammer",
                        title: "Xcode DerivedData",
                        subtitle: "~/Library/Developer/Xcode/DerivedData",
                        sizeBytes: 4_300_000_000,
                        safetyTier: .needsConfirmation,
                        actionLabel: "Review",
                        actionVariant: .secondary
                    ) {}

                    Divider().opacity(0.3)

                    ScanResultRow(
                        systemImage: "lock.doc",
                        title: "System Keychain",
                        subtitle: "/Library/Keychains",
                        sizeBytes: nil,
                        safetyTier: .forbidden,
                        actionLabel: "Locked",
                        actionVariant: .destructive
                    ) {}
                }
            }
            .frame(width: 520)
        }
        .padding(DSSpacing.xLarge)
    }
    .frame(width: 620, height: 320)
}
