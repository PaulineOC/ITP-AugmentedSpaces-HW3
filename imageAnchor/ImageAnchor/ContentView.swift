//
//  ContentView.swift
//  ImageAnchor
//
//  Created by Nien Lam on 9/21/21.
//  Copyright © 2021 Line Break, LLC. All rights reserved.
//

import SwiftUI
import ARKit
import RealityKit
import Combine
import CoreMotion
import AVFoundation
import CoreAudio


// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    let uiSignal = PassthroughSubject<UISignal, Never>()
    
    enum UISignal {
        case screenTapped
    }
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)
                .onTapGesture{
                    viewModel.uiSignal.send(.screenTapped)
                }
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
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

class SimpleARView: ARView, ARSessionDelegate {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var subscriptions = Set<AnyCancellable>()
    
    // Dictionary for tracking image anchors.
    var imageAnchorToEntity: [ARImageAnchor: AnchorEntity] = [:]
    
    // Variable for tracking ambient light intensity.
    var ambientIntensity: Double = 0
    
    // Motion manager for tracking movement.
    let motionManager = CMMotionManager()

    // Recorder for microphone usage.
    var recorder: AVAudioRecorder!
    
    var player: AVAudioPlayer!
    var crocus: Flower!
    var anemone: Flower!
    var rose: Flower!
    var allFlowers: [Flower] = []
    var allGolden = false
    var wasReverted = false
    var hitCount = 0
 
    
    struct Flower {
        var name: String
        var flowerModel: ModelEntity?
        var goldenMat: PhysicallyBasedMaterial
        var originalMat: RealityKit.Material
        var isGold: Bool = false
        
