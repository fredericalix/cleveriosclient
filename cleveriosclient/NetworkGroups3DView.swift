import SwiftUI
import SceneKit
import Combine

// MARK: - NetworkGroups3DView
/// Revolutionary 3D visualization of network topology using SceneKit
struct NetworkGroups3DView: View {
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    
    // MARK: - Properties
    let organizationId: String
    
    // MARK: - State
    @State private var networkGroups: [CCNetworkGroup] = []
    @State private var selectedNetworkGroup: CCNetworkGroup?
    @State private var members: [CCNetworkGroupMember] = []
    @State private var peers: [CCNetworkGroupPeer] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @State private var scene = SCNScene()
    @State private var cameraNode = SCNNode()
    @State private var selectedNodeName: String?
    @State private var selectedNodeDetails: NodeDetails?
    @State private var rotationAngle: Float = 0
    @State private var isAutoRotating = true
    @State private var zoomLevel: Float = 30
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Node Details Structure
    struct NodeDetails {
        var name: String
        var type: String
        var description: String
        var additionalInfo: [String: String]
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Network Groups List (Top Section)
                networkGroupsList
                    .frame(height: 120)
                    .background(Color(.systemGroupedBackground))
                
                Divider()
                
                if let selectedGroup = selectedNetworkGroup {
                    // 3D Visualization (Middle Section)
                    SceneKitView(
                        scene: scene,
                        pointOfView: cameraNode,
                        onNodeTapped: handleNodeSelection
                    )
                    .background(
                        LinearGradient(
                            colors: [Color.black, Color.purple.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .topTrailing) {
                        controlsOverlay
                    }
                    .overlay(alignment: .bottom) {
                        if let details = selectedNodeDetails {
                            nodeDetailsView(details: details)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .onAppear {
                        loadNetworkGroupDetails(for: selectedGroup)
                    }
                } else {
                    // Empty State
                    ContentUnavailableView(
                        "Select a Network Group",
                        systemImage: "network",
                        description: Text("Choose a network group from the list above to visualize its topology")
                    )
                }
            }
            .navigationTitle("3D Network Topology")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadNetworkGroups()
        }
    }
    
    // MARK: - Network Groups List
    private var networkGroupsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network Groups")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(networkGroups) { group in
                        NetworkGroupCard(
                            group: group,
                            isSelected: selectedNetworkGroup?.id == group.id
                        ) {
                            withAnimation(.spring()) {
                                selectedNetworkGroup = group
                                selectedNodeDetails = nil
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - Network Group Card
    struct NetworkGroupCard: View {
        let group: CCNetworkGroup
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .medium)
                        .lineLimit(1)
                    
                    if let description = group.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minWidth: 150)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )
                )
                .foregroundColor(isSelected ? .white : .primary)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Node Details View
    private func nodeDetailsView(details: NodeDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.name)
                        .font(.headline)
                    Text(details.type)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        selectedNodeDetails = nil
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
            
            Text(details.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !details.additionalInfo.isEmpty {
                Divider()
                
                ForEach(Array(details.additionalInfo.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(details.additionalInfo[key] ?? "")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10)
        )
        .padding()
        .frame(maxHeight: 200)
    }
    
    // MARK: - Controls Overlay
    private var controlsOverlay: some View {
        VStack(spacing: 16) {
            // Auto-rotate toggle
            Button(action: {
                isAutoRotating.toggle()
                if isAutoRotating {
                    startAutoRotation()
                }
            }) {
                Image(systemName: isAutoRotating ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 44, height: 44)
                    )
            }
            
            // Zoom control
            VStack(spacing: 8) {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.white)
                
                Slider(value: $zoomLevel, in: 10...50)
                    .frame(width: 100)
                    .tint(.white)
                    .onChange(of: zoomLevel) { _, newValue in
                        updateCameraPosition()
                    }
                
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.white)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
        .padding()
    }
    
