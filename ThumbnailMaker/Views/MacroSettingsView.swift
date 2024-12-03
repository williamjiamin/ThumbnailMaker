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
                VStack(alignment: .leading, spacing: 16) {
                    // Main content section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Generate multiple thumbnails with sequential numbers (max 100)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Toggle("Enable Batch Generation", isOn: $macroConfig.isEnabled)
                            .padding(.vertical, 4)
                            .onChange(of: macroConfig.isEnabled) { oldValue, newValue in
                                if newValue && !hasSelectedImage {
                                    macroConfig.isEnabled = false
                                    showingAlert = true
                                }
                            }
                        
                        if macroConfig.isEnabled {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Start")
                                        .font(.subheadline)
                                    TextField("Start", value: $macroConfig.startNumber, format: .number)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .keyboardType(.numberPad)
                                        .frame(width: 80)
                                        .focused($focusedField, equals: .startNumber)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("End")
                                        .font(.subheadline)
                                    TextField("End", value: $macroConfig.endNumber, format: .number)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .keyboardType(.numberPad)
                                        .frame(width: 80)
                                        .focused($focusedField, equals: .endNumber)
                                }
                            }
                            
                            Picker("Number Position", selection: $macroConfig.appendPosition) {
                                ForEach(MacroConfig.AppendPosition.allCases, id: \.self) { position in
                                    Text(position.rawValue).tag(position)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.top, 4)
                        }
                        
                        if let message = validationMessage {
                            Text(message)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    .padding()
                }
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
            .safeAreaInset(edge: .bottom) {
                if focusedField != nil {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                        .padding()
                    }
                    .background(.bar)
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