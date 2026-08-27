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
	typealias Note = (hz: Float, duration: UInt16)

	static let fallAlert: [Note] = {    
		let toneHz: Float = 1_000
		let blipDuration: UInt16 = 120
		let interval: UInt16 = 500
		let blipCount = 7_000 / Int(interval)
		let silenceDuration = interval - blipDuration
		var notes: [Note] = []

		notes.reserveCapacity((blipCount * 2) + 1)
		for _ in 0..<blipCount {
			notes.append((hz: toneHz, duration: blipDuration))
			if silenceDuration > 0 {
				notes.append((hz: 0, duration: silenceDuration))
			}
		}
		notes.append((hz: toneHz, duration: 3_000))

		return notes
	}()

	static let bigButtonAlarm: [Note] = [
		(hz: 4_000, duration: 10_000)
	]

	static let confirm: [Note] = [
		(hz: 1_760, duration: 60),
		(hz: 0, duration: 10),
		(hz: 2_217, duration: 60),
		(hz: 0, duration: 10),
		(hz: 2_637, duration: 160)
	]

	static let awaitingStillnessBlip: [Note] = [
		(hz: 4_000, duration: 30),
		(hz: 0, duration: 20),
		(hz: 4_000, duration: 30),
		(hz: 0, duration: 20),
		(hz: 4_000, duration: 30)
	]

	static let abort: [Note] = [
		(hz: 2_200, duration: 50),
		(hz: 0, duration: 15),
		(hz: 1_500, duration: 80)
	]

	/// A named, selectable buzzer pattern for presentation in the UI.
	struct NamedPattern: Identifiable {
		let id = UUID()
		let name: String
		let notes: [Note]
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
struct FlicDetailView: View {

	@ObservedObject var button: FlicButtonModel
	@State private var showBuzzerPicker = false
	@State private var showFallDetectionSettings = false

	var body: some View {
		List {
			connectionSection
			accelerometerSection
			fallDetectionSection
			buzzerSection
		}
		.navigationTitle(button.serialNumber)
		.navigationBarTitleDisplayMode(.inline)
		.sheet(isPresented: $showFallDetectionSettings) {
			FallDetectionSettingsView(settings: $button.fallDetectionSettings)
		}
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

	private var connectionSection: some View {
		Section {
			HStack(spacing: 12) {
				Image(systemName: "circle.fill")
					.font(.caption)
					.foregroundColor(connectionStatusColor)

				Text(connectionStatusText)
					.font(.body)

				buttonDownIndicators

				Spacer()

				Button {
					button.toggleConnection()
				} label: {
					Image(systemName: button.connectionActionSystemImage)
						.imageScale(.large)
						.frame(width: 32, height: 32)
				}
				.buttonStyle(.borderless)
				.disabled(button.isConnectionActionDisabled)
				.accessibilityLabel(button.connectionActionTitle)
			}
		}
	}

	private var buttonDownIndicators: some View {
		HStack(spacing: 4) {
			if button.downButtons.contains(0) {
				Image(systemName: "circle.fill")
			} else {
				Image(systemName: "circle")
			}

			if button.isDuo {
				if button.downButtons.contains(1) {
					Image(systemName: "circle.fill")
				} else {
					Image(systemName: "circle")
				}
			}
		}
		.font(.caption)
		.foregroundColor(.secondary)
	}

	private var connectionStatusColor: Color {
		button.state == .connected ? .green : .yellow
	}

	private var connectionStatusText: String {
		switch button.state {
		case .connected:
			return "Connected"
		case .connecting:
			return "Connecting"
		case .disconnecting:
			return "Disconnecting"
		case .disconnected:
			return "Disconnected"
		@unknown default:
			return "Unknown"
		}
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

	private var fallDetectionSection: some View {
		Section {
			HStack(spacing: 12) {
				Toggle("Enable fall detection", isOn: Binding(
					get: { button.isFallDetectionEnabled },
					set: { enabled in
						if enabled {
							button.enableFallDetection()
						} else {
							button.disableFallDetection()
						}
					}
				))
				.disabled(button.isMotionFeatureBusy || !isConnected)

				Button {
					showFallDetectionSettings = true
				} label: {
					Image(systemName: "gearshape")
						.imageScale(.large)
				}
				.buttonStyle(.borderless)
				.disabled(button.isFallDetectionEnabled || button.isFallDetectionBusy)
				.accessibilityLabel("Fall detection settings")
			}

			if !isConnected {
				Label("Flic must be connected to enable fall detection.", systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundColor(.orange)
			}

			if let error = button.fallDetectionError {
				Label(error, systemImage: "xmark.octagon")
					.font(.caption)
					.foregroundColor(.red)
			}

			if button.fallEvents.isEmpty {
				Text("No fall events")
					.font(.caption)
					.foregroundColor(.secondary)
			} else {
				ForEach(button.fallEvents) { event in
					FallEventRow(event: event)
				}
			}
		} header: {
			Text("Fall Detection")
		} footer: {
			Text("Events and settings are kept in memory for the current app session.")
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
			.disabled(button.isMotionFeatureBusy || !isConnected)

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

struct FallDetectionSettingsView: View {

	@Binding var settings: FallDetectionSettings
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			Form {
				Section("Low-G") {
					uint16Stepper(
						"Threshold",
						value: uint16Binding(\.lowGThresholdMg),
						unit: "mg",
						range: 100...4000,
						step: 50
					)
					uint16Stepper(
						"Duration",
						value: uint16Binding(\.lowGDurationMs),
						unit: "ms",
						range: 10...2000,
						step: 10
					)
				}

				Section("High-G") {
					uint16Stepper(
						"Timeout",
						value: uint16Binding(\.highGTimeoutMs),
						unit: "ms",
						range: 100...5000,
						step: 50
					)
					uint16Stepper(
						"Threshold",
						value: uint16Binding(\.highGThresholdMg),
						unit: "mg",
						range: 500...16000,
						step: 100
					)
					uint16Stepper(
						"Time window",
						value: uint16Binding(\.highGTimeWindowMs),
						unit: "ms",
						range: 10...1000,
						step: 10
					)
				}

				Section("Post Event") {
					uint16Stepper(
						"Record duration",
						value: uint16Binding(\.postEventRecordDurationMs),
						unit: "ms",
						range: 1000...30000,
						step: 1000
					)
				}

				Section("Accelerometer") {
					Picker("Full-scale selection", selection: $settings.fullScaleSelection) {
						ForEach(FallDetectionFullScaleOption.all) { option in
							Text(option.title).tag(option.selection)
						}
					}
				}
			}
			.navigationTitle("Fall Settings")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") {
						dismiss()
					}
				}
				ToolbarItem(placement: .primaryAction) {
					Button("Reset") {
						settings = .default
					}
				}
			}
		}
	}

	private func uint16Binding(_ keyPath: WritableKeyPath<FallDetectionSettings, UInt16>) -> Binding<Int> {
		Binding(
			get: { Int(settings[keyPath: keyPath]) },
			set: { settings[keyPath: keyPath] = UInt16(clamping: $0) }
		)
	}

	private func uint16Stepper(
		_ title: String,
		value: Binding<Int>,
		unit: String,
		range: ClosedRange<Int>,
		step: Int
	) -> some View {
		intStepper(title, value: value, unit: unit, range: range, step: step)
	}

	private func intStepper(
		_ title: String,
		value: Binding<Int>,
		unit: String,
		range: ClosedRange<Int>,
		step: Int
	) -> some View {
		Stepper(value: value, in: range, step: step) {
			HStack {
				Text(title)
				Spacer()
				Text(valueText(value.wrappedValue, unit: unit))
					.foregroundColor(.secondary)
					.monospacedDigit()
			}
		}
	}

	private func valueText(_ value: Int, unit: String) -> String {
		if unit.isEmpty {
			return "\(value)"
		}

		return "\(value) \(unit)"
	}
}

private struct FallDetectionFullScaleOption: Identifiable {
	let id: String
	let title: String
	let selection: FLICButtonAccelerometerFullScaleSelection

	static let all: [FallDetectionFullScaleOption] = [
		FallDetectionFullScaleOption(id: "twoG", title: "2 g", selection: .twoG),
		FallDetectionFullScaleOption(id: "fourG", title: "4 g", selection: .fourG),
		FallDetectionFullScaleOption(id: "eightG", title: "8 g", selection: .eightG),
		FallDetectionFullScaleOption(id: "sixteenG", title: "16 g", selection: .sixteenG)
	]
}

struct FallEventRow: View {

	let event: FallEvent

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .firstTextBaseline) {
				Text("Fall")
					.font(.headline)

				Spacer()

				Text(event.status.title)
					.font(.caption)
					.fontWeight(.semibold)
					.foregroundColor(statusColor)
			}

			Text(event.triggeredAt, format: .dateTime.hour().minute().second())
				.font(.caption)
				.foregroundColor(.secondary)

			FallEventGraph(event: event)

			if let sampleSummary = event.sampleSummary {
				Text(sampleSummary)
					.font(.caption2)
					.foregroundColor(.secondary)
					.monospacedDigit()
			}
		}
		.padding(.vertical, 6)
	}

	private var statusColor: Color {
		switch event.status {
		case .triggered, .collectingPostFallData:
			return .orange
		case .completed:
			return .green
		case .cancelledByUser:
			return .red
		}
	}
}

