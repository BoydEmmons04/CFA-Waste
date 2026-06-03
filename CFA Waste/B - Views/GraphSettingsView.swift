import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GraphSettingsView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var graphVM: GraphViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var number: Int = 0
    @State private var isSaving: Bool = false
    @State private var loadError: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account")) {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(name.isEmpty ? "—" : name)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Number")
                        Spacer()
                        Text("\(number)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Top Banner Mode")) {
                    Picker("Top Banner Mode", selection: $graphVM.topBannerMode) {
                        ForEach(GraphViewModel.BannerMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if isSaving {
                        HStack {
                            ProgressView()
                            Text("Saving…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !loadError.isEmpty {
                    Section {
                        Text(loadError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .toolbar {
                // Keep leading side free so the system "Back" button appears automatically if this view pushes deeper.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .task { await loadSettings() }
            .onChange(of: graphVM.topBannerMode) { newMode in
                isSaving = true
                Task {
                    await graphVM.saveTopBannerMode(newMode)
                    await MainActor.run { isSaving = false }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

extension GraphViewModel.BannerMode {
    var title: String {
        switch self {
        case .daily:   return "Daily Total"
        case .weekly:  return "Weekly Total"
        case .monthly: return "Monthly Total"
        }
    }
}

private extension GraphSettingsView {
    func loadSettings() async {
        loadError = ""
        guard let uid = Auth.auth().currentUser?.uid ?? auth.userId, !uid.isEmpty else {
            await MainActor.run { loadError = "Missing user ID." }
            return
        }
        let db = Firestore.firestore()
        let account = db.collection("users").document(uid).collection("account")
        do {
            async let nameDoc = account.document("Name").getDocument()
            async let numberDoc = account.document("Number").getDocument()

            let (n, num) = try await (nameDoc, numberDoc)

            let fetchedName = (n.data()?["value"] as? String) ?? ""
            let fetchedNumber = (num.data()?["value"] as? Int) ?? 0

            await MainActor.run {
                self.name = fetchedName
                self.number = fetchedNumber
            }
        } catch {
            await MainActor.run { loadError = "Failed to load settings: \(error.localizedDescription)" }
        }
    }
}
