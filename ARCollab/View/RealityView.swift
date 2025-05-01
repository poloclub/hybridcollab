//
//  RealityView.swift
//  shaderTest
//
//  Created by Pratham Mehta on 06/03/24.
//

import Foundation
import SwiftUI
import RealityKit
import MetalKit
import ARKit
import MultipeerConnectivity

struct AnnotationData: Codable {
    let position: SIMD3<Float>
    let text: String
}


class RealityView: ARView {
    static let defaultSlice = SIMD4<Float>(0, 1, 0, 3)
    static let hiddenSlice = SIMD4<Float>(0, 0, 0, 0)

    var planeEquation = SIMD4<Float>(0, 0, 0, 0)

    let initNormal: simd_float3 = simd_float3(x: 0, y: 0, z: -1)

    /// A view that guides the user through capturing the scene.
    var coachingView: ARCoachingOverlayView?

    /// The Metal device loads Metal libraries.
    var device: MTLDevice?

    /// The Metal library loads shader functions.
    var library: MTLLibrary?

    var heartScene: AnchorEntity?

//    var heartCollectionEntity: AnchorEntity?

    var heartEntity: HeartEntity?

    var heartEntityInner: HeartEntity?

    var slicingPlane: ModelEntity?

    var prevSlicingScale: CGFloat = 1.0

    var prevModelScale: CGFloat = 1.0

    var prevSliceRotation: CGFloat = 1.0

    var prevSliceTranslation: CGPoint = CGPoint(x: 0, y: 0)

    var surfaceShader: CustomMaterial.SurfaceShader?

    var surfaceShaderInner: CustomMaterial.SurfaceShader?

    var surfaceShaderOuter: CustomMaterial.SurfaceShader?

    var planeShader: CustomMaterial.SurfaceShader?

    var defaultModelOrientation: simd_quatf = .init()

    var arCoordinator: ARCoordinator?
    var multipeerSession: MultipeerSession?

    private var didPlaceEntity = false

    var initialCameraRotation: simd_quatf = .init()
    var initialCameraRotationPlane: simd_quatf = .init()
    var initialObjectRotation: simd_quatf = .init()
    var initialPlaneRotation: simd_quatf = .init()

    private var lastSavedSlicePlane = SIMD4<Float>(0, 1, 0, 3)
    private var isSliceHidden = true {
        didSet {
            guard let heartEntity else { return }

            for child in heartEntity.children {
                if let annotation = child as? AnnotationEntity {
                    annotation.isEnabled = isSliceHidden
                }
            }
        }
    }

    /// Resizes the coaching view when the view size changes.
    override var frame: CGRect {
        didSet {
            coachingView?.frame = self.frame
        }
    }

    required init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Setup behavior called when the RealityView is created.
    func setup() {
        session.delegate = self

        // Used to reset anchor properties when restarting a session
        for anchor in session.currentFrame?.anchors ?? [] {
            session.remove(anchor: anchor)
        }

        setupCollaboration()

        if arCoordinator?.joiningRemotely == false {
            setupMultipeerSession()
        }

        initializeMetal()
        setupScene()
        setupGestureRecognizers()

        // Link ARCoordinator to this view
        arCoordinator?.didReceiveDataHandler = self.receivedData(_:from:)
        arCoordinator?.resetSliceHandler = self.resetSlice
        arCoordinator?.toggleHideSliceHandler = self.toggleHideSlice
        arCoordinator?.loadPreviousStateHandler = self.loadSavedState(from:)
        arCoordinator?.toggleSliceOrientationHandler = self.toggleSliceOrientation
        arCoordinator?.resetModelHandler = self.resetModel

        arCoordinator?.toggleCameraHandler = { [weak self] cameraIsOn in
            if cameraIsOn {
                self?.environment.background = .cameraFeed()
            } else {
                self?.environment.background = .color(.black)
            }
        }
    }

    private func setupMultipeerSession() {
        multipeerSession = MultipeerSession(name: "collab")

        multipeerSession?.arMultipeerSessionDelegate = self

        multipeerSession?.beginAdvertising()
        multipeerSession?.beginBrowsing()
    }

