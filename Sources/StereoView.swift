//
//  StereoView.swift
//  MetalScope
//
//  Created by Jun Tanaka on 2017/01/23.
//  Copyright © 2017 eje Inc. All rights reserved.
//

import UIKit
import SceneKit

public final class StereoView: UIView, MediaSceneLoader {
    #if METALSCOPE_ENABLE_METAL
    public let stereoTexture: MTLTexture

    public var device: MTLDevice {
        return stereoTexture.device
    }
    #endif

    public var scene: SCNScene? {
        didSet {
            orientationNode.removeFromParentNode()
            scene?.rootNode.addChildNode(orientationNode)

            #if METALSCOPE_ENABLE_METAL
            stereoRenderer.scene = scene
            #endif
        }
    }

    public weak var sceneRendererDelegate: SCNSceneRendererDelegate? {
        didSet {
            #if METALSCOPE_ENABLE_METAL
            scnRendererDelegate.forwardingTarget = sceneRendererDelegate
            #endif
        }
    }

    public lazy var orientationNode: OrientationNode = {
        let node = OrientationNode()
        node.pointOfView.addChildNode(self.stereoCameraNode)
        node.interfaceOrientationProvider = UIInterfaceOrientation.landscapeRight
        node.updateInterfaceOrientation()
        return node
    }()

    public lazy var stereoCameraNode: StereoCameraNode = {
        let node = StereoCameraNode(stereoParameters: self.stereoParameters)
        node.position = SCNVector3(0, 0.1, -0.08)
        return node
    }()

    public var stereoParameters: StereoParametersProtocol = StereoParameters() {
        didSet {
            stereoCameraNode.stereoParameters = stereoParameters

            #if METALSCOPE_ENABLE_METAL
            stereoScene.stereoParameters = stereoParameters
            #endif
        }
    }

    public lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer()
        self.addGestureRecognizer(recognizer)
        return recognizer
    }()

    lazy var scnView: SCNView = {
        #if METALSCOPE_ENABLE_METAL
        let view = SCNView(frame: self.bounds, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue,
            SCNView.Option.preferredDevice.rawValue: self.device
        ])
        view.delegate = self.scnViewDelegate
        view.scene = self.stereoScene
        view.pointOfView = self.stereoScene.pointOfView
        #else
        let view = SCNView(frame: self.bounds)
        #endif
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.isPlaying = true
        self.addSubview(view)
        return view
    }()

    #if METALSCOPE_ENABLE_METAL
    fileprivate lazy var stereoRenderer: StereoRenderer = {
        let renderer = StereoRenderer(outputTexture: self.stereoTexture)
        renderer.setPointOfView(self.stereoCameraNode.pointOfView(for: .left), for: .left)
        renderer.setPointOfView(self.stereoCameraNode.pointOfView(for: .right), for: .right)
        renderer.sceneRendererDelegate = self.scnRendererDelegate
        return renderer
    }()
    #endif

    #if METALSCOPE_ENABLE_METAL
    fileprivate lazy var stereoScene: StereoScene = {
        let scene = StereoScene()
        scene.stereoParameters = self.stereoParameters
        scene.stereoTexture = self.stereoTexture
        return scene
    }()
    #endif

    #if METALSCOPE_ENABLE_METAL
    private lazy var scnViewDelegate: SCNViewDelegate = {
        return SCNViewDelegate(stereoRenderer: self.stereoRenderer)
    }()
    #endif

    private lazy var scnRendererDelegate: SCNRendererDelegate = {
        return SCNRendererDelegate(orientationNode: self.orientationNode)
    }()

    #if METALSCOPE_ENABLE_METAL
    public init(stereoTexture: MTLTexture) {
        self.stereoTexture = stereoTexture

        super.init(frame: UIScreen.main.landscapeBounds)
    }

    public convenience init(device: MTLDevice, maximumTextureSize: CGSize? = nil) {
        let nativeScreenSize = UIScreen.main.nativeLandscapeBounds.size
        var textureSize = nativeScreenSize

        if let maxSize = maximumTextureSize {
            let nRatio = nativeScreenSize.width / nativeScreenSize.height
            let mRatio = maxSize.width / maxSize.height
            if nRatio >= mRatio && nativeScreenSize.width > maxSize.width {
                textureSize.width = maxSize.width
                textureSize.height = round(maxSize.width / nRatio)
            } else if nRatio <= mRatio && nativeScreenSize.height > maxSize.height {
                textureSize.width = round(maxSize.height * nRatio)
                textureSize.height = maxSize.height
            }
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Int(textureSize.width),
            height: Int(textureSize.height),
            mipmapped: true
        )
        let texture = device.makeTexture(descriptor: textureDescriptor)

        self.init(stereoTexture: texture)

        let sceneScale = textureSize.width / (bounds.width * UIScreen.main.scale)
        scnView.transform = CGAffineTransform(scaleX: sceneScale, y: sceneScale)
    }
    #else
    public init() {
        super.init(frame: UIScreen.main.landscapeBounds)
    }
    #endif

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        scene = nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        scnView.frame = bounds
    }
}

