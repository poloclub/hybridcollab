//
//  GameKitNetworkingService.swift
//  ARCollab
//

import Foundation
import GameKit

class GameKitNetworkingService: NSObject, NetworkingProtocol {
    typealias P = GKPlayer
    
    weak var delegate: (any NetworkingDelegate<P>)?
    private var match: GKMatch?
    private var localPlayer: GKLocalPlayer

    private let matchMaker = GKMatchmaker.shared()

    var currentPeer: P {
        localPlayer
    }
    
    override init() {
        self.localPlayer = GKLocalPlayer.local
        super.init()
    }
    
    func initialize(with name: String, onCompletion: @escaping () -> Void = {}) {
        authenticatePlayer(onCompletion: onCompletion)
    }
    
    func sendToAllPeers(_ data: Data, reliably: Bool) {
        do {
            print("Sending from \(currentPeer.displayName)")
            try match?.sendData(toAllPlayers: data,
                               with: reliably ? .reliable : .unreliable)
        } catch {
            print("Error sending data to peers: \(error)")
        }
    }
    
    func invitePeer(_: P) {
        let request = GKMatchRequest()
        request.maxPlayers = 4

        matchMaker.findMatch(for: request) { [weak self] match, error in
            if let match = match {
                print("Found match: \(match.description)")
                self?.match = match
                self?.match?.delegate = self

                // Notify about connected players
                for player in match.players {
                    self?.delegate?.didFindPeer(player)
                    self?.delegate?.peerDidChangeState(player, isConnected: true)
                }

                self?.matchMaker.finishMatchmaking(for: match)
            } else if let error {
                print("Error: ", error.localizedDescription)
            }
        }
    }
    
    private func authenticatePlayer(onCompletion: @escaping () -> Void = {}) {
        localPlayer.authenticateHandler = { viewController, error in
            if let viewController = viewController {
                UIViewController.rootViewController?
                    .present(viewController, animated: true)
            }

            if let error = error {
                print("Error authenticating: \(error.localizedDescription)")
                return
            }

            GKLocalPlayer.local.register(self) // real-time requests

            self.invitePeer(.init())

            onCompletion()

//            GKAccessPoint.shared.location = .topLeading
//            GKAccessPoint.shared.showHighlights = true
//            GKAccessPoint.shared.isActive = true

            // self.authenticationComplete = true
        }
    }

    func startShareplayActivity() {
        matchMaker.startGroupActivity { [weak self] player in
            self?.delegate?.didFindPeer(player)
            self?.delegate?.peerDidChangeState(player, isConnected: true)
        }
    }
}

extension GameKitNetworkingService: GKMatchDelegate {
    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        delegate?.didReceiveData(data, from: player)
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        switch state {
        case .connected:
            delegate?.peerDidChangeState(player, isConnected: true)
        case .disconnected:
            delegate?.peerDidChangeState(player, isConnected: false)
        default:
            break
        }
    }
    
    func match(_ match: GKMatch, didFind player: GKPlayer) {
        delegate?.didFindPeer(player)
    }
    
    func match(_ match: GKMatch, didLose player: GKPlayer) {
        delegate?.didLosePeer(player)
    }
}

extension GameKitNetworkingService: GKMatchmakerViewControllerDelegate {
    func matchmakerViewControllerWasCancelled(
        _ viewController: GKMatchmakerViewController
    ) {
        viewController.dismiss(animated: true) {}
    }

    func matchmakerViewController(
        _ viewController: GKMatchmakerViewController,
        didFailWithError error: any Error
    ) {
        viewController.dismiss(animated: true) {}
    }

    func matchmakerViewController(
        _ viewController: GKMatchmakerViewController,
        didFind match: GKMatch
    ) {
        viewController.dismiss(animated: true) {}

        // GKAccessPoint.shared.isActive = false
        self.match = match
        self.match?.delegate = self

        for player in match.players {
            delegate?.didFindPeer(player)
            delegate?.peerDidChangeState(player, isConnected: true)
        }
    }
}

extension GameKitNetworkingService: GKLocalPlayerListener { }
