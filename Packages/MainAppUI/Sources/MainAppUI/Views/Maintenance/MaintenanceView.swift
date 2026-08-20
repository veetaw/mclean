import MaintenanceScripts
import SwiftUI
import UIDesignSystem

/// Lists every `MaintenanceTask` this build offers (flush DNS, rebuild
/// Spotlight index, verify startup disk, clear font cache) — each one's
/// `description` is always visible before its "Run" button can be tapped,
/// per `MaintenanceTask`'s own contract, and nothing here ever runs
/// automatically. These bypass `SafetyRules`/quarantine entirely by design
/// (fixed, reviewed command set, no arbitrary file path) — see
/// `MaintenanceTask`'s doc comment.
@available(macOS 26.0, *)
struct MaintenanceView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var runningTaskID: String?
    @State private var results: [String: MaintenanceTaskResult] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.large) {
                ModuleHeroHeader(
                    title: "Maintenance",
                    systemImage: "stethoscope",
                    subtitle: "Each action below only ever runs when you tap Run — nothing here happens automatically or in the background."
                )

                ForEach(environment.maintenanceTasks, id: \.id) { task in
                    taskCard(task)
                }
            }
            .padding(DSSpacing.xLarge)
        }
    }

    private func taskCard(_ task: any MaintenanceTask) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.small) {
                HStack {
                    Text(task.title).font(DSTypography.heading)
                    if task.requiresAdministratorPrivileges {
                        // Deliberately not `SafetyBadge` here — that
                        // component means "SafetyRules verdict tier," a
                        // different concept from "this needs macOS's admin
                        // password prompt." Plain text avoids conflating them.
                        Label("Requires admin password", systemImage: "lock.shield")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.warning)
                    }
                    Spacer()
                }

                Text(task.description)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)

                if let result = results[task.id] {
                    resultRow(result)
                }

                HStack {
                    Spacer()
                    Button(runningTaskID == task.id ? "Running…" : "Run", systemImage: "play.fill") {
                        Task { await run(task) }
                    }
                    .dsButtonStyle(task.requiresAdministratorPrivileges ? .destructive : .primary)
                    .disabled(runningTaskID != nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resultRow(_ result: MaintenanceTaskResult) -> some View {
        Label(result.summary, systemImage: result.outcome == .success ? "checkmark.circle" : "xmark.circle")
            .font(DSTypography.caption)
            .foregroundStyle(result.outcome == .success ? DSColor.safe : DSColor.destructive)
    }

    private func run(_ task: any MaintenanceTask) async {
        runningTaskID = task.id
        defer { runningTaskID = nil }
        results[task.id] = await task.run()
    }
}
