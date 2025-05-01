//
//  DevicesList.swift
//  CollabTest
//
//  Created by Rahul on 3/13/24.
//

import SwiftUI
import MultipeerConnectivity

struct DevicesList: View {
    @EnvironmentObject private var arCoordinator: ARCoordinator

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Connected Devices")
                    .foregroundStyle(.black)
                    .font(.title)
                    .bold()

                Spacer()
            }

            ScrollView {
                VStack(alignment: .center) {
                    ForEach(arCoordinator.connectedDevices, id: \.self) { peer in
                        rowCell(for: peer)
                    }

                    Spacer()

                    ProgressView {
                        Text("Looking for devices...")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Spacer()
                }
            }
        }
        .frame(maxHeight: 400)
        .padding()
        .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
        .padding()
    }

    private func rowCell(for peer: String) -> some View {
        Group {
            if let arPeer = arCoordinator.connectedPeers.first(
                where: { $0.displayName == peer }) {
                DeviceListRow(peer: arPeer)
            } else {
                Text(peer)
            }
        }
    }
}

private struct DeviceListRow: View {
    @EnvironmentObject private var arCoordinator: ARCoordinator
    @StateObject private var profileImage: PeerProfileImage
    let peer: ARCoordinator.P

    init(peer: ARCoordinator.P) {
        self.peer = peer
        _profileImage = StateObject(wrappedValue: PeerProfileImage(peer: peer))
    }

    var body: some View {
        Button {
            arCoordinator.requestConnection(with: peer.displayName)
        } label: {
            HStack {
                (profileImage.image ?? Image(systemName: "person.circle.fill"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .foregroundColor(.gray)

                Text(isThisDevice ? "You" : peer.displayName)
                    .font(.headline)
                Spacer()
                Group {
                    if isThisDevice {
                        EmptyView()
                    } else if isConnected {
                        Text("Connected")
                    }
                }
                .foregroundStyle(.secondary)
                .bold()
            }
            .padding()
            .background(.tertiary, in: .rect(cornerRadius: 6))
            .tint(
                isThisDevice ? .accentColor : .green
            )
        }
    }

    private var isThisDevice: Bool {
        isConnected && (peer.displayName == arCoordinator.networkingService?.currentPeer.displayName)
    }

    private var isConnected: Bool {
        arCoordinator.connectedTo(peer.displayName)
    }
}

#Preview {
    DevicesList()
        .environmentObject(ARCoordinator())
}
