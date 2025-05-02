//
//  ARCoordinator.swift
//  CollabTest
//
//  Created by Rahul on 3/13/24.
//

import SwiftUI
import MultipeerConnectivity
import ARKit
import GameKit

class ARCoordinator: ObservableObject {
    typealias P = GKPlayer

    private static let appDataKey = "arcollab-app_data"
    enum SessionMode: String, CaseIterable, Codable {
        case object = "View"
        case annotate = "Annotate"
        case slice = "Slice"

        var labelImage: String {
            switch self {
            case .object:
                "rotate.3d"
            case .annotate:
                "hand.tap.fill"
            case .slice:
                "scissors"
            }
        }
    }

    struct UserActionUpdate: Codable {
        let username: String
        let action: UserAction

        enum UserAction: Codable {
            case annotate
            case controlling
            case idle
        }

        var description: String {
            switch self.action {
            case .annotate:
                "\(username) added an annotation"
            case .controlling:
                "\(username) is controlling"
            case .idle:
                ""
            }
        }
    }

    struct SavedState: Codable {
        let appData: AppData
    }

    var networkingService: (any NetworkingProtocol<P>)?

    @Published private(set) var availablePeers = Set<P>()
    @Published private(set) var connectedPeers = Set<P>() {
        didSet {
            print("connected peers: \(connectedPeers)")
        }
    }
    @Published private(set) var appData = AppData()
    @Published var sessionMode: SessionMode = .object {
        didSet {
//            if sessionMode != .annotate {
//                sendUpdatedSessionMode()
//            }
//
            if sessionMode == .slice, isSliceHidden {
                toggleHideSlice()
            }
        }
    }
    @Published private(set) var isSliceHidden = true
    @Published private(set) var previouslySavedAppData: AppData?
    @Published private(set) var didPlaceModel = false
    @Published private(set) var showScanMessage = false
    @Published private(set) var showSuccessConnectionMessage = false

    @Published var cameraIsOn = true

    @Published private(set) var userActionUpdate: UserActionUpdate? {
        didSet {
            if userActionUpdate?.action == .annotate && userActionUpdate?.username != networkingService?.currentPeer.displayName {
                Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    self.userActionUpdate = nil
                }
            }
        }
    }

    @Published var joiningRemotely = false

    private var shouldSendUpdatedSessionMode = true // workaround to avoid network cycle

    var localModelPath: URL?
    var didReceiveDataHandler: ((Data, MCPeerID) -> Void)?
    var toggleHideSliceHandler: ((Bool) -> (Bool))?
    var resetSliceHandler: (() -> ())?
    var resetModelHandler: (() -> ())?
    var toggleSliceOrientationHandler: (() -> ())?
    var loadPreviousStateHandler: ((AppData) -> ())?
    var toggleCameraHandler: ((Bool) -> ())?

    var availableDevices: [String] {
        Array(availablePeers).map { $0.displayName }
    }

    var connectedDevices: [String] {
        Array(connectedPeers).map { $0.displayName }
    }

    var controlStateColor: Color {
        if userActionUpdate?.username == networkingService?.currentPeer.displayName {
            return .green
        } else if userActionUpdate?.action == .annotate {
            return .blue
        } else {
            return .red
        }
    }

    init() {
        getPreviouslySavedData()
    }

    func reset() {
        isSliceHidden = true
        didPlaceModel = false
        localModelPath = nil

    }

    // MARK: - User Intents
    func setNameAndLookForDevices(name: String) {
        // multipeerSession = MultipeerSession(name: name)
        // multipeerSession?.arMultipeerSessionDelegate = self
        // let service = MultipeerNetworkingService()
        let service = GameKitNetworkingService()
        service.delegate = self
        networkingService = service

        networkingService?.initialize(with: name) {
            self.connectedPeers.insert(service.currentPeer)
        }

//        beginARSession()

//        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//            service.invitePeer(.init())
//        }
    }

    func startSharePlay() {
        networkingService?.startShareplayActivity()
    }

    func requestConnection(with peer: String) {
        if let peerToConnect = availablePeers.first(where: { $0.displayName == peer }) {
            networkingService?.invitePeer(peerToConnect)
        }
    }

    func updateLocalModelPath(newValue: URL?) {
        self.localModelPath = newValue
    }

    func toggleCameraIsOn() {
        cameraIsOn.toggle()
        toggleCameraHandler?(cameraIsOn)
    }

    func beginARSession() {
        appData.currentState = .arSession
        sendAppDataToPeers()
    }

    func endARSession() {
        appData.currentState = .connectingToDevices
        sendAppDataToPeers()
    }

    func updateMaterialSlice(newValue: SIMD4<Float>) {
        appData.modelData.planeInfo.materialSlice = newValue
    }

    func updatePlanePosition(newValue: SIMD3<Float>) {
        appData.modelData.planeInfo.planePosition = newValue
    }

    func updatePlaneRotation(newValue: simd_quatf) {
        appData.modelData.planeInfo.planeRotation = .init(matrix: newValue)
    }

    func updateRotationMatrix(newValue: simd_quatf, rot: simd_quatf) {
        appData.modelData.rotationInfo = .init(matrix: newValue, rot: rot)
    }

    func updateScale(newValue: Float, annotationScale: Float) {
        appData.modelData.scaleInfo = .init(
            scale: newValue,
            annotationScale: annotationScale
        )
    }

