/*
Eye Tracking Helper Classes
Utilities for eye tracking integration in multi-camera setup
*/

import UIKit
import ARKit
import AVFoundation

// MARK: - Device Helper Extension
extension UIDevice {
    static var screenSize: CGSize {
        let screenWidthPixel: CGFloat = UIScreen.main.nativeBounds.width
        let screenHeightPixel: CGFloat = UIScreen.main.nativeBounds.height
        let ppi: CGFloat = UIScreen.main.scale * 163
        
        let a_ratio = (1125/458)/0.0623908297
        let b_ratio = (2436/458)/0.135096943231532

        return CGSize(
            width: (screenWidthPixel/ppi)/a_ratio,
            height: (screenHeightPixel/ppi)/b_ratio
        )
    }
    
    static var frameSize: CGSize {
        return CGSize(
            width: UIScreen.main.bounds.size.width,
            height: UIScreen.main.bounds.size.height - 82
        )
    }
}

// MARK: - Gaze Point Converter
class GazePointConverter {
    static func convertARGazeToScreenPoint(
        _ gazePoint: simd_float3,
        faceAnchor: ARFaceAnchor,
        cameraTransform: simd_float4x4,
        screenBounds: CGRect
    ) -> CGPoint {
        // Transform gaze point to world coordinates
        let gazeInWorld = faceAnchor.transform * simd_float4(gazePoint, 1)
        
        // Transform to camera space
        let gazeInCamera = simd_mul(simd_inverse(cameraTransform), gazeInWorld)
        
        // Convert to screen coordinates
        let screenX = CGFloat(gazeInCamera.y) / (CGFloat(UIDevice.screenSize.width) / 2) * CGFloat(UIDevice.frameSize.width)
        let screenY = CGFloat(gazeInCamera.x) / (CGFloat(UIDevice.screenSize.height) / 2) * CGFloat(UIDevice.frameSize.height)
        
        return CGPoint(
            x: max(0, min(screenBounds.width, screenX)),
            y: max(0, min(screenBounds.height, screenY))
        )
    }
}

// MARK: - Eye Tracking Overlay View
class EyeTrackingOverlayView: UIView {
    
    private var gazeIndicator: UIView?
    private var statusLabel: UILabel?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        
        // Create gaze indicator
        gazeIndicator = UIView()
        gazeIndicator?.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        gazeIndicator?.layer.cornerRadius = 20
        gazeIndicator?.layer.borderWidth = 2
        gazeIndicator?.layer.borderColor = UIColor.white.cgColor
        gazeIndicator?.isHidden = true
        addSubview(gazeIndicator!)
        
        // Create status label
        statusLabel = UILabel()
        statusLabel?.textAlignment = .center
        statusLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel?.textColor = .white
        statusLabel?.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        statusLabel?.layer.cornerRadius = 8
        statusLabel?.clipsToBounds = true
        statusLabel?.text = "Eye Tracking: OFF"
        addSubview(statusLabel!)
        
        // Position status label
        statusLabel?.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel!.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            statusLabel!.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel!.widthAnchor.constraint(equalToConstant: 150),
            statusLabel!.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    func updateGazePoint(_ point: CGPoint, isWinking: Bool) {
        guard let gazeIndicator = gazeIndicator else { return }
        
        gazeIndicator.center = point
        gazeIndicator.isHidden = false
        
        let size: CGFloat = isWinking ? 80 : 40
        let cornerRadius: CGFloat = size / 2
        
        UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState]) {
            gazeIndicator.frame.size = CGSize(width: size, height: size)
            gazeIndicator.layer.cornerRadius = cornerRadius
            gazeIndicator.backgroundColor = isWinking ?
                UIColor.systemRed.withAlphaComponent(0.8) :
                UIColor.systemBlue.withAlphaComponent(0.8)
        }
    }
    
    func setEyeTrackingStatus(_ isActive: Bool) {
        statusLabel?.text = isActive ? "Eye Tracking: ON" : "Eye Tracking: OFF"
        gazeIndicator?.isHidden = !isActive
        
        if !isActive {
            gazeIndicator?.removeFromSuperview()
            gazeIndicator = nil
            setupGazeIndicator()
        }
    }
    
    private func setupGazeIndicator() {
        gazeIndicator = UIView()
        gazeIndicator?.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        gazeIndicator?.layer.cornerRadius = 20
        gazeIndicator?.layer.borderWidth = 2
        gazeIndicator?.layer.borderColor = UIColor.white.cgColor
        gazeIndicator?.isHidden = true
        addSubview(gazeIndicator!)
    }
    
    func highlightFrontCamera(_ frontCameraFrame: CGRect, gazePoint: CGPoint) {
        // Create a temporary highlight on the front camera view
        let highlightView = UIView()
        highlightView.backgroundColor = UIColor.yellow.withAlphaComponent(0.3)
        highlightView.layer.borderColor = UIColor.yellow.cgColor
        highlightView.layer.borderWidth = 2
        highlightView.layer.cornerRadius = 15
        
        // Convert gaze point to front camera coordinates
        let relativeX = (gazePoint.x / bounds.width) * frontCameraFrame.width
        let relativeY = (gazePoint.y / bounds.height) * frontCameraFrame.height
        
        let highlightCenter = CGPoint(
            x: frontCameraFrame.origin.x + relativeX,
            y: frontCameraFrame.origin.y + relativeY
        )
        
        highlightView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        highlightView.center = highlightCenter
        
        addSubview(highlightView)
        
        // Animate and remove
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseOut]) {
            highlightView.alpha = 0
            highlightView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        } completion: { _ in
            highlightView.removeFromSuperview()
        }
    }
}

