//
//  ContentView.swift
//  flic2lib-ios-sample
//
//  Created by Oskar Öberg on 2024-02-09.
//

import SwiftUI
import flic2lib

struct FlicListView: View {
    
    @StateObject var viewModel = FlicListViewModel()
    
    var body: some View {
		NavigationStack {
			VStack {
				if viewModel.buttons.isEmpty {
					emptyStateView
				} else {
					buttonListView
				}

				scanSectionView
			}
			.navigationTitle("Flics")
		}
    }
    
    private var emptyStateView: some View {
        List {
            HStack {
                Spacer()
                Text("No Flics connected")
                    .foregroundColor(.gray)
                Spacer()
            }
        }
    }
    
    private var buttonListView: some View {
        List {
            ForEach(viewModel.buttons) { button in
                NavigationLink {
                    FlicDetailView(button: button)
                } label: {
                    FlicButtonRow(button: button, onRemove: {
                        viewModel.buttonToBeRemoved = button
                        viewModel.promptToRemoveButton = true
                    })
                }
            }
        }
        .alert(isPresented: $viewModel.promptToRemoveButton) {
            Alert(
                title: Text("Remove Flic"),
                message: Text("Do you want to remove this button?"),
                primaryButton: .destructive(Text("Remove")) {
                    if let button = viewModel.buttonToBeRemoved {
                        viewModel.removeButton(button)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var scanSectionView: some View {
        VStack {
            if viewModel.isScanning {
                HStack {
                    Text(scanStatusText(for: viewModel.scanState))
                    Spacer().frame(width: 10)
                    ProgressView()
                }
                .padding()
			} else {
				Button(action: {
					print("start scan");
					viewModel.scan()
				}) {
					Text("Add Flic")
					Image(systemName: "plus.circle")
						.resizable()
						.aspectRatio(contentMode: .fit)
						.foregroundColor(.blue)
						.frame(width: 20)
				}
				.padding()
			}
        }
        .alert(item: Binding<AlertError?>(
            get: { viewModel.scanError.map { AlertError(message: $0) } },
            set: { _ in viewModel.scanError = nil }
        )) { alertError in
            Alert(title: Text("Error"), message: Text(alertError.message), dismissButton: .default(Text("OK")))
        }
    }
    
    struct AlertError: Identifiable {
        let id = UUID()
        let message: String
    }
    
    private func scanStatusText(for state: FLICButtonScannerStatusEvent?) -> String {
        switch state {
        case .discovered: return "Discovered..."
        case .connected: return "Connected..."
        case .verified: return "Verified!"
        case .verificationFailed: return "Verification failed"
        case nil: return "Looking for buttons..."
        @unknown default: return "Scanning..."
        }
    }
}

struct FlicButtonRow: View {
    @ObservedObject var button: FlicButtonModel
    var onRemove: () -> Void
    
	var body: some View {
        HStack {
			Image(systemName: "circle.fill")
				.foregroundColor(button.state == .connected ? .green : .yellow)
            
			Text(button.serialNumber)
			
			Group {
				if button.downButtons.contains(0) {
					Image(systemName: "circle.fill")
				} else {
					Image(systemName: "circle")
				}
			}
			.font(.caption)
			
			if button.isDuo {
				Group {
					 if button.downButtons.contains(1) {
						Image(systemName: "circle.fill")
					} else {
						Image(systemName: "circle")
					}
				}
				.font(.caption)
			}
			
			Spacer()
            
            Button(action: onRemove) {
                 Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
    }
}

#Preview {
    FlicListView(viewModel: FlicListViewModel(isPreview: true))
}
