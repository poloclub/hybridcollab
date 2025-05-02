//
//  HeartAnchor.swift
//  CollabTest
//
//  Created by Rahul on 3/14/24.
//

import ARKit

class HeartAnchor: ARAnchor {
    override init(transform: simd_float4x4) {
        super.init(transform: transform)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
    }

    override class var supportsSecureCoding: Bool {
        true
    }

    required init(anchor: ARAnchor) {
        super.init(anchor: anchor)
    }
}

