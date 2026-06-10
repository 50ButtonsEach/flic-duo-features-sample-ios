//
//  FlicDetailView.swift
//  flic2lib-ios-sample
//
//  Created by Oskar Öberg on 2026-06-10.
//

import SwiftUI
import Charts
import flic2lib

/// Predefined buzzer melodies that can be played on a Flic Duo.
enum FlicBuzzerPatterns {
	static let fallAlert: [(hz: Int32, duration: Float)] = {
		let toneHz: Int32 = 1000
		let blipDuration: Float = 0.12
		let interval: Float = 0.5
		let blipCount = Int(7.0 / Double(interval))
		let silenceDuration = interval - blipDuration
		var notes: [(hz: Int32, duration: Float)] = []

		notes.reserveCapacity((blipCount * 2) + 1)
		for _ in 0..<blipCount {
			notes.append((hz: toneHz, duration: blipDuration))
			if silenceDuration > 0 {
				notes.append((hz: 0, duration: silenceDuration))
			}
		}
		notes.append((hz: toneHz, duration: 3.0))

		return notes
	}()

	static let bigButtonAlarm: [(hz: Int32, duration: Float)] = [
		(hz: 4000, duration: 10.0)
	]

	static let confirm: [(hz: Int32, duration: Float)] = [
		(hz: 1760, duration: 0.06),
		(hz: 0, duration: 0.01),
		(hz: 2217, duration: 0.06),
		(hz: 0, duration: 0.01),
		(hz: 2637, duration: 0.16)
	]

	static let awaitingStillnessBlip: [(hz: Int32, duration: Float)] = [
		(hz: 4000, duration: 0.03),
		(hz: 0, duration: 0.02),
		(hz: 4000, duration: 0.03),
		(hz: 0, duration: 0.02),
		(hz: 4000, duration: 0.03)
	]

	static let abort: [(hz: Int32, duration: Float)] = [
		(hz: 2200, duration: 0.05),
		(hz: 0, duration: 0.015),
		(hz: 1500, duration: 0.08)
	]

	/// A named, selectable buzzer pattern for presentation in the UI.
	struct NamedPattern: Identifiable {
		let id = UUID()
		let name: String
		let notes: [(hz: Int32, duration: Float)]
	}

	/// All patterns offered in the "Play Buzzer Sound" picker, in display order.
	static let all: [NamedPattern] = [
		NamedPattern(name: "Fall Alert", notes: fallAlert),
		NamedPattern(name: "Big Button Alarm", notes: bigButtonAlarm),
		NamedPattern(name: "Confirm", notes: confirm),
		NamedPattern(name: "Awaiting Stillness Blip", notes: awaitingStillnessBlip),
		NamedPattern(name: "Abort", notes: abort)
	]
}

/// Detail screen for a single Flic where you can try out the device features.
/// Currently exposes accelerometer streaming, with buzzer and fall detection to follow.
struct FlicDetailView: View {

	@ObservedObject var button: FlicButtonModel
	@State private var showBuzzerPicker = false

	var body: some View {
		List {
			accelerometerSection
			buzzerSection
		}
		.navigationTitle(button.serialNumber)
		.navigationBarTitleDisplayMode(.inline)
		.onDisappear {
			// Stop streaming when leaving the screen so the Flic doesn't keep sending data.
			if button.isAccelerometerStreaming {
				button.disableAccelerometerStreaming()
			}
		}
	}

	private var isConnected: Bool {
		button.state == .connected
	}

	private var buzzerSection: some View {
		Section {
			Button("Play Buzzer Sound") {
				showBuzzerPicker = true
			}
			.disabled(!isConnected)
			.confirmationDialog("Play Buzzer Sound", isPresented: $showBuzzerPicker, titleVisibility: .visible) {
				ForEach(FlicBuzzerPatterns.all) { pattern in
					Button(pattern.name) {
						button.playBuzzer(pattern.notes)
					}
				}
				Button("Cancel", role: .cancel) {}
			}

			if !isConnected {
				Label("Flic must be connected to play sounds.", systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundColor(.orange)
			}
		} header: {
			Text("Buzzer")
		} footer: {
			Text("Plays a predefined melody on the Flic Duo's buzzer.")
		}
	}

	private var accelerometerSection: some View {
		Section {
			Toggle("Stream accelerometer data", isOn: Binding(
				get: { button.isAccelerometerStreaming },
				set: { enabled in
					if enabled {
						button.enableAccelerometerStreaming()
					} else {
						button.disableAccelerometerStreaming()
					}
				}
			))
			.disabled(button.isAccelerometerBusy || !isConnected)

			if !isConnected {
				Label("Flic must be connected to stream.", systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundColor(.orange)
			}

			if let error = button.accelerometerError {
				Label(error, systemImage: "xmark.octagon")
					.font(.caption)
					.foregroundColor(.red)
			}

			if button.isAccelerometerStreaming {
				accelerometerGraph
			}
		} header: {
			Text("Accelerometer")
		} footer: {
			Text("Live X, Y and Z acceleration streamed from the Flic.")
		}
	}

	@ViewBuilder
	private var accelerometerGraph: some View {
		if button.accelerometerSamples.isEmpty {
			HStack {
				Spacer()
				ProgressView("Waiting for data…")
				Spacer()
			}
			.padding(.vertical)
		} else {
			AccelerometerChart(samples: button.accelerometerSamples)
				.frame(height: 220)
				.padding(.vertical, 8)
		}
	}
}

/// A live line chart of the three accelerometer axes.
struct AccelerometerChart: View {

	let samples: [AccelerometerSample]

	/// Pairs each sample with its position in the current window so the x-axis
	/// always spans 0..<count instead of the ever-growing absolute sample id.
	private var indexedSamples: [(position: Int, sample: AccelerometerSample)] {
		samples.enumerated().map { (position: $0.offset, sample: $0.element) }
	}

	var body: some View {
		Chart {
			ForEach(indexedSamples, id: \.sample.id) { position, sample in
				LineMark(
					x: .value("Sample", position),
					y: .value("Acceleration", sample.x)
				)
				.foregroundStyle(by: .value("Axis", "X"))
			}
			ForEach(indexedSamples, id: \.sample.id) { position, sample in
				LineMark(
					x: .value("Sample", position),
					y: .value("Acceleration", sample.y)
				)
				.foregroundStyle(by: .value("Axis", "Y"))
			}
			ForEach(indexedSamples, id: \.sample.id) { position, sample in
				LineMark(
					x: .value("Sample", position),
					y: .value("Acceleration", sample.z)
				)
				.foregroundStyle(by: .value("Axis", "Z"))
			}
		}
		.chartForegroundStyleScale(domain: ["X", "Y", "Z"], range: [Color.red, Color.green, Color.blue])
		.chartXAxis(.hidden)
		.chartLegend(position: .top)
	}
}

#Preview {
	AccelerometerChart(samples: (0..<120).map { i in
		let t = Double(i) / 10
		return AccelerometerSample(id: i, x: sin(t), y: cos(t) * 0.6, z: 1 + sin(t * 0.5) * 0.2)
	})
	.frame(height: 220)
	.padding()
}
