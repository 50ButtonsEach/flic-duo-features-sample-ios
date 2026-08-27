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

/// Runtime-only settings used when enabling fall detection on the Flic.
struct FallDetectionSettings: Equatable {
	var lowGThresholdMg: UInt16 = 700
	var lowGDurationMs: UInt16 = 500
	var highGTimeoutMs: UInt16 = 650
	var highGThresholdMg: UInt16 = 3500
	var highGTimeWindowMs: UInt16 = 50
	var postEventRecordDurationMs: UInt16 = 2000
	var fullScaleSelection: FLICButtonAccelerometerFullScaleSelection = .fourG

	static let `default` = FallDetectionSettings()

	func makeConfig() -> FLICButtonFallDetectionConfig {
		FLICButtonFallDetectionConfig(
			lowGThresholdMg: lowGThresholdMg,
			lowGDurationMs: lowGDurationMs,
			highGTimeoutMs: highGTimeoutMs,
			highGThresholdMg: highGThresholdMg,
			highGTimeWindowMs: highGTimeWindowMs,
			postEventRecordDurationMs: postEventRecordDurationMs,
			fullScaleSelection: fullScaleSelection
		)
	}
}

/// A stored fall-detection accelerometer sample.
struct FallDetectionSample: Identifiable, Equatable {
	let id: Int
	let x: Double
	let y: Double
	let z: Double

	var magnitude: Double {
		sqrt((x * x) + (y * y) + (z * z))
	}
}

enum FallEventStatus: Equatable {
	case triggered
	case collectingPostFallData
	case completed
	case cancelledByUser

	var title: String {
		switch self {
		case .triggered, .collectingPostFallData:
			return "Pending..."
		case .completed:
			return "Completed"
		case .cancelledByUser:
			return "Cancelled by User"
		}
	}
}

/// A single fall event, kept only in memory for this sample app session.
struct FallEvent: Identifiable, Equatable {
	let id = UUID()
	let sequenceNumber: Int
	let triggeredAt: Date
	var status: FallEventStatus = .triggered
	var preFallSampleRate: UInt16?
	var preFallExpectedSampleCount: UInt16?
	var preFallSamples: [FallDetectionSample] = []
	var postFallSampleRate: UInt16?
	var postFallExpectedSampleCount: UInt16?
	var postFallSamples: [FallDetectionSample] = []
	var hasCompletedData = false

	var isAwaitingCompleteCurve: Bool {
		!hasCompletedData
	}
}

@dynamicMemberLookup
class FlicButtonModel: ObservableObject, Identifiable {
	var flicButton: FLICButton
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

	// MARK: Fall detection

	@Published var fallDetectionSettings: FallDetectionSettings = .default
	@Published var isFallDetectionEnabled: Bool = false
	@Published var isFallDetectionBusy: Bool = false
	@Published var fallDetectionError: String? = nil
	@Published var fallEvents: [FallEvent] = []

	/// True while either mutually exclusive motion feature is being enabled.
	var isMotionFeatureBusy: Bool {
		isAccelerometerBusy || isFallDetectionBusy
	}

	private var fallEventSequence = 0
	private var activeFallEventID: UUID?
	fileprivate static let smallButtonNumber: UInt8 = 1

	var id: UUID {
		flicButton.identifier
	}

	var isDuo:Bool {
		return self.flicButton.serialNumber.hasPrefix("D")
	}

	var connectionActionTitle: String {
		flicButton.state == .disconnected ? "Connect" : "Disconnect"
	}

	var connectionActionSystemImage: String {
		flicButton.state == .disconnected ? "link" : "link.slash"
	}

	var isConnectionActionDisabled: Bool {
		flicButton.state == .disconnecting
	}

	init(_ flicButton: FLICButton) {
		self.flicButton = flicButton
	}

	subscript<T>(dynamicMember keyPath: KeyPath<FLICButton, T>) -> T {
		return flicButton[keyPath: keyPath]
	}

	func updateButtonReference(_ flicButton: FLICButton) {
		self.flicButton = flicButton
		objectWillChange.send()
	}

