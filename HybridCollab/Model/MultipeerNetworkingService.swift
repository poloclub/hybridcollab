//
//  MultipeerNetworkingService.swift
//  ARCollab
//
//  Created by Rahul on 2/7/25.
//

import Foundation
import MultipeerConnectivity

class MultipeerNetworkingService: NSObject, NetworkingProtocol {
    typealias P = MCPeerID

    weak var delegate: (any NetworkingDelegate<P>)?
    private var multipeerSession: MultipeerSession?

    var currentPeer: P {
        multipeerSession?.session.myPeerID ?? MCPeerID(displayName: "")
    }

    func initialize(with name: String, onCompletion: () -> Void = {}) {
        multipeerSession = MultipeerSession(name: name)
         multipeerSession?.arMultipeerSessionDelegate = self
    }

    func sendToAllPeers(_ data: Data, reliably: Bool) {
        multipeerSession?.sendToAllPeers(data, reliably: reliably)
    }

    func invitePeer(_ peer: P) {
        guard let _ = multipeerSession?.session,
              let peerID = peer as? MCPeerID else { return }

        multipeerSession?.invitePeer(peerID)
    }
}

extension MultipeerNetworkingService: ARMultipeerSessionDelegate {
    func didReceiveData(_ data: Data, from id: MCPeerID) {
        delegate?.didReceiveData(data, from: id)
    }

    func peerDidChangeState(_ peer: MCPeerID, to newState: MCSessionState) {
        delegate?.peerDidChangeState(peer, isConnected: newState == .connected)
    }

    func didFindPeer(_ peer: MCPeerID) {
        delegate?.didFindPeer(peer)
    }

    func didLosePeer(_ peer: MCPeerID) {
        delegate?.didLosePeer(peer)
    }
}