extension StereoView {
    public var isPlaying: Bool {
        get {
            return scnView.isPlaying
        }
        set(value) {
            scnView.isPlaying = value
        }
    }

    public func snapshot() -> UIImage {
        return scnView.snapshot()
    }

    public func resetCenter() {
        orientationNode.resetCenter(animated: true)
    }
}

#if METALSCOPE_ENABLE_METAL
extension StereoView {
    public var sceneRenderer: SCNSceneRenderer {
        return stereoRenderer.scnRenderer
    }

    @available(*, unavailable, message: "Use sceneRendererDelegate property instead")
    public func sceneRendererDelegate(for eye: Eye) -> SCNSceneRendererDelegate? {
        fatalError("Use sceneRendererDelegate property instead")
    }

    @available(*, unavailable, message: "Use sceneRendererDelegate property instead")
    public func setSceneRendererDelegate(_ delegate: SCNSceneRendererDelegate, for eye: Eye) {
        fatalError("Use sceneRendererDelegate property instead")
    }
}
#endif

#if METALSCOPE_ENABLE_METAL
private extension StereoView {
    final class SCNViewDelegate: NSObject, SCNSceneRendererDelegate {
        let stereoRenderer: StereoRenderer

        init(stereoRenderer: StereoRenderer) {
            self.stereoRenderer = stereoRenderer
        }

        func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
            guard let commandQueue = renderer.commandQueue else {
                fatalError("Invalid rendering API")
            }

            stereoRenderer.render(atTime: time, commandQueue: commandQueue)
        }
    }
}
#endif

private extension StereoView {
    final class SCNRendererDelegate: NSObject, SCNSceneRendererDelegate {
        weak var forwardingTarget: SCNSceneRendererDelegate?

        let orientationNode: OrientationNode

        init(orientationNode: OrientationNode) {
            self.orientationNode = orientationNode
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if let provider = orientationNode.deviceOrientationProvider, provider.shouldWaitDeviceOrientation(atTime: time) {
                provider.waitDeviceOrientation(atTime: time)
            }

            SCNTransaction.lock()
            SCNTransaction.begin()
            SCNTransaction.disableActions = true

            orientationNode.updateDeviceOrientation(atTime: time)

            SCNTransaction.commit()
            SCNTransaction.unlock()

            forwardingTarget?.renderer?(renderer, updateAtTime: time)
        }

        func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
            forwardingTarget?.renderer?(renderer, didApplyAnimationsAtTime: time)
        }

        func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
            forwardingTarget?.renderer?(renderer, didSimulatePhysicsAtTime: time)
        }

        func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
            forwardingTarget?.renderer?(renderer, willRenderScene: scene, atTime: time)
        }

        func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            forwardingTarget?.renderer?(renderer, didRenderScene: scene, atTime: time)
        }
    }
}

private extension UIScreen {
    var landscapeBounds: CGRect {
        return CGRect(x: 0, y: 0, width: fixedCoordinateSpace.bounds.height, height: fixedCoordinateSpace.bounds.width)
    }

    var nativeLandscapeBounds: CGRect {
        return CGRect(x: 0, y: 0, width: nativeBounds.height, height: nativeBounds.width)
    }
}