struct FallEventGraph: View {

	let event: FallEvent

	var body: some View {
		ZStack(alignment: .topTrailing) {
			if event.graphSeriesPoints.isEmpty {
				RoundedRectangle(cornerRadius: 8)
					.fill(Color.secondary.opacity(0.08))
					.frame(height: 160)
			} else {
				FallDetectionChart(event: event)
					.frame(height: 180)
			}

			if event.isAwaitingCompleteCurve {
				Text("Pending...")
					.font(.caption)
					.fontWeight(.semibold)
					.foregroundColor(.secondary)
					.padding(8)
			}
		}
		.padding(.top, 4)
	}
}

struct FallDetectionChart: View {

	let event: FallEvent

	var body: some View {
		Chart {
			ForEach(event.graphSeriesPoints) { point in
				LineMark(
					x: .value("Seconds from impact", point.timeSeconds),
					y: .value("Acceleration", point.value)
				)
				.foregroundStyle(by: .value("Channel", point.series.title))
				.interpolationMethod(.catmullRom)
			}

			RuleMark(x: .value("Impact", 0))
				.foregroundStyle(Color.secondary)
				.lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
		}
		.chartForegroundStyleScale(
			domain: FallGraphSeries.allCases.map(\.title),
			range: [Color.red, Color.green, Color.blue, Color.secondary]
		)
		.chartLegend(position: .top)
		.chartXAxisLabel("Seconds from impact")
		.chartYAxisLabel("Acceleration")
	}
}