    private func setupCollaboration() {
        let configuration = ARWorldTrackingConfiguration()

        automaticallyConfigureSession = false

        // Enable collaboration and person occlusion
        configuration.isCollaborationEnabled = true
        configuration.planeDetection = [.horizontal]

        // Set up session with the new configuration
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func setupGestureRecognizers() {
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.didTap))
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.handleRotation(sender:)))

        self.addGestureRecognizer(pinchRecognizer)
        self.addGestureRecognizer(tapRecognizer)
        self.addGestureRecognizer(panRecognizer)
    }

    private func initializeMetal() {
        guard let maybeDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Error creating default metal device.")
        }
        device = maybeDevice
        guard let maybeLibrary = maybeDevice.makeDefaultLibrary() else {
            fatalError("Error creating default metal library")
        }
        library = maybeLibrary
    }

    private func setupScene() {
        heartScene = AnchorEntity(plane: .horizontal,
                                  classification: .any,
                                  minimumBounds: [0.1, 0.1])

        self.renderOptions.insert(.disableGroundingShadows)
        self.renderOptions.insert(.disableMotionBlur)
    }

    private func modifyShaders() {
        guard let library = library else { fatalError("No Metal library available.") }

        surfaceShaderInner = CustomMaterial.SurfaceShader(
            named: "SurfaceShaderInner",
            in: library
        )

        surfaceShaderOuter = CustomMaterial.SurfaceShader(
            named: "SurfaceShaderOuter",
            in: library
        )

        planeShader = CustomMaterial.SurfaceShader(
            named: "PlaneShader",
            in: library
        )

        modifyHeartMaterials(newValues: Self.hiddenSlice)

    }

    func createPlaneEntity() -> ModelEntity {
        let planeMesh = MeshResource.generatePlane(width: 1.0, depth: 1.0)

        var planeMaterial = UnlitMaterial(color: .black)

        planeMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.5))


        let planeEntity = ModelEntity(mesh: planeMesh, materials: [planeMaterial])

        try? planeEntity.modifyMaterials {
            var customMaterial = try CustomMaterial(from: $0, surfaceShader: surfaceShaderOuter!)
            customMaterial.faceCulling = .none
            return customMaterial
        }


        return planeEntity
    }

    func setupPlaneEntity() {
        let planeEntity = createPlaneEntity()

        planeEntity.position = [0, 0, 0] // Example positioning
        planeEntity.orientation = simd_quatf(vector: [0,0,0,0])

        slicingPlane = planeEntity
    }

    @objc
        private func didTap(_ gestureRecognizer: UITapGestureRecognizer) {
            // Check if a local model path is available in the AR coordinator
            guard let _ = arCoordinator?.localModelPath else {
                // If no model is selected, print a message and exit the function
                print("did not select model")
                return
            }

            // Get the tap position relative to the view
            let pos = gestureRecognizer.location(in: self)
            print(pos) // Log the tap position for debugging

            // If an entity hasn't been placed yet
            if !didPlaceEntity {
                // Add an anchor at the tapped position
                addAnchor(at: pos)
                return
            }


            let raycasts: [CollisionCastHit] = self.hitTest(pos)

            guard let raycast: CollisionCastHit = raycasts.first else { return }

            if arCoordinator?.sessionMode == .annotate && isSliceHidden {
                addAnnotation(at: raycast.position)
            }
        }

    private func addAnnotation(at position: SIMD3<Float>, text: String? = nil){
        guard let heartEntity else { return }

        let anchor = AnnotationEntity(world: .zero)
        heartEntity.addChild(anchor)

        anchor.position = position
        anchor.initialOffset = anchor.transform.translation - heartEntity.transform.translation

        if let text {
            addTextNode(text, at: position, for: anchor)
        } else {
            presentAnnotationInput(for: anchor, at: position)
        }
    }


    private func presentAnnotationInput(
        for node: AnnotationEntity,
        at position: SIMD3<Float>
    ) {
        guard let heartEntity else { return }

        DispatchQueue.main.async {
            let positionMessage = String(format: "Enter your annotation text below at (%.2f, %.2f, %.2f)", position.x, position.y, position.z)

            let alert = UIAlertController(title: "Add Annotation", message: positionMessage, preferredStyle: .alert)

            alert.addTextField { textField in
                textField.placeholder = "Type your annotation here..."
                textField.autocorrectionType = .yes
                textField.autocapitalizationType = .sentences
                textField.becomeFirstResponder()  // Force the keyboard to appear
            }

            alert.addAction(
UIAlertAction(title: "Add", style: .default) { _ in
                if let text = alert.textFields?.first?.text {
                    self.addTextNode(text, at: position, for: node)
                    print("Annotation added: \(text)")  // Log for debugging

                    //Code added to send annotation
                    let payload = AnnotationData(
                        position: position - heartEntity.position,
                        text: text
                    )

                    if let data = try? JSONEncoder().encode(payload) {
                        self.arCoordinator?.networkingService?.sendToAllPeers(data, reliably: true)
                        self.arCoordinator?.sendUserActionUpdate(action: .annotate)
                    }
                } else {
                    print("Annotation cancelled or empty text.")  // Log for debugging
                }
            })

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                print("Annotation dialog cancelled.")  // Log for debugging
            })

            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let keyWindow = scene.windows.first(where: { $0.isKeyWindow }),
               var topController = keyWindow.rootViewController {

                while let presentedViewController = topController.presentedViewController {
                    topController = presentedViewController
                }

                topController.present(alert, animated: true) {
                    if let textField = alert.textFields?.first {
                        textField.becomeFirstResponder()  // Force the keyboard again just in case
                    }
                    print("Annotation dialog presented successfully.")  // Log for debugging
                }
            } else {
                print("Failed to present annotation dialog: Unable to access root view controller.")  // Log for debugging
            }
        }
    }

    private func addTextNode(
        _ text: String,
        at position: SIMD3<Float>,
        for node: AnnotationEntity
    ) {
        guard !text.isEmpty else { return }

        let textMesh = MeshResource.generateText(text, extrusionDepth: 0.001)

        let textMaterial = UnlitMaterial(color: .white)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])

        textEntity.scale = SIMD3<Float>(0.001, 0.001, 0.001)

        let textWidth = textMesh.bounds.extents.x * 0.001
        let textHeight = textMesh.bounds.extents.y * 0.001

        let backgroundMesh = MeshResource.generatePlane(
            width: textWidth + 2 * 15 * 0.001,
            height: textHeight * 3,
            cornerRadius: 12.0
        )
        var backgroundMaterial = UnlitMaterial(
            color: .black
        )

        backgroundMaterial.blending = .transparent(opacity: 0.75)

        let backgroundEntity = ModelEntity(mesh: backgroundMesh, materials: [backgroundMaterial])

        let containerEntity = ModelEntity()

        textEntity.position = SIMD3<Float>(
            -textWidth / 2,
            -3 * textHeight / 4,
            0
        )
        backgroundEntity.addChild(textEntity)

        backgroundEntity.position = SIMD3<Float>(0.025, 0.025, -0.001)

        containerEntity.addChild(backgroundEntity)

        node.addChild(containerEntity)

        containerEntity.orientation = self.cameraTransform.rotation
    }

    private func addAnchor(at pos: CGPoint) {
        guard let arCoordinator = arCoordinator, let localModelPath = arCoordinator.localModelPath else { return }

        if let query = makeRaycastQuery(from: self.center, allowing: .estimatedPlane, alignment: .horizontal),
           let firstResult = session.raycast(query).first {

            let heartAnchor = HeartAnchor(transform: firstResult.worldTransform)

            session.add(anchor: heartAnchor)
            multipeerSession?
                .sendToAllPeers(
                    try! NSKeyedArchiver
                        .archivedData(
                            withRootObject: heartAnchor,
                            requiringSecureCoding: true
                        ),
                    reliably: true
                )

            print("Placed Anchor")
            arCoordinator.didTapOnScreen(placedAnchor: true)
        } else {
            arCoordinator.didTapOnScreen(placedAnchor: false)
        }
    }

    private func placeEntity(using anchor: HeartAnchor) {
        if let modelEntity = HeartEntity(heartAnchor: anchor) {
            heartEntity = modelEntity
            arCoordinator?.updateLocalModelPath(newValue: heartEntity?.modelPath)

            if var model = heartEntity?.model {
                var material = SimpleMaterial()
                material.roughness = 1
                model.materials = [material]
                heartEntity?.model = model

                if let modelComponent = heartEntity?.model {
                    Task {
                        let convex = try await ShapeResource.generateStaticMesh(
                            from: modelComponent.mesh
                        )
                        heartEntity?.collision = .init(shapes: [convex])
                    }
                }

                heartEntityInner = heartEntity?.clone(recursive: true)
                heartEntityInner?.name = "heartInner"

            }

            heartEntity?.scale = SIMD3(repeating: 0.008)
            heartEntity?.name = "heart"

            heartEntityInner = heartEntity?.clone(recursive: true)
            heartEntityInner?.name = "heartInner"

            modifyShaders()

            if let heartScene, let heartEntity, let heartEntityInner {
                heartScene.addChild(heartEntity)
                heartScene.addChild(heartEntityInner)

                scene.addAnchor(heartScene)

                defaultModelOrientation = heartEntity.orientation
            }

            setupPlaneEntity()

            didPlaceEntity = true
            arCoordinator?.didTapOnScreen(placedAnchor: true)
        } else {
            print("unable to place entity")
        }
    }

    func receivedData(_ data: Data, from peer: MCPeerID) {
        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARSession.CollaborationData.self,
            from: data
        ) {
            session.update(with: collaborationData)
            return
        }

        if let anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HeartAnchor.self, from: data) {
            session.add(anchor: anchor)
        }

        if let annotation = try? JSONDecoder().decode(AnnotationData.self, from: data) {
            print("RECEIVED ANNOTATION")
            DispatchQueue.main.async {
                if let heartEntity = self.heartEntity {
                    self.addAnnotation(
                        at: annotation.position + heartEntity.position,
                        text: annotation.text
                    )
                }
            }
            return
        }

        if let appData = try? JSONDecoder().decode(AppData.self, from: data) {
            slicingPlane?.position = appData.modelData.planeInfo.planePosition
            slicingPlane?.transform.rotation = appData.modelData.planeInfo.planeRotation.rotationInfo.matrix

            modifyHeartMaterials(newValues: appData.modelData.planeInfo.materialSlice)

            heartEntity?.transform.rotation = appData.modelData.rotationInfo.matrix
            heartEntity?.transform.scale = SIMD3<Float>(repeating: appData.modelData.scaleInfo.scale)

            heartEntityInner?.transform.rotation = appData.modelData.rotationInfo.matrix
            heartEntityInner?.transform.scale = SIMD3<Float>(repeating: appData.modelData.scaleInfo.scale)

        }  else if let rotationInfo = try? JSONDecoder().decode(AppData.RotationInfo.self, from: data) {

            heartEntity?.transform.rotation = rotationInfo.matrix
            heartEntityInner?.transform.rotation = rotationInfo.matrix

            let rot = rotationInfo.rot

            if let heartEntity {
                for child in heartEntity.children {
                    if let child = child as? AnnotationEntity, let initialOffset = child.initialOffset {

                        let rotatedOffset = rot.act(
                            initialOffset
                        )
                        child.transform.translation = heartEntity.transform.translation + rotatedOffset
                    }
                }
            }
        } else if let scaleInfo = try? JSONDecoder().decode(AppData.ScaleInfo.self, from: data) {
            if let heartEntity {
                let scale = scaleInfo.annotationScale

                let heartPosition = heartEntity.position
                for child in heartEntity.children {
                    if let child = child as? AnnotationEntity {
                        let relativePosition = child.position - heartPosition
                        child.position = heartPosition + (relativePosition * scale)
                        child.transform.scale *= SIMD3<Float>(repeating: scale)

                         child.initialOffset = child.transform.translation - heartEntity.transform.translation
                    }
                }
            }

            heartEntity?.transform.scale = SIMD3<Float>(repeating: scaleInfo.scale)
            heartEntityInner?.transform.scale = SIMD3<Float>(repeating: scaleInfo.scale)

        } else if let modelData = try? JSONDecoder().decode(AppData.ModelData.self, from: data) {
            slicingPlane?.position = modelData.planeInfo.planePosition
            slicingPlane?.transform.rotation = modelData.planeInfo.planeRotation.rotationInfo.matrix

            modifyHeartMaterials(newValues: modelData.planeInfo.materialSlice)

            heartEntity?.transform.rotation = modelData.rotationInfo.matrix
            heartEntity?.transform.scale = SIMD3<Float>(repeating: modelData.scaleInfo.scale)

            heartEntityInner?.transform.rotation = modelData.rotationInfo.matrix
            heartEntityInner?.transform.scale = SIMD3<Float>(repeating: modelData.scaleInfo.scale)

        } else if let planeInfo = try? JSONDecoder().decode(AppData.PlaneInfo.self, from: data) {
            slicingPlane?.position = planeInfo.planePosition
            slicingPlane?.transform.rotation = planeInfo.planeRotation.rotationInfo.matrix

            planeEquation = planeInfo.materialSlice

            modifyHeartMaterials(newValues: planeInfo.materialSlice)
        } else if let planeRotationInfo = try? JSONDecoder().decode(AppData.PlaneRotationInfo.self, from: data) {
            slicingPlane?.transform.rotation = planeRotationInfo.rotationInfo.matrix

            let a = planeRotationInfo.rotationInfo
            modifyHeartMaterials(newValues: SIMD4<Float>(a.x, a.y, a.z, a.w))
        } else if let gestureState = try? JSONDecoder().decode(AppData.GestureState.self,
            from: data
        ) {
            if gestureState == .started, let heartEntity {
                for child in heartEntity.children {
                    if let child = child as? AnnotationEntity {
                        child.initialOffset = child.transform.translation - heartEntity.transform.translation
                    }
                }
            }
        }
    }

    func loadSavedState(from appData: AppData) {
        arCoordinator?.updateAppData(using: appData)

        slicingPlane?.position = appData.modelData.planeInfo.planePosition
        slicingPlane?.transform.rotation = appData.modelData.planeInfo.planeRotation.rotationInfo.matrix

        modifyHeartMaterials(newValues: appData.modelData.planeInfo.materialSlice)

        heartEntity?.transform.rotation = appData.modelData.rotationInfo.matrix
        heartEntity?.transform.scale = SIMD3<Float>(repeating: appData.modelData.scaleInfo.scale)

        heartEntityInner?.transform.rotation = appData.modelData.rotationInfo.matrix
        heartEntityInner?.transform.scale = SIMD3<Float>(repeating: appData.modelData.scaleInfo.scale)

        arCoordinator?.sendAppDataToPeers()
    }
    
    
    func modifyHeartMaterials(newValues: SIMD4<Float>) {
        try? self.heartEntity?.modifyMaterials {
            var customMaterial = try CustomMaterial(from: $0, surfaceShader: surfaceShaderOuter!)
            customMaterial.faceCulling = .front
            customMaterial.roughness = CustomMaterial.Roughness(floatLiteral: 1)
            customMaterial.metallic = CustomMaterial.Metallic(floatLiteral: 1)
            customMaterial.custom.value = newValues

            return customMaterial
        }

        try? self.heartEntityInner?.modifyMaterials {
            var customMaterial = try CustomMaterial(from: $0, surfaceShader: surfaceShaderInner!)
            customMaterial.faceCulling = .back
            customMaterial.roughness = CustomMaterial.Roughness(floatLiteral: 1)
            customMaterial.metallic = CustomMaterial.Metallic(floatLiteral: 1)
            customMaterial.custom.value = newValues

            return customMaterial
        }
    }

    func resetSlice() {
        planeEquation = Self.defaultSlice
        lastSavedSlicePlane = SIMD4(0, 0, 0, 0)

        modifyHeartMaterials(newValues: Self.defaultSlice)

        arCoordinator?.updateMaterialSlice(newValue: Self.defaultSlice)
        arCoordinator?.sendPlaneInfoToPeers()
    }

    func resetModel() {
        heartEntity?.transform.rotation = defaultModelOrientation
        heartEntityInner?.transform.rotation = defaultModelOrientation

        heartEntity?.scale = SIMD3(repeating: 0.008)
        heartEntityInner?.scale = SIMD3(repeating: 0.008)

        // TODO: Integrate with Pratham
        arCoordinator?.updateRotationMatrix(newValue: defaultModelOrientation, rot: .init(ix: 0, iy: 0, iz: 0, r: 0))
        arCoordinator?.sendRotationInfoToPeers()
    }

    func toggleHideSlice(shouldSend: Bool = true) -> Bool {
        isSliceHidden.toggle()

        let newSlicePlane = lastSavedSlicePlane

        lastSavedSlicePlane = planeEquation
        planeEquation = newSlicePlane

        modifyHeartMaterials(newValues: newSlicePlane)

        if shouldSend {
            arCoordinator?.updateMaterialSlice(newValue: newSlicePlane)
            arCoordinator?.sendPlaneInfoToPeers()
        }

        return isSliceHidden
    }

    func toggleSliceOrientation() {
        if !isSliceHidden {
            planeEquation = -planeEquation

            modifyHeartMaterials(newValues: planeEquation)

            arCoordinator?.updateMaterialSlice(newValue: planeEquation)
            arCoordinator?.sendPlaneInfoToPeers()
        }
    }

    // MARK: - Gesture Recognizers

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard arCoordinator?.userActionUpdate == nil || arCoordinator?.userActionUpdate?.action == .idle || arCoordinator?.userActionUpdate?.username == arCoordinator?.networkingService?.currentPeer.displayName else {
            return
        }

        if gesture.state == .began {
            arCoordinator?.sendUserActionUpdate(action: .controlling)
        } else if gesture.state == .ended {
            arCoordinator?.sendUserActionUpdate(action: .idle)
        }

        if arCoordinator?.sessionMode == .slice {
            if !isSliceHidden {
                handleSlicePinch(gesture: gesture)
            }
        } else {
            handleModelScale(sender: gesture)
        }
    }


    @objc func handleRotation(sender: UIPanGestureRecognizer) {
        guard arCoordinator?.userActionUpdate == nil || arCoordinator?.userActionUpdate?.action == .idle || arCoordinator?.userActionUpdate?.username == arCoordinator?.networkingService?.currentPeer.displayName else {
            return
        }

        if sender.state == .began {
            arCoordinator?.sendUserActionUpdate(action: .controlling)
        } else if sender.state == .ended {
            arCoordinator?.sendUserActionUpdate(action: .idle)
        }

        if arCoordinator?.sessionMode == .slice {
            if !isSliceHidden {
                handleSliceRotation(sender)
            }
        } else {
            handleModelRotation(sender: sender)
        }
    }

    @objc func handleTwist(sender: UIRotationGestureRecognizer) {
        guard arCoordinator?.userActionUpdate == nil || arCoordinator?.userActionUpdate?.action == .idle || arCoordinator?.userActionUpdate?.username == arCoordinator?.networkingService?.currentPeer.displayName else {
            return
        }

        if sender.state == .began {
            arCoordinator?.sendUserActionUpdate(action: .controlling)
        } else if sender.state == .ended {
            arCoordinator?.sendUserActionUpdate(action: .idle)
        }

        if arCoordinator?.sessionMode == .slice {
            if !isSliceHidden {
                handleSliceTwist(sender)
            }
        } else {
            handleModelTwist(sender: sender)
        }
    }

    private func handleModelScale(sender: UIPinchGestureRecognizer) {
        guard let heartEntity = heartEntity, let heartEntityInner = heartEntityInner else { return }
        if sender.state == .began {
            prevModelScale = sender.scale
        }
        else if sender.state == .changed {
            let scale = Float(sender.scale / prevModelScale)
            prevModelScale = sender.scale

            let newScale = heartEntity.transform.scale * SIMD3<Float>(repeating: scale)
            let newScaleFloat = heartEntity.transform.scale.x * scale

            heartEntity.transform.scale = newScale
            heartEntityInner.transform.scale = newScale

            // Update annotation positions based on the heart's center
            let heartPosition = heartEntity.position
            for child in heartEntity.children {
                if let child = child as? AnnotationEntity {
                    // Get the vector from heart to annotation
                    let relativePosition = child.position - heartPosition
                    // Scale this vector and reposition relative to heart
                    child.position = heartPosition + (relativePosition * scale)
                    child.transform.scale *= SIMD3<Float>(repeating: scale)
                }
            }

            arCoordinator?
                .updateScale(newValue: newScaleFloat, annotationScale: scale)
            arCoordinator?.sendScaleInfoToPeers()
        }
    }

    private func handleSlicePinch(gesture: UIPinchGestureRecognizer) {
        guard let heartEntity = heartEntity, let heartEntityInner = heartEntityInner, let planeEntity = slicingPlane else { return }

        let sensitivity = 5

        if gesture.state == .began {
            prevSlicingScale = gesture.scale
        } else if gesture.state == .changed {
            let pinchScale = gesture.scale
            let newValue = Float(pinchScale - prevSlicingScale) * Float(sensitivity)
            let newRawValue = Float(pinchScale - prevSlicingScale) * 1/Float(sensitivity)

            planeEntity.position.y += newRawValue
            planeEquation.w += newValue

            do {
                try heartEntity.modifyMaterials {
                    var customMaterial = try CustomMaterial(from: $0, surfaceShader: surfaceShaderOuter!)
                    customMaterial.faceCulling = .front
                    customMaterial.custom.value[3] += newValue
                    arCoordinator?.updateMaterialSlice(newValue: customMaterial.custom.value)
                    return customMaterial
                }

                try heartEntityInner.modifyMaterials {
                    var customMaterial = try CustomMaterial(from: $0, surfaceShader: surfaceShaderInner!)
                    customMaterial.faceCulling = .back
                    customMaterial.custom.value[3] += newValue
                    arCoordinator?.updateMaterialSlice(newValue: customMaterial.custom.value)
                    return customMaterial
                }
            } catch {
                print("Error updating material: \(error)")
            }

            // Update prevSlicingScale for the next pinch event
            prevSlicingScale = gesture.scale

            arCoordinator?.updatePlanePosition(newValue: planeEntity.position)
            arCoordinator?.sendPlaneInfoToPeers()
        }
    }

    private func normalize(_ vector: SIMD4<Float>) -> SIMD4<Float>{

        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        guard length != 0 else { return vector }

        return SIMD4<Float>(
            vector.x / length,
            vector.y / length,
            vector.z / length,
            vector.w // Keep the fourth component unchanged
        )
    }

    private func handleSliceRotation(_ sender: UIPanGestureRecognizer) {
        guard let heartEntity = heartEntity, let heartEntityInner = heartEntityInner, let planeEntity = slicingPlane else { return }

        if let currentFrame = session.currentFrame {
            if sender.state == .began {
                initialCameraRotationPlane = simd_quatf(currentFrame.camera.transform)
                initialPlaneRotation = heartEntity.orientation
            }

            let translation = sender.translation(in: self)

            if sender.state == .changed {
                let deviceOrientation = UIDevice.current.orientation

                let newAngleY = Float(prevSliceTranslation.x - translation.x) * Float.pi / 180.0 * 0.2
                let newAngleX = Float(prevSliceTranslation.y - translation.y) * Float.pi / 180.0 * 0.2

                // Modify axis based on device orientation
                var axisX = simd_float3(-1, 0, 0)
                var axisY = simd_float3(0, -1, 0)

                if deviceOrientation == .portrait {
                    axisX = simd_float3(0, -1, 0)
                    axisY = simd_float3(1, 0, 0)
                }

                let x_quat = simd_quatf(angle: newAngleX, axis: self.initialCameraRotationPlane.act(axisX))
                let y_quat = simd_quatf(angle: newAngleY, axis: self.initialCameraRotationPlane.act(axisY))

                let rot = initialPlaneRotation.inverse * x_quat * y_quat * initialPlaneRotation

                planeEquation = rotatePlane(rot)

                modifyHeartMaterials(newValues: planeEquation)

                arCoordinator?.updateMaterialSlice(newValue: planeEquation)
                arCoordinator?.sendPlaneInfoToPeers()

            }
            prevSliceTranslation = translation
        }
    }

    private func handleSliceTwist(_ sender: UIRotationGestureRecognizer) {
        guard let heartEntity = heartEntity, let heartEntityInner = heartEntityInner else { return }

        if let currentFrame = session.currentFrame {

            if sender.state == .began {
                initialCameraRotation = simd_quatf(currentFrame.camera.transform)
                initialObjectRotation = heartEntity.orientation
            }

            if sender.state == .changed {
                let rotation = Float(sender.rotation - prevSliceRotation)
                let axisZ = simd_float3(0, 0, -1)

                let z_quat = simd_quatf(angle: rotation, axis: self.initialCameraRotation.act(axisZ))

                let rot = heartEntity.orientation.inverse * z_quat * heartEntity.orientation

                planeEquation = rotatePlane(rot)

                modifyHeartMaterials(newValues: planeEquation)

                arCoordinator?.updateMaterialSlice(newValue: planeEquation)
                arCoordinator?.sendPlaneInfoToPeers()

            }

            prevSliceRotation = sender.rotation
        }
    }

    private func rotatePlane(_ rot: simd_quatf) -> SIMD4<Float>{

        let rot3x3 = matrix_float3x3(rot)
        var rot4x4 = matrix_float4x4()

        rot4x4.columns.0 = SIMD4<Float>(rot3x3.columns.0, 0)
        rot4x4.columns.1 = SIMD4<Float>(rot3x3.columns.1, 0)
        rot4x4.columns.2 = SIMD4<Float>(rot3x3.columns.2, 0)
        rot4x4.columns.3 = SIMD4<Float>(0,0,0,1)

        let rot_plane = rot4x4 * planeEquation

        print("rot4x4: " + rot4x4.debugDescription)

        let newPlaneEquation = SIMD4<Float>(rot_plane.x, rot_plane.y, rot_plane.z, rot_plane.w)

        return newPlaneEquation
    }

    private func handleModelRotation(sender: UIPanGestureRecognizer) {
        guard let heartEntity = heartEntity, let heartEntityInner = heartEntityInner else { return }

        if let currentFrame = session.currentFrame {
            if sender.state == .began {
                initialCameraRotation = simd_quatf(currentFrame.camera.transform)
                initialObjectRotation = heartEntity.orientation

                // Store initial offsets
                for child in heartEntity.children {
                    if let child = child as? AnnotationEntity {
                        child.initialOffset = child.transform.translation - heartEntity.transform.translation
                    }
                }

                let update = AppData.GestureState.started
                if let data = try? JSONEncoder().encode(update) {
                    arCoordinator?.networkingService?.sendToAllPeers(data, reliably: true)
                }
            }

            if sender.state == .changed {
                let translation = sender.translation(in: self)
                let deviceOrientation = UIDevice.current.orientation
                let newAngleY = Float(translation.x) * Float.pi / 180.0
                let newAngleX = Float(translation.y) * Float.pi / 180.0

                // Modify axis based on device orientation
                var axisX = simd_float3(1, 0, 0)
                var axisY = simd_float3(0, 1, 0)
                if deviceOrientation == .portraitUpsideDown {
                    axisX = simd_float3(0, -1, 0)
                    axisY = simd_float3(1, 0, 0)
                } else if deviceOrientation == .portrait {
                    axisX = simd_float3(0, 1, 0)
                    axisY = simd_float3(-1, 0, 0)
                }

                let x_quat = simd_quatf(angle: newAngleX, axis: self.initialCameraRotation.act(axisX))
                let y_quat = simd_quatf(angle: newAngleY, axis: self.initialCameraRotation.act(axisY))

                let rot = x_quat * y_quat
                let matrix = rot * (self.initialObjectRotation).normalized

                heartEntity.transform.rotation = matrix
                heartEntityInner.transform.rotation = matrix

                for child in heartEntity.children {
                    if let child = child as? AnnotationEntity, let initialOffset = child.initialOffset {
                        let rotatedOffset = rot.act(initialOffset)  // Rotate only from initial offset
                        child.transform.translation = heartEntity.transform.translation + rotatedOffset
                    }
                }


                arCoordinator?.updateRotationMatrix(newValue: matrix, rot: rot)
                arCoordinator?.sendRotationInfoToPeers()
            }
        }
    }

    private func handleModelTwist(sender: UIRotationGestureRecognizer) {
        guard let heartEntity = heartEntity, let heartEntityInner = heartEntityInner else { return }

        if let currentFrame = session.currentFrame {

            if sender.state == .began {
                initialCameraRotation = simd_quatf(currentFrame.camera.transform)
                initialObjectRotation = heartEntity.orientation

                // Store initial offsets
                for child in heartEntity.children {
                    if let child = child as? AnnotationEntity {
                        child.initialOffset = child.transform.translation - heartEntity.transform.translation
                    }
                }
            }

            if sender.state == .changed {
                let rotation = Float(sender.rotation)
                let axisZ = simd_float3(0, 0, -1)

                let z_quat = simd_quatf(angle: rotation, axis: self.initialCameraRotation.act(axisZ))

                let matrix = z_quat * (self.initialObjectRotation).normalized

                heartEntity.transform.rotation = matrix
                heartEntityInner.transform.rotation = matrix

                for child in heartEntity.children {
                    if let child = child as? AnnotationEntity, let initialOffset = child.initialOffset {
                        let rotatedOffset = z_quat.act(
                            initialOffset
                        )  // Rotate only from initial offset
                        child.transform.translation = heartEntity.transform.translation + rotatedOffset
                    }
                }

                arCoordinator?
                    .updateRotationMatrix(newValue: matrix, rot: z_quat)
                arCoordinator?.sendRotationInfoToPeers()

            }
        }
    }
}

