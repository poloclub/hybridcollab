import SwiftUI
import GameKit
import MultipeerConnectivity

class PeerProfileImage: ObservableObject {
    @Published private(set) var image: Image?
    private static var imageCache: [String: Image] = [:]

    init(peer: GKPlayer) {
        loadImage(for: peer)
    }

    init(peer: MCPeerID) {
        image = Image(systemName: "person.circle.fill")
    }

    private func loadImage(for player: GKPlayer) {
        if let cachedImage = Self.imageCache[player.gamePlayerID] {
            self.image = cachedImage
            return
        }

        player.loadPhoto(for: .normal) { [weak self] image, error in
            DispatchQueue.main.async {
                if let image = image {
                    let swiftUIImage = Image(uiImage: image)
                    Self.imageCache[player.gamePlayerID] = swiftUIImage
                    self?.image = swiftUIImage
                } else {
                    self?.image = Image(systemName: "person.circle.fill")
                }
            }
        }
    }
}
