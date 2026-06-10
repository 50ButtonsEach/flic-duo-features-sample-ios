//
//  FlicViewModel.swift
//  flic2lib-ios-sample
//
//  Created by Oskar Öberg on 2024-02-09.
//

import Foundation
import flic2lib

/// A single accelerometer reading, used as a data point in the live graph.
struct AccelerometerSample: Identifiable {
	let id: Int
	let x: Double
	let y: Double
	let z: Double
}

@dynamicMemberLookup
class FlicButtonModel: ObservableObject, Identifiable {
	let flicButton: FLICButton
	@Published var downButtons: Set<UInt8> = []

	// MARK: Accelerometer streaming

	/// Whether accelerometer streaming is currently active.
	@Published var isAccelerometerStreaming: Bool = false
	/// True while an enable request is in flight, used to disable the UI toggle.
	@Published var isAccelerometerBusy: Bool = false
	/// A rolling window of the most recent samples to plot.
	@Published var accelerometerSamples: [AccelerometerSample] = []
	/// The last error returned when trying to enable streaming, if any.
	@Published var accelerometerError: String? = nil

	private var accelerometerSampleIndex = 0
	private let maxAccelerometerSamples = 150

	var id: UUID {
		flicButton.identifier
	}

	var isDuo:Bool {
		return self.flicButton.serialNumber.hasPrefix("D")
	}

	init(_ flicButton: FLICButton) {
		self.flicButton = flicButton
	}

	subscript<T>(dynamicMember keyPath: KeyPath<FLICButton, T>) -> T {
		return flicButton[keyPath: keyPath]
	}

	/// Enables accelerometer streaming using the demo configuration.
	func enableAccelerometerStreaming() {
		isAccelerometerBusy = true
		accelerometerError = nil

		let config = FLICButtonAccelerometerConfig(
			lowPowerMode: 0,
			mode: 1,
			outputDataRate: 5,
			bandwidthFilter: 0,
			fullScaleSelection: 1,
			filterDatatypeSelection: 0,
			lowNoise: 0,
			highPassRefMode: 0,
			onlyWhilePressed: 0,
			samplesPerBurst: 1
		)

		flicButton.enableAccelerometerStreaming(with: config) { [weak self] result in
			DispatchQueue.main.async {
				guard let self = self else { return }
				self.isAccelerometerBusy = false
				if result == .OK {
					self.isAccelerometerStreaming = true
				} else {
					self.accelerometerError = FlicButtonModel.description(for: result)
				}
			}
		}
	}

	// MARK: Buzzer

	/// Plays a series of notes on the Flic Duo's buzzer.
	func playBuzzer(_ notes: [(hz: Int32, duration: Float)]) {
		let buzzerNotes = notes.map { FLICButtonBuzzerNote(hz: $0.hz, duration: $0.duration) }
		flicButton.playBuzzerSound(buzzerNotes)
	}

	/// Disables accelerometer streaming and clears the graph.
	func disableAccelerometerStreaming() {
		flicButton.disableAccelerometerStreaming()
		isAccelerometerStreaming = false
		accelerometerSamples = []
		accelerometerSampleIndex = 0
	}

	/// Appends a freshly received batch of samples to the rolling window.
	fileprivate func appendAccelerometerData(_ data: FLICButtonAccelerometerData) {
		guard isAccelerometerStreaming else { return }

		for point in data.points {
			accelerometerSamples.append(
				AccelerometerSample(
					id: accelerometerSampleIndex,
					x: Double(point.x),
					y: Double(point.y),
					z: Double(point.z)
				)
			)
			accelerometerSampleIndex += 1
		}

		if accelerometerSamples.count > maxAccelerometerSamples {
			accelerometerSamples.removeFirst(accelerometerSamples.count - maxAccelerometerSamples)
		}
	}

	private static func description(for result: FLICButtonEnableAccelerometerStreamingResult) -> String {
		switch result {
		case .OK: return "OK"
		case .invalidConfig: return "Invalid accelerometer configuration."
		case .busy: return "The Flic is busy. Please try again."
		case .notReady: return "The Flic is not ready yet. Wait for it to connect."
		case .notSupported: return "Accelerometer streaming is not supported by this Flic."
		case .firmwareUpdateNeeded: return "A firmware update is needed to use this feature."
		@unknown default: return "Failed to enable accelerometer streaming."
		}
	}
}

class FlicListViewModel: NSObject, ObservableObject, FLICButtonDelegate, FLICManagerDelegate {
	
