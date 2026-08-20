import Shredder
import SwiftUI
import UIDesignSystem

/// The UI half of `Shredder`'s two-step, denylist-gated API — see
/// `Shredder`'s own doc comment for the full safety rationale. This view is
/// the **only** place in the app that ever calls `confirmShred`, and it
/// only does so after two separate, explicit user confirmations, never as
/// a single tap. This screen is never reached from a scan finding — file
/// selection here is always a deliberate choice the user makes right here,
/// via the file picker below, not something fed in from `FindingsListView`
/// or any `ScanFinding`.
@available(macOS 26.0, *)
struct ShredderView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var isPickerPresented = false
    @State private var pendingRequest: ShredRequest?
    @State private var confirmationStep: ConfirmationStep = .none
    @State private var passes = 3
    @State private var isShredding = false
    @State private var progress: (completed: Int, total: Int)?
    @State private var errorMessage: String?
    @State private var lastShreddedPath: String?

    private enum ConfirmationStep {
        case none
        case first   // "Are you sure?"
        case second  // "Are you REALLY sure?" — graver, separate dialog
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.large) {
                // Tinted `destructive`, not the default `accent` — Shredder
                // is the one screen in the app whose primary action is
                // always irreversible, so its hero should read as more
                // serious than a routine module at a glance.
                ModuleHeroHeader(
                    title: "Shredder",
                    systemImage: "scissors",
                    subtitle: "Permanently overwrite and delete a single file. Bypasses Quarantine entirely — there is no undo.",
                    tint: DSColor.destructive
                )

                honestyCard
                pickerCard

                if let lastShreddedPath {
                    GlassCard(tint: DSColor.safe.opacity(0.18)) {
                        Label("Shredded: \(lastShreddedPath)", systemImage: "checkmark.circle")
                            .font(DSTypography.body)
                            .foregroundStyle(DSColor.safe)
                    }
                }
            }
            .padding(DSSpacing.xLarge)
        }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            handlePickerResult(result)
        }
        .sheet(isPresented: firstConfirmationBinding) {
            firstConfirmationSheet
        }
        .sheet(isPresented: secondConfirmationBinding) {
            secondConfirmationSheet
        }
        .alert("Couldn't shred that file", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    /// Prominent, un-skippable honesty about what "shredded" actually
    /// means on this hardware — never softened to "guaranteed unrecoverable".
    /// See `Shredder`'s doc comment, which this text summarizes for a
    /// non-technical reader rather than quoting verbatim.
    private var honestyCard: some View {
        GlassCard(tint: DSColor.warning.opacity(0.18)) {
            VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                Label("What shredding actually guarantees", systemImage: "info.circle")
                    .font(DSTypography.heading)
                    .foregroundStyle(DSColor.warning)
                Text(
                    "Shredding overwrites the file's content multiple times before deleting it — "
                    + "this makes casual recovery significantly harder than a normal delete. It is "
                    + "not a cryptographic guarantee: on this Mac's SSD, wear leveling and APFS "
                    + "copy-on-write mean the original data can sometimes persist elsewhere on the "
                    + "disk regardless. This action bypasses Quarantine entirely and cannot be "
                    + "undone once confirmed."
                )
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pickerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.small) {
                Text("Select a file to shred").font(DSTypography.heading)
                Text("Shreds one file at a time. The file is validated against the same protected-path rules as everything else in this app before anything happens.")
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)

                Stepper("Passes: \(passes)", value: $passes, in: 1...7)

                Button("Choose File…", systemImage: "doc.badge.gearshape") {
                    isPickerPresented = true
                }
                .dsButtonStyle(.destructive)
                .disabled(isShredding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Step 1: "Are you sure?"

    private var firstConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: DSSpacing.medium) {
            Text("Permanently shred this file?").font(DSTypography.title)
            if let pendingRequest {
                Text(pendingRequest.path)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                Text("\(ScanResultRow.formattedSize(pendingRequest.fileSizeBytes)) · \(passes) overwrite pass(es)")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            Text("This does NOT go through Quarantine. There is no undo.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.destructive)

            HStack {
                Spacer()
                Button("Cancel") { confirmationStep = .none; pendingRequest = nil }
                    .dsButtonStyle(.secondary)
                Button("Continue") { confirmationStep = .second }
                    .dsButtonStyle(.destructive)
            }
        }
        .padding(DSSpacing.xLarge)
        .frame(width: 480)
    }

    // MARK: - Step 2: "Are you REALLY sure?" — a separate, graver dialog

    private var secondConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: DSSpacing.medium) {
            Label("This is the final confirmation", systemImage: "exclamationmark.triangle.fill")
                .font(DSTypography.title)
                .foregroundStyle(DSColor.destructive)
            Text("Shredding starts immediately after you tap the button below. The file cannot be recovered from Quarantine — it was never placed there.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)

            if isShredding {
                if let progress {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    Text("Overwriting — pass \(progress.completed)/\(progress.total)")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textSecondary)
                } else {
                    ProgressView()
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { confirmationStep = .none; pendingRequest = nil }
                    .dsButtonStyle(.secondary)
                    .disabled(isShredding)
                Button("Shred Permanently", systemImage: "scissors") {
                    Task { await performShred() }
                }
                .dsButtonStyle(.destructive)
                .disabled(isShredding)
            }
        }
        .padding(DSSpacing.xLarge)
        .frame(width: 480)
    }

    // MARK: - Actions

    private func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let request = try await environment.shredder.requestShred(path: url.path)
                    pendingRequest = request
                    confirmationStep = .first
                } catch {
                    errorMessage = String(describing: error)
                }
            }
        }
    }

    private func performShred() async {
        guard let pendingRequest else { return }
        isShredding = true
        progress = nil
        defer { isShredding = false }

        do {
            try await environment.shredder.confirmShred(pendingRequest, passes: passes) { completed, total in
                Task { @MainActor in progress = (completed, total) }
            }
            lastShreddedPath = pendingRequest.path
            confirmationStep = .none
            self.pendingRequest = nil
        } catch {
            errorMessage = String(describing: error)
            confirmationStep = .none
            self.pendingRequest = nil
        }
    }

    // MARK: - Sheet bindings

    private var firstConfirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmationStep == .first },
            set: { if !$0, confirmationStep == .first { confirmationStep = .none; pendingRequest = nil } }
        )
    }

    private var secondConfirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmationStep == .second },
            set: { if !$0, confirmationStep == .second, !isShredding { confirmationStep = .none; pendingRequest = nil } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