private enum FallGraphSeries: CaseIterable {
	case x
	case y
	case z
	case magnitude

	var title: String {
		switch self {
		case .x: return "X"
		case .y: return "Y"
		case .z: return "Z"
		case .magnitude: return "Magnitude"
		}
	}
}

private struct FallGraphPoint: Identifiable {
	let id: String
	let timeSeconds: Double
	let value: Double
	let series: FallGraphSeries
}

private extension FallEvent {

	var graphSeriesPoints: [FallGraphPoint] {
		preFallGraphPoints + postFallGraphPoints
	}

	var sampleSummary: String? {
		var parts: [String] = []

		if let preFallSampleRate {
			parts.append(sampleSummaryPart(
				title: "Pre",
				count: preFallSamples.count,
				expectedCount: preFallExpectedSampleCount,
				sampleRate: preFallSampleRate
			))
		}

		if let postFallSampleRate {
			parts.append(sampleSummaryPart(
				title: "Post",
				count: postFallSamples.count,
				expectedCount: postFallExpectedSampleCount,
				sampleRate: postFallSampleRate
			))
		}

		if parts.isEmpty {
			return nil
		}

		return parts.joined(separator: " | ")
	}

	private var preFallGraphPoints: [FallGraphPoint] {
		guard let preFallSampleRate, preFallSampleRate > 0 else { return [] }

		let interval = 1.0 / Double(preFallSampleRate)
		let sampleCount = preFallSamples.count

		return preFallSamples.enumerated().flatMap { index, sample in
			graphPoints(
				idPrefix: "pre-\(index)",
				timeSeconds: -Double(sampleCount - 1 - index) * interval,
				sample: sample
			)
		}
	}

	private var postFallGraphPoints: [FallGraphPoint] {
		guard let postFallSampleRate, postFallSampleRate > 0 else { return [] }

		let interval = 1.0 / Double(postFallSampleRate)

		return postFallSamples.enumerated().flatMap { index, sample in
			graphPoints(
				idPrefix: "post-\(index)",
				timeSeconds: Double(index) * interval,
				sample: sample
			)
		}
	}

	private func graphPoints(
		idPrefix: String,
		timeSeconds: Double,
		sample: FallDetectionSample
	) -> [FallGraphPoint] {
		[
			FallGraphPoint(id: "\(idPrefix)-x", timeSeconds: timeSeconds, value: sample.x, series: .x),
			FallGraphPoint(id: "\(idPrefix)-y", timeSeconds: timeSeconds, value: sample.y, series: .y),
			FallGraphPoint(id: "\(idPrefix)-z", timeSeconds: timeSeconds, value: sample.z, series: .z),
			FallGraphPoint(id: "\(idPrefix)-magnitude", timeSeconds: timeSeconds, value: sample.magnitude, series: .magnitude)
		]
	}

	private func sampleSummaryPart(
		title: String,
		count: Int,
		expectedCount: UInt16?,
		sampleRate: UInt16
	) -> String {
		let expectedText = expectedCount.map { "/\($0)" } ?? ""
		return "\(title) \(count)\(expectedText) @ \(sampleRate) Hz"
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