//    func updateAnnotationRotation(newValue: simd_quatf) {
//        appData.modelData.annotations = .init(matrix: newValue)
//    }

    func updateAppData(using appData: AppData) {
        self.appData = appData
    }

    func sendUserActionUpdate(action: UserActionUpdate.UserAction) {
        guard let networkingService = networkingService else { return }

        let newValue = UserActionUpdate(
            username: networkingService.currentPeer.displayName,
            action: action
        )

        if action == .annotate {
            sendActionUpdateToPeers(forcedUpdateValue: newValue)
        } else {
            userActionUpdate = newValue
            sendActionUpdateToPeers()
        }

        print("SENDING ACTION UPDATE: \(userActionUpdate)")


    }

    func toggleHideSlice(shouldSend: Bool = true) {
        if let hidden = toggleHideSliceHandler?(shouldSend) {
            isSliceHidden = hidden
        }
    }

    func resetSlice() {
        if sessionMode == .slice {
            resetSliceHandler?()
        } else {
            resetModelHandler?()
        }
    }

    func toggleSliceOrientation() {
        toggleSliceOrientationHandler?()
    }

    func saveCurrentState(data: AppData? = nil, shouldSend: Bool = false) {
        let dataToSave = data == nil ? self.appData : data

        do {
            let encodedState = try JSONEncoder().encode(dataToSave)

            UserDefaults.standard.setValue(encodedState, forKey: Self.appDataKey)

            previouslySavedAppData = appData
        } catch {
            print("could not encode state: \(error)")
        }

        if shouldSend {
            sendPreviouslySavedStateToPeers()
        }
    }

    func loadPreviousState() {
        guard let previouslySavedAppData else { return }

        loadPreviousStateHandler?(previouslySavedAppData)
    }
    
    func updateShowSuccessConnectionMessage(_ value: Bool) {
        showSuccessConnectionMessage = value
        if showSuccessConnectionMessage {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                self.showSuccessConnectionMessage = false
            }
        }
    }

    func didTapOnScreen(placedAnchor: Bool) {
        showScanMessage = !placedAnchor
        if showScanMessage {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                self.showScanMessage = false
            }
        } else {
            didPlaceModel = true
        }
    }

    // MARK: - Multipeer Functions
    func connectedTo(_ peer: String) -> Bool {
        connectedPeers.contains(where: { $0.displayName == peer })
    }

    func sendAppDataToPeers() {
        do {
            let data = try JSONEncoder().encode(appData)
            print(data.count)

            // multipeerSession?.sendToAllPeers(data, reliably: true)
            networkingService?.sendToAllPeers(data, reliably: false)
        } catch {
            print("Could not encode app data: \(error)")
        }
    }

    func sendRotationInfoToPeers() {
        do {
            let data = try JSONEncoder().encode(appData.modelData.rotationInfo)

            networkingService?.sendToAllPeers(data, reliably: true)
            // multipeerSession?.sendToAllPeers(data, reliably: true)
        } catch {
            print("Could not encode rotation data: \(error)")
        }
    }

    func sendModelDataToPeers() {
        do {
            let data = try JSONEncoder().encode(appData.modelData)

            networkingService?.sendToAllPeers(data, reliably: true)
            // multipeerSession?.sendToAllPeers(data, reliably: true)
        } catch {
            print("Could not encode model data: \(error)")
        }
    }

    func sendPlaneInfoToPeers() {
        do {
            let data = try JSONEncoder().encode(appData.modelData.planeInfo)

            networkingService?.sendToAllPeers(data, reliably: true)
            // multipeerSession?.sendToAllPeers(data, reliably: true)
        } catch {
            print("Could not encode plane data: \(error)")
        }
    }

    func sendPlaneRotationInfoToPeers() {
        do {
            let data = try JSONEncoder().encode(appData.modelData.planeInfo.planeRotation)

            networkingService?.sendToAllPeers(data, reliably: true)
            // multipeerSession?.sendToAllPeers(data, reliably: true)
        } catch {
            print("Could not encode plane data: \(error)")
        }
    }

    func sendScaleInfoToPeers() {
        do {
            let data = try JSONEncoder().encode(appData.modelData.scaleInfo)

            networkingService?.sendToAllPeers(data, reliably: true)
            // multipeerSession?.sendToAllPeers(data, reliably: true)
        } catch {
            print("Could not encode model scale data: \(error)")
        }
    }

    func sendUpdatedSessionMode() {
        if shouldSendUpdatedSessionMode {
            do {
                let data = try JSONEncoder().encode(sessionMode)

                networkingService?.sendToAllPeers(data, reliably: true)
                // multipeerSession?.sendToAllPeers(data, reliably: true)
            } catch {
                print("Could not encode model data: \(error)")
            }
        }
    }

    func sendActionUpdateToPeers(forcedUpdateValue: UserActionUpdate? = nil) {
        let userActionUpdate = forcedUpdateValue ?? self.userActionUpdate

        do {
            let data = try JSONEncoder().encode(userActionUpdate)

            networkingService?.sendToAllPeers(data, reliably: true)
        } catch {
            print("Could not encode control state data: \(error)")
        }
    }

    func sendPreviouslySavedStateToPeers() {
        guard let previouslySavedAppData else { return }

        do {
            let savedData = SavedState(appData: previouslySavedAppData)

            let data = try JSONEncoder().encode(savedData)

            networkingService?.sendToAllPeers(data, reliably: true)
            // multipeerSession?.sendToAllPeers(data, reliably: true)
        } catch {
            print("Could not encode control state data: \(error)")
        }
    }

    func sendAnnotationDataToPeers() {
        do {
            let data = try JSONEncoder().encode(appData.modelData.annotations)

            networkingService?.sendToAllPeers(data, reliably: true)
        } catch {
            print("Could not encode annotations data: \(error)")
        }
    }

    // MARK: - Private
    private func getPreviouslySavedData() {
        if let savedData = UserDefaults.standard.data(
            forKey: Self.appDataKey
        ), let decodedData = try? JSONDecoder().decode(AppData.self, from: savedData) {
            self.previouslySavedAppData = decodedData
        }
    }
}

