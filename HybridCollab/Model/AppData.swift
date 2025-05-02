//
//  AppData.swift
//  CollabTest
//
//  Created by Rahul on 3/13/24.
//

import Foundation
import ARKit

struct AppData: Codable {
    enum AppState: Int, CaseIterable, Codable {
        case connectingToDevices = 0
        case arSession
    }

    struct RotationInfo: Codable {
        var x: Float
        var y: Float
        var z: Float
        var w: Float
        var rotx: Float
        var roty: Float
        var rotz: Float
        var rotw: Float

        init(matrix: simd_quatf, rot: simd_quatf) {
            x = matrix.imag.x
            y = matrix.imag.y
            z = matrix.imag.z
            w = matrix.real

            rotx = rot.imag.x
            roty = rot.imag.y
            rotz = rot.imag.z
            rotw = rot.real
        }

        var matrix: simd_quatf {
            simd_quatf(ix: x, iy: y, iz: z, r: w)
        }

        var rot: simd_quatf {
            simd_quatf(ix: rotx, iy: roty, iz: rotz, r: rotw)
        }
    }
    
    struct PlaneRotationInfo: Codable {
        var rotationInfo: RotationInfo = RotationInfo(matrix: .init(ix: 0, iy: 1, iz: 0, r: 0), rot: .init(ix: 0, iy: 1, iz: 0, r: 0))

        init(matrix: simd_quatf) {
            self.rotationInfo.x = matrix.imag.x
            self.rotationInfo.y = matrix.imag.y
            self.rotationInfo.z = matrix.imag.z
            self.rotationInfo.w = matrix.real
        }
    }
    
    struct ScaleInfo: Codable {
        var scale: Float
        var annotationScale: Float

        init(scale: Float, annotationScale: Float) {
            self.scale = scale
            self.annotationScale = annotationScale
        }
    }

    struct PlaneInfo: Codable {
        var planePosition: SIMD3<Float> = SIMD3(repeating: 0.0)
        var planeRotation: PlaneRotationInfo = PlaneRotationInfo(matrix: .init(ix: 0, iy: 1, iz: 0, r: 0))
        var materialSlice: SIMD4<Float> = RealityView.defaultSlice
    }

    struct ModelData: Codable {
        var scaleInfo: ScaleInfo = ScaleInfo(scale: 0.008, annotationScale: 0.0)
        var planeInfo = PlaneInfo()
        var rotationInfo: RotationInfo = RotationInfo(matrix: simd_quatf(vector: [0, 0, 0, 0]), rot: simd_quatf(vector: [0, 0, 0, 0]))
        var annotations = AnnotationTranslationData(matrix: simd_quatf(vector: [0, 0, 0, 0]))
    }

    struct AnnotationTranslationData: Codable {
        var x: Float
        var y: Float
        var z: Float
        var w: Float
        var otherVarUnused = ""

        init(matrix: simd_quatf) {
            x = matrix.imag.x
            y = matrix.imag.y
            z = matrix.imag.z
            w = matrix.real
        }

        var matrix: simd_quatf {
            simd_quatf(ix: x, iy: y, iz: z, r: w)
        }
    }

    enum GestureState: Codable {
        case started
        case inProgress
        case ended
    }

    var currentState: AppState = .connectingToDevices
    var modelData = ModelData()

    mutating func updateState(using other: AppData) {
        self.currentState = other.currentState
        self.modelData = other.modelData
    }
}