	@Published var buttons: [FlicButtonModel] = []
	@Published var promptToRemoveButton: Bool = false
	@Published var buttonToBeRemoved: FlicButtonModel?
	@Published var isScanning: Bool = false
	@Published var scanState: FLICButtonScannerStatusEvent? = nil
	
	override convenience init() {
		self.init(isPreview: false)
	}
	
	init(isPreview: Bool) {
		super.init()
		if !isPreview {
			FLICManager.configure(with: self, buttonDelegate: self, background: true)
		}
	}

	// MARK: - FLICButtonDelegate
	
	func buttonDidConnect(_ flicButton: FLICButton) {
		print("buttonDidConnect")
		buttons.first(where: { $0.flicButton == flicButton })?.objectWillChange.send()
	}
	
	func buttonIsReady(_ button: FLICButton) {
		print("buttonIsReady")
		reloadButtons()
	}
	
	func button(_ flicButton: FLICButton, didDisconnectWithError error: Error?) {
		print("didDisconnectWithError", error ?? "")
		buttons.first(where: { $0.flicButton == flicButton })?.objectWillChange.send()
	}
	
	func button(_ flicButton: FLICButton, didReceive buttonEvent: FLICButtonEvent) {

		// Note that all events from the buttons will be sent to this delegate,
		// including gestures and all button changes. Use the ButtonEvent convenience
		// methods to single out the events that you are interested in.
		// See examples bellow:

		// Determine if the event was a Duo swipe gesture
		buttonEvent.isGesture { gesture, buttonNumber in
			if let gestureString = gesture == .left ? "Left" : gesture == .right ? "Right" : gesture == .up ? "Up" : gesture == .down ? "Down" : nil {
				print("\(flicButton.serialNumber) – [Swipe \(gestureString)] on button \(buttonNumber)")
			}
		}
		
		// Determine if the event is a click, double click or hold.
		// Note that listening for all click types introduces some latency since
		// we need to distinguis between click and double click for example.
		// For optimal latency, use the buttonEvent.isButtonDown method.
		buttonEvent.isSingleOrDoubleClickOrHold { type, buttonNumber in
			let typeString = type == .singleClick ? "Click" : type == .doubleClick ? "Double Click" : "Hold"
			print("\(flicButton.serialNumber) – [\(typeString)] on button \(buttonNumber)")
		}
		
		// update UI button state
		if buttonEvent.eventClass == .upOrDown {
			if let button = buttons.first(where: { $0.flicButton == flicButton }) {
				if (buttonEvent.type == .down) {
					button.downButtons.insert(buttonEvent.buttonNumber)
				} else {
					button.downButtons.remove(buttonEvent.buttonNumber)
				}
			}
		}
	}
	
	func button(_ button: FLICButton, didFailToConnectWithError error: Error?) {
		print("didFailToConnectWithError", error ?? "")
	}

	func button(_ button: FLICButton, didReceive accelerometerData: FLICButtonAccelerometerData) {
		// Route the streamed samples to the matching button model so its detail view can plot them.
		buttons.first(where: { $0.flicButton == button })?.appendAccelerometerData(accelerometerData)
	}
	
	// MARK: - FLICManagerDelegate
	
	func managerDidRestoreState(_ manager: FLICManager) {
		print("managerDidRestoreState")
		reloadButtons()
	}
	
	func manager(_ manager: FLICManager, didUpdate state: FLICManagerState) {
		print("managerDidUpdate")
	}
	
	// MARK: - Helpers
	
	func reloadButtons() {
		DispatchQueue.main.async {
			var newButtons: [FlicButtonModel] = []
			if let manager = FLICManager.shared() {
				for flicButton in manager.buttons() {
					newButtons.append(FlicButtonModel(flicButton))
				}
			}
			self.buttons = newButtons
		}
	}
	
	func removeButton(_ button: FlicButtonModel) {
		FLICManager.shared()?.forgetButton(button.flicButton) { uuid, error in
			self.reloadButtons()
		}
	}
	
	@Published var scanError: String? = nil

	func scan() {
		scanState = nil
		isScanning = true
		scanError = nil
		FLICManager.shared()?.scanForButtons(stateChangeHandler: { event in
			print(event)
			self.scanState = event
		}, completion: { button, error in
			self.isScanning = false
			if let error = error {
				self.scanError = error.localizedDescription
			}
		})
	}
}
