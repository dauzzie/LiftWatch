import SwiftUI

struct IOSExerciseLibraryView: View {
    @EnvironmentObject private var store: ExerciseStore

    @State private var category: ExerciseCategory = .weightlifting
    @State private var weightCategory: WeightliftingCategory = .push
    @State private var name = ""
    @State private var symbol = "hare.fill"
    @State private var muscles = ""

    var body: some View {
        Form {
            Section("Add Custom Exercise") {
                Picker("Type", selection: $category) {
                    Text("Weightlifting").tag(ExerciseCategory.weightlifting)
                    Text("Cardio").tag(ExerciseCategory.cardio)
                }
                .pickerStyle(.segmented)

                if category == .weightlifting {
                    Picker("Category", selection: $weightCategory) {
                        ForEach(WeightliftingCategory.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }

                TextField("Exercise Name", text: $name)

                if category == .weightlifting {
                    TextField("Target muscles (comma-separated)", text: $muscles)
                }

                Picker("Symbol", selection: $symbol) {
                    ForEach(store.availableCustomSymbols(), id: \.self) { item in
                        Label(item, systemImage: item).tag(item)
                    }
                }

                Button("Add Exercise") {
                    let parsedMuscles = muscles
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    store.addCustomExercise(
                        name: name,
                        symbol: symbol,
                        category: category,
                        weightliftingCategory: category == .weightlifting ? weightCategory : nil,
                        targetMuscles: parsedMuscles
                    )

                    name = ""
                    muscles = ""
                    symbol = store.availableCustomSymbols().first ?? "star.fill"
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.availableCustomSymbols().isEmpty)
            }

            Section("Custom Exercises") {
                if store.customExercises.isEmpty {
                    Text("No custom exercises yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.customExercises) { exercise in
                        HStack {
                            Label(exercise.name, systemImage: exercise.symbol)
                            Spacer()
                            Text(label(for: exercise))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeCustomExercise(id: exercise.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Unused Symbol Library") {
                let available = store.availableCustomSymbols()
                if available.isEmpty {
                    Text("All symbols in this library are used.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(available, id: \.self) { item in
                                Image(systemName: item)
                                    .frame(width: 32, height: 32)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Exercise Library")
        .onAppear {
            if let first = store.availableCustomSymbols().first {
                symbol = first
            }
        }
    }

    private func label(for exercise: ExerciseDefinition) -> String {
        if exercise.category == .cardio {
            return "Cardio"
        }
        return exercise.weightliftingCategory?.title ?? "Weightlifting"
    }
}

#Preview {
    IOSExerciseLibraryView()
        .environmentObject(ExerciseStore())
}