// MARK: - Eye Tracking Manager
class EyeTrackingManager: NSObject, ARSessionDelegate {
    
    weak var delegate: EyeTrackingManagerDelegate?
    private var arSession: ARSession?
    private var isActive = false
    
    override init() {
        super.init()
    }
    
    func startTracking() {
        guard ARFaceTrackingConfiguration.isSupported else {
            delegate?.eyeTrackingManager(self, didFailWithError: .faceTrackingNotSupported)
            return
        }
        
        if arSession == nil {
            arSession = ARSession()
            arSession?.delegate = self
        }
        
        let configuration = ARFaceTrackingConfiguration()
        arSession?.run(configuration)
        isActive = true
        
        delegate?.eyeTrackingManagerDidStart(self)
    }
    
    func stopTracking() {
        arSession?.pause()
        isActive = false
        delegate?.eyeTrackingManagerDidStop(self)
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard isActive,
              let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
            return
        }
        
        DispatchQueue.main.async {
            self.delegate?.eyeTrackingManager(self, didUpdateFaceAnchor: faceAnchor)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        delegate?.eyeTrackingManager(self, didFailWithError: .sessionError(error))
    }
}

// MARK: - Eye Tracking Manager Delegate
protocol EyeTrackingManagerDelegate: AnyObject {
    func eyeTrackingManagerDidStart(_ manager: EyeTrackingManager)
    func eyeTrackingManagerDidStop(_ manager: EyeTrackingManager)
    func eyeTrackingManager(_ manager: EyeTrackingManager, didUpdateFaceAnchor anchor: ARFaceAnchor)
    func eyeTrackingManager(_ manager: EyeTrackingManager, didFailWithError error: EyeTrackingError)
}

// MARK: - Eye Tracking Errors
enum EyeTrackingError: Error {
    case faceTrackingNotSupported
    case sessionError(Error)
    
    var localizedDescription: String {
        switch self {
        case .faceTrackingNotSupported:
            return "Face tracking is not supported on this device"
        case .sessionError(let error):
            return "AR Session error: \(error.localizedDescription)"
        }
    }
}

// MARK: - CGFloat Extensions
extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

// MARK: - Gesture Recognition Helper
class EyeTrackingGestureRecognizer {
    
    static func detectWink(from blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) -> Bool {
        guard let leftEyeBlink = blendShapes[.eyeBlinkLeft] as? Float,
              let rightEyeBlink = blendShapes[.eyeBlinkRight] as? Float else {
            return false
        }
        
        return leftEyeBlink > 0.9 && rightEyeBlink > 0.9
    }
    
    static func detectEyebrowRaise(from blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) -> Bool {
        guard let browInnerUp = blendShapes[.browInnerUp] as? Float else {
            return false
        }
        
        return browInnerUp > 0.1
    }
    
    static func detectSmile(from blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) -> Bool {
        guard let mouthSmileLeft = blendShapes[.mouthSmileLeft] as? Float,
              let mouthSmileRight = blendShapes[.mouthSmileRight] as? Float else {
            return false
        }
        
        return mouthSmileLeft > 0.3 && mouthSmileRight > 0.3
    }
}
