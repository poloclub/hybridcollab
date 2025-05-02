//
//  ARCollabView.swift
//  CollabTest
//
//  Created by Rahul on 3/14/24.
//

import SwiftUI

struct ARCollabView: View {
    @EnvironmentObject private var arCoordinator: ARCoordinator
    // @State private var showingFiles = false

    @State private var showingImport = false

    var body: some View {
        RealityViewContainer()
            .ignoresSafeArea()
            .onAppear {
                if let url = Bundle.main.url(forResource: "heart_model", withExtension: "obj") {
                    arCoordinator.localModelPath = url
                }
            }
            .overlay(alignment: .top) {
                if arCoordinator.showScanMessage {
                    Text("Continue scanning to place object...")
                        .foregroundStyle(.white)
                        .padding()
                        .background(.gray.opacity(0.7), in: RoundedRectangle(cornerRadius: 8.0))
                        .minimumScaleFactor(0.7)
                        .padding(.top)
                }

                if let controlState = arCoordinator.userActionUpdate , let peer = arCoordinator.connectedPeers.first(
                    where: { $0.displayName == controlState.username }), controlState.action != .idle {
                    ControlLabelView(controlState: controlState, peer: peer)
                } else if arCoordinator.showSuccessConnectionMessage {
                    Text("Nearby Connection Established!")
                        .foregroundStyle(.white)
                        .padding()
                        .background(.green.opacity(0.7), in: RoundedRectangle(cornerRadius: 8.0))
                        .minimumScaleFactor(0.7)
                        .padding(.top)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showingImport {
                    importButton
                        .padding(16)
                } else {
                    HStack(spacing: 16) {
                        sessionModeControl

                        Spacer()

                        if arCoordinator.sessionMode == .slice {
                            toggleSliceOrientationButton
                        } else {
                            hideSliceButton
                        }
                        // resetSliceButton
                    }
                    .padding(16)
                }
            }
            .overlay(alignment: .topLeading) {
                endSessionButton
                    .padding(16)
            }
            .overlay(alignment: .bottom) {
                if arCoordinator.didPlaceModel {
                    // loadSavesButton
                    toggleCameraButton
                        .padding(16)
                }
            }
            .environment(\.colorScheme, .light)
            .animation(.easeInOut, value: arCoordinator.showScanMessage)
    }

    private var importButton: some View {
        Button {
            if let url = Bundle.main.url(forResource: "heart_model", withExtension: "obj") {
                arCoordinator.localModelPath = url
                showingImport = false
            }
            // showingFiles = true
        } label: {
            ZStack {
                Circle()
                    .foregroundStyle(.thinMaterial)

                Image("custom.heart.fill.badge.plus")
                    .imageScale(.large)
                    .padding(8)
                    .foregroundStyle(.black)
                    .offset(y: 3)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var loadSavesButton: some View {
        Menu {
            Button {
                arCoordinator.saveCurrentState(shouldSend: true)
            } label: {
                Label("Save State", systemImage: "square.and.arrow.down.fill")
            }

            Button {
                arCoordinator.loadPreviousState()
            } label: {
                Label("Load Previously Saved State", systemImage: "folder.fill")
            }
            .disabled(arCoordinator.previouslySavedAppData == nil)
        } label: {
            ZStack {
                Circle()
                    .foregroundStyle(.thinMaterial)

                Image(systemName: "square.and.arrow.down.fill")
                    .imageScale(.large)
                    .padding(8)
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var resetSliceButton: some View {
        ARCollabViewButton(systemImage: arCoordinator.sessionMode == .object ? "arrow.clockwise.heart" : "arrow.clockwise") {
            arCoordinator.resetSlice()
        }
    }

    private var hideSliceButton: some View {
        ARCollabViewButton(systemImage: arCoordinator.isSliceHidden ? "eye" : "eye.slash") {
            arCoordinator.toggleHideSlice()
        }
    }

    private var toggleSliceOrientationButton: some View {
        ARCollabViewButton(systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down.fill"){
            arCoordinator.toggleSliceOrientation()
        }
    }

    private var endSessionButton: some View {
        ARCollabViewButton(systemImage: "xmark") {
            arCoordinator.endARSession()
        }
    }

    private var toggleCameraButton: some View {
        Button {
            arCoordinator.toggleCameraIsOn()
        } label: {
            ZStack {
                Capsule()
                    .foregroundStyle(.thinMaterial)

                Group {
                    if arCoordinator.cameraIsOn {
                        Label("Switch to VR", systemImage: "lightbulb.slash.fill")
                    } else {
                        Label("Switch to AR", systemImage: "arkit")
                    }
                }
                .imageScale(.large)
                .padding(12)
                .padding(.horizontal, 8)
                .foregroundStyle(.black)
            }
        }
        .padding(8)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 30)
        .disabled(arCoordinator.localModelPath == nil)
    }

    private var sessionModeControl: some View {
        Menu {
            Picker(selection: $arCoordinator.sessionMode) {
                ForEach(ARCoordinator.SessionMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.labelImage)
                        .tag(mode)
                }
            } label: {
                EmptyView()
            }
        } label: {
            ZStack {
                Circle()
                    .foregroundStyle(.blue.opacity(0.5))

                Image(systemName: arCoordinator.sessionMode.labelImage)
                    .imageScale(.large)
                    .padding(8)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
    }
}

fileprivate struct ControlLabelView: View {
    @EnvironmentObject private var arCoordinator: ARCoordinator
    @StateObject private var profileImage: PeerProfileImage
    let controlState: ARCoordinator.UserActionUpdate

    init(controlState: ARCoordinator.UserActionUpdate, peer: ARCoordinator.P) {
        self.controlState = controlState

        _profileImage = StateObject(wrappedValue: PeerProfileImage(peer: peer))
    }

    var body: some View {
        HStack(spacing: 8) {
            (profileImage.image ?? Image(systemName: "person.circle.fill"))
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .foregroundColor(.gray)

            Text(controlState.description)
        }
        .foregroundStyle(.white)
        .padding()
        .background(arCoordinator.controlStateColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 8.0))
        .minimumScaleFactor(0.7)
        .padding(.top)
        .onTapGesture(count: 2) {
            arCoordinator.sendUserActionUpdate(action: .idle)
        }
    }
}

fileprivate struct ARCollabViewButton: View {
    let systemImage: String
    let action: () -> ()

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .foregroundStyle(.thinMaterial)

                Image(systemName: systemImage)
                    .imageScale(.large)
                    .padding(8)
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 30, height: 30)
    }
}

#Preview {
    ARCollabView()
        .environmentObject(ARCoordinator())
}
