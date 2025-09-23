//
//  DynamicGroupView.swift
//  CFA Waste
//
//  Created by Boyd Emmons on 9/22/25.
//

import SwiftUI

// ViewModel that listens to Firestore groups via FirebaseService
final class GroupsVM: ObservableObject {
    @Published var groups: [GroupInfo] = []
    @Published var selectedGroupId: String?

    private let storeId: String
    private let service = FirebaseService.shared

    init(storeId: String, includeDisabled: Bool = false) {
        self.storeId = storeId
        service.listenGroups(forUserId: storeId, includeDisabled: includeDisabled) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let groups):
                    // groups come back ordered; ensure again just in case
                    let ordered = groups.sorted { $0.order < $1.order }
                    self?.groups = ordered
                    if self?.selectedGroupId == nil { self?.selectedGroupId = ordered.first?.id }
                case .failure(let err):
                    print("Groups listen error:", err)
                }
            }
        }
    }

    deinit { service.stopGroups() }
}

/// Host container that procedurally shows a tab per group and renders ButtonGridView
struct GroupsHostView: View {
    @StateObject private var vm: GroupsVM
    @ObservedObject var buttonGridVM: ButtonGridViewModel
    @Binding var isMoving: Bool
    @Binding var selectedDate: Date

    /// Create a host bound to a storeId (the only login you mentioned)
    init(storeId: String,
         buttonGridVM: ButtonGridViewModel,
         isMoving: Binding<Bool>,
         selectedDate: Binding<Date>,
         includeDisabled: Bool = false) {
        _vm = StateObject(wrappedValue: GroupsVM(storeId: storeId, includeDisabled: includeDisabled))
        self.buttonGridVM = buttonGridVM
        self._isMoving = isMoving
        self._selectedDate = selectedDate
    }

    var body: some View {
        Group {
            if vm.groups.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading groups…").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $vm.selectedGroupId) {
                    ForEach(vm.groups, id: \.id) { group in
                        // Render the existing grid for the selected group
                        ButtonGridView(
                            viewModel: buttonGridVM,
                            group: group.id,
                            isMoving: $isMoving,
                            selectedDate: selectedDate,
                            availableGroups: vm.groups
                        )
                        .tabItem {
                            if let icon = group.icon { Image(systemName: icon) }
                            Text(group.title)
                        }
                        .tag(Optional(group.id)) // selection is Optional<String>
                    }
                }
            }
        }
    }
}

/// Thin wrapper if you want to reuse this elsewhere without tabs
struct DynamicGroupView: View {
    @ObservedObject var buttonGridVM: ButtonGridViewModel
    let groupId: String
    @Binding var isMoving: Bool
    let selectedDate: Date
    let availableGroups: [GroupInfo]

    var body: some View {
        ButtonGridView(
            viewModel: buttonGridVM,
            group: groupId,
            isMoving: $isMoving,
            selectedDate: selectedDate,
            availableGroups: availableGroups
        )
    }
}

#if DEBUG
struct GroupsHostView_Previews: PreviewProvider {
    static var previews: some View {
        GroupsHostView(
            storeId: "DEMO_STORE",
            buttonGridVM: ButtonGridViewModel(),
            isMoving: .constant(false),
            selectedDate: .constant(Date())
        )
    }
}
#endif
