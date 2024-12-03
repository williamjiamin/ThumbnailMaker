import SwiftUI

enum TextFieldFocus: Hashable {
    case overlayText
    case startNumber
    case endNumber
}

struct MacroSettingsView: View {
    @Binding var macroConfig: MacroConfig
    let hasSelectedImage: Bool
    @FocusState var focusedField: TextFieldFocus?
    @Environment(\.dismiss) private var dismiss
    @State private var showingAlert = false
    @State private var baseText: String
    
    init(macroConfig: Binding<MacroConfig>, hasSelectedImage: Bool, baseText: String) {
        self._macroConfig = macroConfig
        self.hasSelectedImage = hasSelectedImage
        self._baseText = State(initialValue: baseText)
    }
    
    var previewText: String {
        guard macroConfig.isEnabled else { return baseText }
        let number = macroConfig.startNumber
        return macroConfig.appendPosition == .after ?
            "\(baseText) \(number)" : "\(number) \(baseText)"
    }
    
    var validationMessage: String? {
        if macroConfig.isEnabled {
            let difference = abs(macroConfig.endNumber - macroConfig.startNumber)
            if difference >= 100 {
                return "Maximum batch size is 100 images"
            }
        }
        return nil
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Main Toggle
                    Toggle("Enable Batch Generation", isOn: $macroConfig.isEnabled)
                        .padding()
                        .background(Color(uiColor: .systemGray6))
                        .cornerRadius(12)
                        .onChange(of: macroConfig.isEnabled) { oldValue, newValue in
                            if newValue && !hasSelectedImage {
                                macroConfig.isEnabled = false
                                showingAlert = true
                            }
                        }
                    
                    if macroConfig.isEnabled {
                        // Number Configuration Section
                        GroupBox(label: Text("Number Configuration").fontWeight(.medium)) {
                            VStack(alignment: .leading, spacing: 16) {
                                // Range inputs
                                HStack(spacing: 20) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Start")
                                            .font(.subheadline)
                                        TextField("Start", value: $macroConfig.startNumber, format: .number)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .keyboardType(.numberPad)
                                            .frame(width: 100)
                                            .focused($focusedField, equals: .startNumber)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("End")
                                            .font(.subheadline)
                                        TextField("End", value: $macroConfig.endNumber, format: .number)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .keyboardType(.numberPad)
                                            .frame(width: 100)
                                            .focused($focusedField, equals: .endNumber)
                                    }
                                }
                                
                                // Position selector
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Position")
                                        .font(.subheadline)
                                    Picker("", selection: $macroConfig.appendPosition) {
                                        ForEach(MacroConfig.AppendPosition.allCases, id: \.self) { position in
                                            Text(position.rawValue).tag(position)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 200)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .padding(.horizontal)
                        
                        // Preview Section
                        GroupBox(label: Text("Preview").fontWeight(.medium)) {
                            Text(previewText)
                                .padding(.vertical, 8)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        // Information Section
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Experimental Feature")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Image(systemName: "flask.fill")
                                        .foregroundColor(.orange)
                                }
                                
                                Text("Tips & Guidelines:")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• Start with 5 images to test your layout")
                                    Text("• Numbers may affect text positioning")
                                    Text("• Use smaller font size for longer numbers")
                                    Text("• Processing time varies by device")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } label: {
                            Text("Important Information")
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Batch Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Image Required", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please select an image first to enable batch generation.")
        }
    }
}