extension RealityView: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let anchor = anchor as? HeartAnchor {
                print("Received HeartAnchor")
                placeEntity(using: anchor)
            }
            if let participantAnchor = anchor as? ARParticipantAnchor {
                arCoordinator?.updateShowSuccessConnectionMessage(true)
                let anchorEntity = AnchorEntity(anchor: participantAnchor)

                let coloredSphere = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.03),
                                                materials: [SimpleMaterial(color: .black, isMetallic: true)])
                anchorEntity.addChild(coloredSphere)

                self.scene.addAnchor(anchorEntity)
            }

        }
    }

//    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
////        print("update?????")
//    }

    // MARK: - Collaborative Session Methods
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        guard let coordinator = arCoordinator, let networkingService = coordinator.networkingService,
             !coordinator.connectedPeers.isEmpty else { return }

       do {
           let dataForPeers = try NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
//           print("COLLAB DATA: ", dataForPeers.count)
           // Send to peers based on data priority
           multipeerSession?.sendToAllPeers(
               dataForPeers,
               reliably: data.priority == .critical
           )
       } catch {
           print("Error archiving collaboration data: \(error)")
       }
    }
}

extension RealityView: ARMultipeerSessionDelegate {
    func didReceiveData(_ data: Data, from id: MCPeerID) {
        self.receivedData(data, from: id)
    }

    func peerDidChangeState(_ peer: MCPeerID, to newState: MCSessionState) {
//        print("\(peer) changed state to \(newState)")
    }

    func didFindPeer(_ peer: MCPeerID) {
        multipeerSession?.invitePeer(peer)
    }

    func didLosePeer(_ peer: MCPeerID) {

    }
}
