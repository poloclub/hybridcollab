//
//  AnnotationEntity.swift
//  ARCollab
//
//  Created by Pratham Mehta on 10/04/25.
//

import RealityKit

class AnnotationEntity: Entity, HasAnchoring, Codable {
    static let defaultRadius: Float = 0.005

    var initialOffset: SIMD3<Float>?

    init(world position: SIMD3<Float>) {
        super.init()

        let sphereMesh = MeshResource.generateSphere(radius: Self.defaultRadius)
        let material = SimpleMaterial(color: .blue, isMetallic: false)
        let annotation = ModelEntity(mesh: sphereMesh, materials: [material])

        // Attach anchor at tap position
        self.addChild(annotation)
        self.position = position
    }
    
    @MainActor required init() {
        super.init()
    }
}
