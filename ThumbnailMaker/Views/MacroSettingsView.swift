import SwiftUI

enum TextFieldFocus: Hashable {
    case overlayText
    case startNumber
    case endNumber
}

struct MacroSettingsView: View {
    @Binding var macroConfig: MacroConfig
    let hasSelectedImage: Bool
    let baseText: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingAlert = false
    @State private var attemptedDismiss = false
    
    private let maxRange = 100
    
    private var isValidRange: Bool {
        abs(macroConfig.endNumber - macroConfig.startNumber) + 1 <= maxRange
    }
    
    private var canDismiss: Bool {
        !macroConfig.isEnabled || isValidRange
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Enable Batch Generation", isOn: $macroConfig.isEnabled)
                    
                    if macroConfig.isEnabled {
                        HStack {
                            Text("Start")
                            TextField("Start", value: $macroConfig.startNumber, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        HStack {
                            Text("End")
                            TextField("End", value: $macroConfig.endNumber, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        if !isValidRange {
                            Text("Range cannot exceed 100 images")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        Picker("Number Position", selection: $macroConfig.appendPosition) {
                            ForEach(MacroConfig.AppendPosition.allCases, id: \.self) { position in
                                Text(position.rawValue).tag(position)
                            }
                        }
                        
                        // Preview of first and last result
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("First: \(previewText(number: macroConfig.startNumber))")
                                .font(.caption)
                            Text("Last: \(previewText(number: macroConfig.endNumber))")
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Batch Settings")
                } footer: {
                    Text("Generate up to 100 images with sequential numbering")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Experimental Feature")
                                .font(.title3)
                                .foregroundColor(.orange)
                            Image(systemName: "flask.fill")
                                .foregroundColor(.orange)
                        }
                        
                        Text("Tips & Guidelines:")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Start with 5 images to test your layout")
                            Text("• Numbers may affect text positioning")
                            Text("• Use smaller font size for longer numbers")
                            Text("• Processing time varies by device")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        
                        Divider()
                        
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Important:")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                        
                        Text("Please stay on this page while generating batch images. Leaving the page will interrupt the process and lose progress.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Batch Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        if canDismiss {
                            dismiss()
                        } else {
                            attemptedDismiss = true
                        }
                    }
                    .foregroundColor(canDismiss ? .blue : .gray)
                }
            }
            .alert("Invalid Range", isPresented: $attemptedDismiss) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please adjust the range to generate no more than 100 images.")
            }
        }
        .alert("Image Required", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please select an image first to enable batch generation.")
        }
        .interactiveDismissDisabled(!canDismiss)
    }
    
    private func previewText(number: Int) -> String {
        macroConfig.appendPosition == .after ?
            "\(baseText) \(number)" : "\(number) \(baseText)"
    }
}