//
//  NetworkingDelegate.swift
//  ARCollab
//
//  Created by Rahul on 2/7/25.
//

import Foundation
import MultipeerConnectivity
import GameKit

protocol PeerIdentifiable: Hashable {
    var displayName: String { get }
}

extension MCPeerID: PeerIdentifiable {}

extension GKPlayer: PeerIdentifiable {}

protocol NetworkingDelegate<P>: AnyObject {
    associatedtype P: PeerIdentifiable
    func didReceiveData(_ data: Data, from peer: P)
    func peerDidChangeState(_ peer: P, isConnected: Bool)
    func didFindPeer(_ peer: P)
    func didLosePeer(_ peer: P)
}

protocol NetworkingProtocol<P> {
    associatedtype P: PeerIdentifiable
    var delegate: (any NetworkingDelegate<P>)? { get set }
    var currentPeer: P { get }
    var supportsSharePlay: Bool { get }

    func initialize(with name: String, onCompletion: @escaping () -> Void)
    func sendToAllPeers(_ data: Data, reliably: Bool)
    func invitePeer(_ peer: P)
    func startShareplayActivity()
}

extension MultipeerNetworkingService {
    var supportsSharePlay: Bool { false }

    func startShareplayActivity() {
        fatalError("Multipeer networking does not support shareplay.")
    }
}

extension GameKitNetworkingService {
    var supportsSharePlay: Bool { true }
}