        init(flowerName: String){
            self.name = flowerName
            let filename: String
            var xPos = Float(0)
            var flowerScale: SIMD3<Float>
            var collisionSize: SIMD3<Float>
            
            switch(flowerName){
                case "crocus":
                    filename = "crocus.usdz";
                    xPos = 0
                    flowerScale = [0.2, 0.2, 0.2]
                    break
                case "anemone":
                    filename = "anemone.usdz";
                    xPos = 0.1
                    flowerScale = [0.25, 0.25, 0.25]
                    break
                case "rose":
                    filename = "rose.usdz";
                    xPos = -0.1
                    flowerScale = [0.09, 0.09, 0.09]
                    break
            default:
                filename = "crocus.usdz"
                flowerScale = [0.1,0.1,0.1]
                collisionSize = [1, 0.2, 1]
            }
            
            self.flowerModel = try! Entity.loadModel(named: filename)
            
            // Set transform:
            self.flowerModel?.position.y = 0.1
            self.flowerModel?.position.x = xPos
            self.flowerModel?.scale = flowerScale
                    
            //Set up materials:
            self.originalMat = (self.flowerModel?.model?.materials[0])!
            
            let golden = UIColor(red: 218, green: 165, blue: 0, alpha: 1)
            self.goldenMat = PhysicallyBasedMaterial()
            self.goldenMat.baseColor = PhysicallyBasedMaterial.BaseColor(tint: golden)
            self.goldenMat.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0)
            self.goldenMat.metallic  = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.5)
            //self.flowerModel?.generateCollisionShapes(recursive: true)
        }
        
        mutating func turnGold(){
            self.isGold = true
            self.flowerModel?.model?.materials[0] = self.goldenMat
        }
        
        mutating func reverted(){
            self.isGold = false
            self.flowerModel?.model?.materials[0] = self.originalMat
        }
    }


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
        
        setupMotionManager()
        
        setupMicrophoneSensor()
        
        setupScene()
        
    }
    
    func setupMotionManager() {
        motionManager.startAccelerometerUpdates()
        motionManager.startGyroUpdates()
        motionManager.startMagnetometerUpdates()
        motionManager.startDeviceMotionUpdates()
    }
    
    func setupMicrophoneSensor() {
        let documents = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0])
        let url = documents.appendingPathComponent("record.caf")

        let recordSettings: [String: Any] = [
            AVFormatIDKey:              kAudioFormatAppleIMA4,
            AVSampleRateKey:            44100.0,
            AVNumberOfChannelsKey:      2,
            AVEncoderBitRateKey:        12800,
            AVLinearPCMBitDepthKey:     16,
            AVEncoderAudioQualityKey:   AVAudioQuality.max.rawValue
        ]

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord)
            try audioSession.setActive(true)
            try recorder = AVAudioRecorder(url:url, settings: recordSettings)
        } catch {
            return
        }

        recorder.prepareToRecord()
        recorder.isMeteringEnabled = true
        recorder.record()
    }
    
    func setupScene() {
        // Setup world tracking and plane detection.
        let configuration = ARImageTrackingConfiguration()
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]


        // TODO: Update target image and physical width in meters. //////////////////////////////////////
        let targetImage    = "Midas.jpeg"
        let physicalWidth  = 0.1524
        
        if let refImage = UIImage(named: targetImage)?.cgImage {
            let arReferenceImage = ARReferenceImage(refImage, orientation: .up, physicalWidth: physicalWidth)
            var set = Set<ARReferenceImage>()
            set.insert(arReferenceImage)
            configuration.trackingImages = set
        } else {
            print("❗️ Error loading target image")
        }
    
        arView.session.run(configuration)
        
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            // Call renderLoop method on every frame.
            self.renderLoop()
        }.store(in: &subscriptions)
        
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)

        // Set session delegate.
        arView.session.delegate = self
    }
    
    // Hide/Show active tetromino.
    func processUISignal(_ signal: ViewModel.UISignal) {
        switch signal {
        case .screenTapped:
            handleScreenTap()
        }
    }
    
    func handleScreenTap(){
        hitCount += 1
        if(hitCount == 1 && rose.isGold == false){
            rose.turnGold()
            playSound()
        }
        else if(hitCount == 2 && crocus.isGold == false){
            crocus.turnGold()
            playSound()
        }
        else if(hitCount == 3 && anemone.isGold == false){
            anemone.turnGold()
            playSound()
            if(wasReverted == true){
                wasReverted = false
            }
        }
        else{
            hitCount = 0
        }
        print(hitCount)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        anchors.compactMap { $0 as? ARImageAnchor }.forEach {
            // Create anchor from image.
            let anchorEntity = AnchorEntity(anchor: $0)
            
            // Track image anchors added to scene.
            imageAnchorToEntity[$0] = anchorEntity
            
            // Add anchor to scene.
            arView.scene.addAnchor(anchorEntity)
            
            // Call setup method for entities.
            // IMPORTANT: Play USDZ animations after entity is added to the scene.
            setupEntities(anchorEntity: anchorEntity)
        }
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if let intensity = frame.lightEstimate?.ambientIntensity {
            ambientIntensity = intensity
        }
    }

    // TODO: Setup entities. //////////////////////////////////////
    // IMPORTANT: Attach to anchor entity. Called when image target is found.
    func setupEntities(anchorEntity: AnchorEntity) {
        crocus = Flower(flowerName: "crocus");
        anchorEntity.addChild(crocus.flowerModel!)
        anemone = Flower(flowerName: "anemone");
        anchorEntity.addChild(anemone.flowerModel!)
        rose = Flower(flowerName: "rose");
        anchorEntity.addChild(rose.flowerModel!)
        
        allFlowers.append(crocus!)
        allFlowers.append(anemone!)
        allFlowers.append(rose!)
    }
    

    // TODO: Animate entities. //////////////////////////////////////
    func renderLoop() {
        
//TODO: For some reason flower.isGold wouldn't be true despite being set by handleScreen tap?
//        for flower in allFlowers{
//            print(flower.isGold)
//            allGolden = true
//            if(flower.isGold == false){
//                allGolden = false
//            }
//        }
        
        if(rose?.isGold == true && crocus?.isGold == true && anemone?.isGold == true){
            allGolden = true
        }
        
        // Sensor: Decibel power
        recorder.updateMeters()
        let decibelPower = recorder.averagePower(forChannel: 0)
        
        if(decibelPower >= -4 && allGolden == true && wasReverted == false){
            print("Restore!");
//            for i in allFlowers.indices{
//                allFlowers[i].reverted()
//            }
            rose.reverted();
            crocus.reverted();
            anemone.reverted();
            
            hitCount = 0
            wasReverted = true
        }
    
        crocus?.flowerModel?.orientation *= simd_quatf(angle: 0.02, axis: [0, 1, 0])
        anemone?.flowerModel?.orientation *= simd_quatf(angle: 0.02, axis: [0, 1, 0])
        rose?.flowerModel?.orientation *= simd_quatf(angle: 0.02, axis: [0, 1, 0])
    }
    
    func playSound() {
      let url = Bundle.main.url(forResource: "sparkle", withExtension: "mp3")
      player = try! AVAudioPlayer(contentsOf: url!)
      player.play()
    }
}
