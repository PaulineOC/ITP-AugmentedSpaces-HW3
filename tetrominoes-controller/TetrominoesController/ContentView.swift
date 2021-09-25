//
//  ContentView.swift
//  TetrominoesController
//
//  Created by Nien Lam on 9/21/21.
//  Copyright © 2021 Line Break, LLC. All rights reserved.
//

import SwiftUI
import ARKit
import RealityKit
import Combine


// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    let uiSignal = PassthroughSubject<UISignal, Never>()
    
    @Published var positionLocked = false
    
    enum UISignal {
        case straightSelected
        case squareSelected
        case tSelected
        case lSelected
        case skewSelected

        case moveLeft
        case moveRight

        case rotateCCW
        case rotateCW

        case lockPosition
    }
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)
            
            // Left / Right controls.
            HStack {
                HStack {
                    Button {
                        viewModel.uiSignal.send(.moveLeft)
                    } label: {
                        buttonIcon("arrow.left", color: .blue)
                    }
                }

                HStack {
                    Button {
                        viewModel.uiSignal.send(.moveRight)
                    } label: {
                        buttonIcon("arrow.right", color: .blue)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 30)


            // Rotation controls.
            HStack {
                HStack {
                    Button {
                        viewModel.uiSignal.send(.rotateCCW)
                    } label: {
                        buttonIcon("rotate.left", color: .red)
                    }
                }

                HStack {
                    Button {
                        viewModel.uiSignal.send(.rotateCW)
                    } label: {
                        buttonIcon("rotate.right", color: .red)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.horizontal, 30)

            // Lock release button.
            Button {
                viewModel.uiSignal.send(.lockPosition)
            } label: {
                Label("Lock Position", systemImage: "target")
                    .font(.system(.title))
                    .foregroundColor(.white)
                    .labelStyle(IconOnlyLabelStyle())
                    .frame(width: 44, height: 44)
                    .opacity(viewModel.positionLocked ? 0.25 : 1.0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.bottom, 30)


            // Bottom buttons.
            HStack {
                Button {
                    viewModel.uiSignal.send(.straightSelected)
                } label: {
                    tetrominoIcon("straight", color: Color(red: 0, green: 1, blue: 1))
                }
                
                Button {
                    viewModel.uiSignal.send(.squareSelected)
                } label: {
                    tetrominoIcon("square", color: .yellow)
                }
                
                Button {
                    viewModel.uiSignal.send(.tSelected)
                } label: {
                    tetrominoIcon("t", color: .purple)
                }
                
                Button {
                    viewModel.uiSignal.send(.lSelected)
                } label: {
                    tetrominoIcon("l", color: .orange)
                }
                
                Button {
                    viewModel.uiSignal.send(.skewSelected)
                } label: {
                    tetrominoIcon("skew", color: .green)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 30)
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
    
    // Helper methods for rendering icons.
    
    func tetrominoIcon(_ image: String, color: Color) -> some View {
        Image(image)
            .resizable()
            .padding(3)
            .frame(width: 44, height: 44)
            .background(color)
            .cornerRadius(5)
    }

    func buttonIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .resizable()
            .padding(10)
            .frame(width: 44, height: 44)
            .foregroundColor(.white)
            .background(color)
            .cornerRadius(5)
    }
}


// MARK: - AR View.
struct ARViewContainer: UIViewRepresentable {
    let viewModel: ViewModel
    
    func makeUIView(context: Context) -> ARView {
        SimpleARView(frame: .zero, viewModel: viewModel)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class SimpleARView: ARView {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var originAnchor: AnchorEntity!
    var subscriptions = Set<AnyCancellable>()
    
    // Empty entity for cursor.
    var cursor: Entity!
    
    // Scene lights.
    var directionalLight: DirectionalLight!
    

    // Reference to entity pieces.
    // This needs to be set in the setup.
    var straightPiece: TetrominoEntity!
    var squarePiece: TetrominoEntity!
    var tPiece: TetrominoEntity!
    var lPiece: TetrominoEntity!
    var skewPiece: TetrominoEntity!
    
    // The selected tetromino.
    var activeTetromino: TetrominoEntity?

    init(frame: CGRect, viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        setupScene()
        
        setupEntities()

        disablePieces()
    }
    
    func setupScene() {
        // Setup world tracking and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        arView.session.run(configuration)
        
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            if !self.viewModel.positionLocked {
                self.updateCursor()
            }
        }.store(in: &subscriptions)
        
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)
    }
    
    // Hide/Show active tetromino & process controls.
    func processUISignal(_ signal: ViewModel.UISignal) {
        switch signal {
        case .straightSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            straightPiece?.isEnabled = true
            activeTetromino = straightPiece
        case .squareSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            squarePiece.isEnabled = true
            activeTetromino = squarePiece
        case .tSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            tPiece.isEnabled = true
            activeTetromino = tPiece
        case .lSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            lPiece.isEnabled = true
            activeTetromino = lPiece
        case .skewSelected:
            disablePieces()
            clearActiveTetrominoTransform()
            skewPiece.isEnabled = true
            activeTetromino = skewPiece
        case .lockPosition:
            disablePieces()
            viewModel.positionLocked.toggle()
        case .moveLeft:
            moveLeftPressed()
        case .moveRight:
            moveRightPressed()
        case .rotateCCW:
            rotateCCWPressed()
        case .rotateCW:
            rotateCWPressed()
        }
    }
    
    func disablePieces() {
        straightPiece.isEnabled  = false
        squarePiece.isEnabled    = false
        tPiece.isEnabled         = false
        lPiece.isEnabled         = false
        skewPiece.isEnabled      = false
    }
    
    func clearActiveTetrominoTransform() {
        activeTetromino?.transform = Transform.identity
    }
    
    // Move cursor to plane detected.
    func updateCursor() {
        // Raycast to get cursor position.
        let results = raycast(from: center,
                              allowing: .existingPlaneGeometry,
                              alignment: .any)
        
        // Move cursor to position if hitting plane.
        if let result = results.first {
            cursor.isEnabled = true
            cursor.move(to: result.worldTransform, relativeTo: originAnchor)
        } else {
            cursor.isEnabled = false
        }
    }
    
    func setupEntities() {
        // Create an anchor at scene origin.
        originAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(originAnchor)
        
        // Create and add empty cursor entity to origin anchor.
        cursor = Entity()
        originAnchor.addChild(cursor)
        
        // Add directional light.
        directionalLight = DirectionalLight()
        directionalLight.light.intensity = 1000
        directionalLight.look(at: [0,0,0], from: [1, 1.1, 1.3], relativeTo: originAnchor)
        directionalLight.shadow = DirectionalLightComponent.Shadow(maximumDistance: 0.5, depthBias: 2)
        originAnchor.addChild(directionalLight)

        // Add checkerboard plane.
        var checkerBoardMaterial = PhysicallyBasedMaterial()
        checkerBoardMaterial.baseColor.texture = .init(try! .load(named: "checker-board.png"))
        let checkerBoardPlane = ModelEntity(mesh: .generatePlane(width: 0.5, depth: 0.5), materials: [checkerBoardMaterial])
        cursor.addChild(checkerBoardPlane)

        // Create an relative origin entity above the checkerboard.
        let relativeOrigin = Entity()
        relativeOrigin.position.x = 0.05 / 2
        relativeOrigin.position.z = 0.05 / 2
        relativeOrigin.position.y = 0.05 * 2.5
        cursor.addChild(relativeOrigin)


        // TODO: Refactor code using TetrominoEntity Classes. ////////////////////////////////////////////
        
        
        straightPiece = TetrominoEntity(color: "cyan", pieceType: "straight")
        relativeOrigin.addChild(straightPiece)
        
        squarePiece = TetrominoEntity(color: "yellow", pieceType: "square")
        relativeOrigin.addChild(squarePiece)
        
        tPiece = TetrominoEntity(color: "purple", pieceType: "t")
        relativeOrigin.addChild(tPiece)
        
        lPiece = TetrominoEntity(color: "orange", pieceType: "l")
        relativeOrigin.addChild(lPiece)
        
        skewPiece = TetrominoEntity(color: "green", pieceType: "skew")
        relativeOrigin.addChild(skewPiece)

    }


    // TODO: Implement controls to move and rotate tetromino.
    // IMPORTANT: Use optional activeTetromino variable for movement and rotation.
    // e.g. activeTetromino?.position.x
    
    func moveLeftPressed() {
        print("🔺 Did press move left")
        //activeTetromino?.position.x -= activeTetromino?.boxSize ?? 0
        let newPos = (activeTetromino?.boxSize ?? 0) * -1
        activeTetromino?.transform.matrix *= Transform(translation: [newPos,0,0]).matrix
    }

    func moveRightPressed() {
        print("🔺 Did press move right")
        //activeTetromino?.position.x += activeTetromino?.boxSize ?? 0
        let newPos = (activeTetromino?.boxSize ?? 0)
        activeTetromino?.transform.matrix *= Transform(translation: [newPos,0,0]).matrix
    }

    func rotateCCWPressed() {
        print("🔺 Did press rotate CCW")
        activeTetromino?.orientation *= simd_quatf(angle: (Float.pi)/2, axis: [0, 0, 1])
    }

    func rotateCWPressed() {
        print("🔺 Did press rotate CW")
        activeTetromino?.orientation *= simd_quatf(angle: -(Float.pi)/2, axis: [0, 0, 1])
    }
}

class TetrominoEntity: Entity {
    
    let boxSize: Float       = 0.05
    let cornerRadius: Float  = 0.002
    var material = SimpleMaterial()
    
    // Define inputs to class.
    init(color: String, pieceType: String) {
        super.init()
        
        let boxMesh = MeshResource.generateBox(size: self.boxSize, cornerRadius: self.cornerRadius)
        
        switch(color) {
            case "cyan":
                self.material = SimpleMaterial(color: .cyan, isMetallic: false )
                break
            case "yellow":
                self.material = SimpleMaterial(color: .yellow, isMetallic: false )
                break;
            case "purple":
                print("purple color")
                self.material = SimpleMaterial(color: .purple, isMetallic: false )
                break;
            case "orange":
                print("orange color")
                self.material = SimpleMaterial(color: .orange, isMetallic: false )
                break;
            case "green":
                print("green color")
                self.material = SimpleMaterial(color: .green, isMetallic: false )
                break;
            default: self.material = SimpleMaterial(color: .black, isMetallic: false );
        }
    
        let startingPiece = ModelEntity(mesh: boxMesh, materials: [self.material])
        self.addChild(startingPiece)
        
        switch(pieceType){
            case "straight":
                print("create straight piece")
                createStraightPiece(startingPiece: startingPiece)
                break;
            case "square":
                print("create square piece")
                createSquarePiece(startingPiece: startingPiece)
                break;
            case "t":
                print("create t piece")
                createTPiece(startingPiece: startingPiece)
            case "l":
                print("create l piece")
                createLPiece(startingPiece: startingPiece)
            case "skew":
                print("create skew piece")
               createSkewPiece(startingPiece: startingPiece)
            default:
                break;
        }

    }
    
    func createStraightPiece(startingPiece: Entity){
        for i in 1...4 {
            let cube = startingPiece.clone(recursive: false)
            cube.position.y = Float(i) * self.boxSize
            
//            let newPos = Float(i) * self.boxSize
//            cube.transform.matrix *= Transform(translation: [0,newPos,0]).matrix

    
            self.addChild(cube)
        }
    }
    
    func createSquarePiece(startingPiece: Entity){

        let topLeft = startingPiece.clone(recursive: false)
        topLeft.position.y += self.boxSize
        self.addChild(topLeft)
        
        let topRight = topLeft.clone(recursive: false)
        topRight.position.x += self.boxSize
        self.addChild(topRight)
        
        let bottomRight = startingPiece.clone(recursive: false)
        bottomRight.position.x += self.boxSize
        self.addChild(bottomRight)
    }
    
    func createTPiece(startingPiece: Entity){
        let topCube = startingPiece.clone(recursive: false)
        topCube.position.y += self.boxSize
        self.addChild(topCube)
        
        let leftCube = startingPiece.clone(recursive: false)
        leftCube.position.x -= self.boxSize
        self.addChild(leftCube)
        
        let rightCube = startingPiece.clone(recursive: false)
        rightCube.position.x += self.boxSize
        self.addChild(rightCube)
    
    }
    
    func createLPiece(startingPiece: Entity){
        for i in 1...2 {
            let cube = startingPiece.clone(recursive: false)
            cube.position.y = Float(i) * self.boxSize
            print(cube)
            self.addChild(cube)
        }
        let rightCube = startingPiece.clone(recursive: false)
        rightCube.position.x += self.boxSize
        self.addChild(rightCube)
    }
    
    func createSkewPiece(startingPiece: Entity){
        let bottomLeft = startingPiece.clone(recursive: false)
        bottomLeft.position.x -= self.boxSize
        self.addChild(bottomLeft)
        
        let topLeft = startingPiece.clone(recursive: false)
        topLeft.position.y += self.boxSize
        self.addChild(topLeft)
        
        let topRight = startingPiece.clone(recursive: false)
        topRight.position.y += self.boxSize
        topRight.position.x += self.boxSize
        self.addChild(topRight)
        
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
}