	func markDisconnected() {
		downButtons = []

		isAccelerometerStreaming = false
		isAccelerometerBusy = false
		accelerometerError = nil
		accelerometerSamples = []
		accelerometerSampleIndex = 0

		isFallDetectionEnabled = false
		isFallDetectionBusy = false
		fallDetectionError = nil
	}

	func toggleConnection() {
		switch flicButton.state {
		case .connected, .connecting:
			flicButton.disconnect()
			markDisconnected()
		case .disconnected:
			flicButton.connect()
			objectWillChange.send()
		case .disconnecting:
			break
		@unknown default:
			flicButton.connect()
			objectWillChange.send()
		}
	}

	/// Enables accelerometer streaming using the demo configuration.
	func enableAccelerometerStreaming() {
		isAccelerometerBusy = true
		accelerometerError = nil

		if isFallDetectionEnabled {
			disableFallDetection()
		}

		let config = FLICButtonAccelerometerStreamingConfig(
			lowPowerMode: 0,
			mode: 1,
			outputDataRate: 5,
			bandwidthFilter: 0,
			fullScaleSelection: .fourG,
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
				if result == .success {
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
		let buzzerNotes = notes.map {
			FLICButtonBuzzerNote(hz: Float($0.hz), duration: UInt16($0.duration * 1_000))
		}
		flicButton.playBuzzerSound(buzzerNotes)
	}

	/// Enables fall detection using the current in-memory settings.
	func enableFallDetection() {
		isFallDetectionBusy = true
		fallDetectionError = nil

		if isAccelerometerStreaming {
			disableAccelerometerStreaming()
		}

		flicButton.enableFallDetection(with: fallDetectionSettings.makeConfig(), alwaysReconnect: true) { [weak self] result in
			DispatchQueue.main.async {
				guard let self = self else { return }
				self.isFallDetectionBusy = false
				if result == .success {
					self.isFallDetectionEnabled = true
				} else {
					self.isFallDetectionEnabled = false
					self.fallDetectionError = FlicButtonModel.description(for: result)
				}
			}
		}
	}

	/// Disables fall detection and also disables always-reconnect advertising.
	func disableFallDetection() {
		flicButton.disableFallDetection(true)
		isFallDetectionEnabled = false
		isFallDetectionBusy = false
		fallDetectionError = nil
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

	fileprivate func handleSmallButtonDown() {
		playBuzzer(FlicBuzzerPatterns.abort)
		cancelPendingFallEventByUser()
	}

	fileprivate func handleFallDetectionUpdate(_ event: FLICButtonFallDetectionEvent) {
		switch event.state {
		case .triggered:
			createFallEvent()
			playBuzzer(FlicBuzzerPatterns.awaitingStillnessBlip)

		case .preFallDataCollected:
			let index = ensureActiveFallEvent()
			applyPreFallData(from: event, toFallEventAt: index)
			if fallEvents[index].status != .cancelledByUser {
				fallEvents[index].status = .collectingPostFallData
			}

		case .completed:
			let index = ensureActiveFallEvent()
			applyPreFallData(from: event, toFallEventAt: index)
			applyPostFallData(from: event, toFallEventAt: index)
			fallEvents[index].hasCompletedData = true
			if fallEvents[index].status != .cancelledByUser {
				fallEvents[index].status = .completed
			}
			activeFallEventID = nil

		case .disabled:
			isFallDetectionEnabled = false
			isFallDetectionBusy = false

		@unknown default:
			break
		}
	}

	private func createFallEvent() {
		fallEventSequence += 1
		let event = FallEvent(sequenceNumber: fallEventSequence, triggeredAt: Date())
		fallEvents.insert(event, at: 0)
		activeFallEventID = event.id
	}

	private func ensureActiveFallEvent() -> Int {
		if let activeFallEventID,
		   let index = fallEvents.firstIndex(where: { $0.id == activeFallEventID }) {
			return index
		}

		createFallEvent()
		return 0
	}

	private func cancelPendingFallEventByUser() {
		guard let activeFallEventID,
			  let index = fallEvents.firstIndex(where: { $0.id == activeFallEventID }),
			  fallEvents[index].isAwaitingCompleteCurve else {
			return
		}

		fallEvents[index].status = .cancelledByUser
	}

	private func applyPreFallData(from event: FLICButtonFallDetectionEvent, toFallEventAt index: Int) {
		fallEvents[index].preFallSampleRate = event.preFallSampleRate
		fallEvents[index].preFallExpectedSampleCount = event.preFallExpectedSampleCount
		fallEvents[index].preFallSamples = Self.samples(from: event.preFallAccelerometerData)
	}

	private func applyPostFallData(from event: FLICButtonFallDetectionEvent, toFallEventAt index: Int) {
		fallEvents[index].postFallSampleRate = event.postFallSampleRate
		fallEvents[index].postFallExpectedSampleCount = event.postFallExpectedSampleCount
		fallEvents[index].postFallSamples = Self.samples(from: event.postFallAccelerometerData)
	}

	private static func samples(from data: FLICButtonAccelerometerData) -> [FallDetectionSample] {
		data.points.enumerated().map { offset, point in
			FallDetectionSample(
				id: offset,
				x: Double(point.x),
				y: Double(point.y),
				z: Double(point.z)
			)
		}
	}

	private static func description(for result: FLICButtonEnableAccelerometerStreamingResult) -> String {
		switch result {
		case .success: return "OK"
		case .invalidConfig: return "Invalid accelerometer configuration."
		case .busy: return "The Flic is busy. Please try again."
		case .notReady: return "The Flic is not ready yet. Wait for it to connect."
		case .notSupported: return "Accelerometer streaming is not supported by this Flic."
		case .firmwareUpdateNeeded: return "A firmware update is needed to use this feature."
		@unknown default: return "Failed to enable accelerometer streaming."
		}
	}

	private static func description(for result: FLICButtonEnableFallDetectionResult) -> String {
		switch result {
		case .success: return "OK"
		case .invalidConfig: return "Invalid fall detection configuration."
		case .busy: return "The Flic is busy. Please try again."
		case .notReady: return "The Flic is not ready yet. Wait for it to connect."
		case .notSupported: return "Fall detection is not supported by this Flic."
		case .firmwareUpdateNeeded: return "A firmware update is needed to use fall detection."
		@unknown default: return "Failed to enable fall detection."
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
		model(for: flicButton)?.objectWillChange.send()
	}
	
	func buttonIsReady(_ button: FLICButton) {
		print("buttonIsReady")
		reloadButtons()
	}
	
	func button(_ flicButton: FLICButton, didDisconnectWithError error: Error?) {
		print("didDisconnectWithError", error ?? "")
		model(for: flicButton)?.markDisconnected()
	}
	
	func button(_ flicButton: FLICButton, didReceive buttonEvent: FLICButtonEvent) {
		guard let button = model(for: flicButton) else { return }

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

		buttonEvent.isButtonDown { buttonNumber in
			if buttonNumber == FlicButtonModel.smallButtonNumber {
				button.handleSmallButtonDown()
			}
		}
		
		// update UI button state
		if buttonEvent.eventClass == .upOrDown {
			if (buttonEvent.type == .down) {
				button.downButtons.insert(buttonEvent.buttonNumber)
			} else {
				button.downButtons.remove(buttonEvent.buttonNumber)
			}
		}
	}
	
	func button(_ button: FLICButton, didFailToConnectWithError error: Error?) {
		print("didFailToConnectWithError", error ?? "")
	}

	func button(_ button: FLICButton, didReceive accelerometerData: FLICButtonAccelerometerData) {
		// Route the streamed samples to the matching button model so its detail view can plot them.
		model(for: button)?.appendAccelerometerData(accelerometerData)
	}

	func button(_ button: FLICButton, didUpdateFallDetection event: FLICButtonFallDetectionEvent) {
		model(for: button)?.handleFallDetectionUpdate(event)
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
			let existingButtons = self.buttons
			if let manager = FLICManager.shared() {
				for flicButton in manager.buttons() {
					if let existingButton = existingButtons.first(where: { $0.id == flicButton.identifier }) {
						existingButton.updateButtonReference(flicButton)
						newButtons.append(existingButton)
					} else {
						newButtons.append(FlicButtonModel(flicButton))
					}
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

	private func model(for flicButton: FLICButton) -> FlicButtonModel? {
		buttons.first(where: { $0.flicButton == flicButton || $0.id == flicButton.identifier })
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
