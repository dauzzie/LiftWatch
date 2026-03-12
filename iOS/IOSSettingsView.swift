import SwiftUI
import UniformTypeIdentifiers

struct IOSSettingsView: View {
    @EnvironmentObject private var store: ExerciseStore
    @EnvironmentObject private var cloud: CloudSyncManager

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument = LiftWatchBackupDocument()
    @State private var backupMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Day Reset") {
                    DatePicker(
                        "Reset Time",
                        selection: Binding(
                            get: { cutoffDate },
                            set: { store.updateCutoff(to: minutesSinceMidnight(for: $0)) }
                        ),
                        displayedComponents: .hourAndMinute
                    )

                    Text("Workouts are active from this time to the next day at the same time. At reset, current logs move to history and the active list clears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Library") {
                    NavigationLink("Manage Custom Exercises") {
                        IOSExerciseLibraryView()
                    }
                    NavigationLink("Weightlifting Similarity Table") {
                        IOSWorkoutSimilarityView()
                    }
                }

                Section("Cloud Sync") {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.fill")
                            .foregroundStyle(cloudColor)
                        Text(cloud.syncStatus)
                            .fontWeight(.semibold)
                            .foregroundStyle(cloudColor)
                    }

                    if !cloud.syncDetail.isEmpty {
                        Text(cloud.syncDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Sync Now") {
                        cloud.manualSync()
                    }
                }

                Section("Backup") {
                    Button("Export Backup JSON") {
                        do {
                            exportDocument = LiftWatchBackupDocument(data: try store.exportBackupData())
                            isExporting = true
                        } catch {
                            backupMessage = error.localizedDescription
                        }
                    }

                    Button("Import Backup JSON") {
                        isImporting = true
                    }

                    if let backupMessage {
                        Text(backupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "liftwatch-backup"
            ) { result in
                switch result {
                case .success:
                    backupMessage = "Backup exported successfully."
                case .failure(let error):
                    backupMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let data = try Data(contentsOf: url)
                        try store.importBackupData(data)
                        backupMessage = "Backup imported successfully."
                    } catch {
                        backupMessage = error.localizedDescription
                    }
                case .failure(let error):
                    backupMessage = error.localizedDescription
                }
            }
        }
    }

    private var cutoffDate: Date {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .minute, value: store.settings.cutoffMinutes, to: start) ?? now
    }

    private func minutesSinceMidnight(for date: Date) -> Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private var cloudColor: Color {
        switch cloud.syncLevel {
        case .idle: return .secondary
        case .syncing: return .orange
        case .success: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }
}

#Preview {
    IOSSettingsView()
        .environmentObject(ExerciseStore())
        .environmentObject(CloudSyncManager())
}
