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
                VStack(spacing: 8) {
                    // Non-swipe group selector (horizontally scrollable chips)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(vm.groups, id: \.id) { group in
                                let isSelected = (vm.selectedGroupId == group.id)
                                Button(action: { vm.selectedGroupId = group.id }) {
                                    HStack(spacing: 6) {
                                        Text(group.title)
                                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                                    )
                                    .overlay(
                                        Capsule().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
                                    )
                                    .foregroundColor(isSelected ? Color.accentColor : Color.primary)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 6)
                    }

                    // Selected group's grid (no outer swipe; inner pager remains active)
                    if let currentId = vm.selectedGroupId {
                        ButtonGridView(
                            viewModel: buttonGridVM,
                            group: currentId,
                            isMoving: $isMoving,
                            selectedDate: selectedDate,
                            availableGroups: vm.groups
                        )
                        .id(currentId) // ensure content refreshes when switching groups
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .contentShape(Rectangle()) // ensure full hit area for swipes
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // let grid expand to full space
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