    // MARK: - Network Groups Loading
    private func loadNetworkGroups() {
        Task { @MainActor in
            do {
                let publisher = coordinator.cleverCloudSDK.getNetworkGroups(for: organizationId)
                
                for try await groups in publisher.values {
                    networkGroups = groups
                    
                    // Auto-select first group if available
                    if let firstGroup = groups.first {
                        selectedNetworkGroup = firstGroup
                    }
                    
                    isLoading = false
                    break // Only need the first value
                }
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    // MARK: - Network Group Details Loading
    private func loadNetworkGroupDetails(for group: CCNetworkGroup) {
        Task { @MainActor in
            do {
                let publisher = coordinator.cleverCloudSDK.getCompleteNetworkGroupData(
                    organizationId: organizationId,
                    networkGroupId: group.id
                )
                
                for try await (_, newMembers, newPeers) in publisher.values {
                    members = newMembers
                    peers = newPeers
                    
                    // Setup 3D scene
                    setupScene()
                    
                    // Start auto-rotation
                    if isAutoRotating {
                        startAutoRotation()
                    }
                    
                    break // Only need the first value
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Scene Setup
    private func setupScene() {
        // Clear existing scene
        scene = SCNScene()
        
        // Setup camera
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 5, z: 30)
        cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(cameraNode)
        
        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)
        
        // Create network group center node
        let centerNode = createNode(
            name: selectedNetworkGroup?.name ?? "Network Group",
            color: .blue,
            position: SCNVector3(0, 0, 0),
            size: 2.0,
            type: "center"
        )
        scene.rootNode.addChildNode(centerNode)
        
        // Add pulsing animation to center
        let pulseAnimation = CABasicAnimation(keyPath: "scale")
        pulseAnimation.fromValue = SCNVector3(1, 1, 1)
        pulseAnimation.toValue = SCNVector3(1.1, 1.1, 1.1)
        pulseAnimation.duration = 1.0
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        centerNode.addAnimation(pulseAnimation, forKey: "pulse")
        
        // Calculate positions for members and peers
        let totalNodes = members.count + peers.count
        let angleStep = (2 * Float.pi) / Float(max(totalNodes, 1))
        var currentAngle: Float = 0
        let radius: Float = 10
        
        // Add member nodes (applications and add-ons)
        for member in members {
            let x = radius * cos(currentAngle)
            let z = radius * sin(currentAngle)
            let position = SCNVector3(x: x, y: 0, z: z)
            
            let color: UIColor = member.type == .application ? .systemBlue : .systemGreen
            let node = createNode(
                name: member.name,
                color: color,
                position: position,
                size: 1.5,
                type: member.type.rawValue.lowercased()
            )
            scene.rootNode.addChildNode(node)
            
            // Create connection line
            let line = createLine(from: SCNVector3(0, 0, 0), to: position, color: color.withAlphaComponent(0.5))
            scene.rootNode.addChildNode(line)
            
            currentAngle += angleStep
        }
        
        // Add peer nodes
        for peer in peers {
            let x = radius * cos(currentAngle)
            let z = radius * sin(currentAngle)
            let position = SCNVector3(x: x, y: 0, z: z)
            
            let color: UIColor = peer.type == "external" ? .systemRed : .systemOrange
            let node = createNode(
                name: peer.name,
                color: color,
                position: position,
                size: 1.5,
                type: "peer"
            )
            scene.rootNode.addChildNode(node)
            
            // Create connection line
            let line = createLine(from: SCNVector3(0, 0, 0), to: position, color: color.withAlphaComponent(0.5))
            scene.rootNode.addChildNode(line)
            
            currentAngle += angleStep
        }
        
        // Add particle system for network activity
        let particleSystem = createNetworkParticles()
        centerNode.addParticleSystem(particleSystem)
    }
    
    // MARK: - Create Node
    private func createNode(name: String, color: UIColor, position: SCNVector3, size: CGFloat, type: String) -> SCNNode {
        let geometry = SCNSphere(radius: size)
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.emission.contents = color.withAlphaComponent(0.3)
        geometry.firstMaterial?.emission.intensity = 0.5
        
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.name = "\(type):\(name)"
        
        // Add tap gesture handling
        node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        node.physicsBody?.categoryBitMask = 1
        
        return node
    }
    
    // MARK: - Create Line
    private func createLine(from: SCNVector3, to: SCNVector3, color: UIColor) -> SCNNode {
        let vector = SCNVector3(to.x - from.x, to.y - from.y, to.z - from.z)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        let midPoint = SCNVector3((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2)
        
        let cylinder = SCNCylinder(radius: 0.1, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = color
        cylinder.firstMaterial?.emission.contents = color
        cylinder.firstMaterial?.emission.intensity = 0.3
        
        let lineNode = SCNNode(geometry: cylinder)
        lineNode.position = midPoint
        lineNode.look(at: to, up: scene.rootNode.worldUp, localFront: lineNode.worldUp)
        
        return lineNode
    }
    
    // MARK: - Network Particles
    private func createNetworkParticles() -> SCNParticleSystem {
        let particleSystem = SCNParticleSystem()
        particleSystem.loops = true
        particleSystem.birthRate = 2
        particleSystem.emissionDuration = 0
        particleSystem.emitterShape = SCNSphere(radius: 2.5)
        particleSystem.particleLifeSpan = 3
        particleSystem.particleSize = 0.3
        particleSystem.particleColor = UIColor.cyan
        particleSystem.particleColorVariation = SCNVector4(0, 0, 0.5, 0)
        particleSystem.spreadingAngle = 180
        particleSystem.particleVelocity = 2
        particleSystem.particleVelocityVariation = 1
        
        return particleSystem
    }
    
    // MARK: - Camera Controls
    private func updateCameraPosition() {
        let x = zoomLevel * cos(rotationAngle)
        let z = zoomLevel * sin(rotationAngle)
        cameraNode.position = SCNVector3(x: x, y: 5, z: z)
        cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }
    
    private func startAutoRotation() {
        guard isAutoRotating else { return }
        
        Task { @MainActor in
            while isAutoRotating {
                rotationAngle += 0.01
                let x = zoomLevel * cos(rotationAngle)
                let z = zoomLevel * sin(rotationAngle)
                
                cameraNode.position = SCNVector3(x: x, y: 5, z: z)
                cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
                
                // Wait for ~16ms (60 FPS)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
}

// MARK: - SceneView with Touch Handling
struct SceneKitView: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode?
    let onNodeTapped: (String, String) -> Void
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.pointOfView = pointOfView
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .clear
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
        uiView.pointOfView = pointOfView
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: SceneKitView
        
        init(_ parent: SceneKitView) {
            self.parent = parent
        }
        
        @MainActor
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            let hitResults = scnView.hitTest(location, options: [:])
            
            if let hit = hitResults.first,
               let nodeName = hit.node.name {
                // Extract node details from name
                let components = nodeName.split(separator: ":").map(String.init)
                if components.count == 2 {
                    let type = components[0]
                    let name = components[1]
                    
                    // Call the parent's callback
                    parent.onNodeTapped(type, name)
                }
            }
        }
    }
}

// MARK: - Extensions for NetworkGroups3DView
extension NetworkGroups3DView {
    func handleNodeSelection(type: String, name: String) {
        withAnimation(.spring()) {
            // Create node details based on type and name
            var details = NodeDetails(
                name: name,
                type: type.capitalized,
                description: "",
                additionalInfo: [:]
            )
            
            switch type {
            case "center":
                if let group = selectedNetworkGroup {
                    details.description = group.description ?? "Network Group"
                    details.additionalInfo = [
                        "ID": group.id,
                        "Created": formatDate(group.createdAt),
                        "Members": "\(members.count)",
                        "Peers": "\(peers.count)"
                    ]
                }
                
            case "application", "addon":
                if let member = members.first(where: { $0.name == name }) {
                    details.description = member.type == .application ? "Application member" : "Add-on member"
                    details.additionalInfo = [
                        "Type": member.type.displayName,
                        "ID": member.resourceId,
                        "IP Address": member.ipAddress ?? "N/A",
                        "Status": member.status ?? "Unknown"
                    ]
                }
                
            case "peer":
                if let peer = peers.first(where: { $0.name == name }) {
                    details.description = peer.type == "external" ? "External peer" : "Internal peer"
                    details.additionalInfo = [
                        "Public Key": String(peer.publicKey?.prefix(20) ?? "") + "...",
                        "Endpoint": peer.endpoint ?? "Dynamic",
                        "Status": peer.status ?? "Unknown"
                    ]
                }
                
            default:
                details.description = "Unknown node type"
            }
            
            selectedNodeDetails = details
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "N/A" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
} 