extension ARCoordinator: NetworkingDelegate {
    func didReceiveData(_ data: Data, from peer: P) {
        print("received data: \(data)")
        if let newAppData = try? JSONDecoder().decode(AppData.self, from: data) {
            print("received new app data: \(newAppData)")
            appData.updateState(using: newAppData)
        } else if let newRotationInfo = try? JSONDecoder().decode(AppData.RotationInfo.self, from: data) {
            appData.modelData.rotationInfo = newRotationInfo
        } else if let newPlaneInfo = try? JSONDecoder().decode(AppData.PlaneInfo.self, from: data) {
            appData.modelData.planeInfo = newPlaneInfo
            if sessionMode != .slice, !isSliceHidden {
                toggleHideSlice(shouldSend: false)
            }
        } else if let newModelInfo = try? JSONDecoder().decode(AppData.ModelData.self, from: data) {
            appData.modelData = newModelInfo
        } else if let newSessionMode = try? JSONDecoder().decode(SessionMode.self, from: data) {
            shouldSendUpdatedSessionMode = false
            self.sessionMode = newSessionMode
            shouldSendUpdatedSessionMode = true
        } else if let savedData = try? JSONDecoder().decode(SavedState.self, from: data) {
            self.previouslySavedAppData = savedData.appData

            saveCurrentState(data: savedData.appData, shouldSend: false)
        } else if let userActionUpdate = try? JSONDecoder().decode(UserActionUpdate.self, from: data) {
            self.userActionUpdate = userActionUpdate
        }

        didReceiveDataHandler?(data, MCPeerID(displayName: peer.displayName)) // Temporary adapter for transition
    }

    func peerDidChangeState(_ peer: P, isConnected: Bool) {
        if isConnected {
            connectedPeers.insert(peer)
        } else {
            connectedPeers.remove(peer)
        }
    }

    func didFindPeer(_ peer: P) {
        availablePeers.insert(peer)
    }

    func didLosePeer(_ peer: P) {
        availablePeers.remove(peer)
    }
}
