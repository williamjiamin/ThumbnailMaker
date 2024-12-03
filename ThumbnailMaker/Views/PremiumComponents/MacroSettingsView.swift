import SwiftUI

enum TextFieldFocus {
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Macro Settings (Experimental)")
                .font(.headline)
                .padding(.bottom, 4)
            
            Text("Batch generation allows you to create multiple thumbnails with sequential numbers. For stability, generation is limited to 100 images per batch.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
            
            Text("Tip: Start with a small batch (5-10 images) to test layout consistency. Consider using smaller text size to accommodate number changes.")
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.bottom, 8)
            
            Toggle("Enable Batch Generation", isOn: $macroConfig.isEnabled)
                .padding(.bottom, 8)
                .onChange(of: macroConfig.isEnabled) { oldValue, newValue in
                    if newValue && !hasSelectedImage {
                        macroConfig.isEnabled = false
                        showingAlert = true
                    }
                }
            
            if macroConfig.isEnabled {
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Start Number")
                            .font(.subheadline)
                        TextField("Start", value: $macroConfig.startNumber, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                            .frame(width: 100)
                            .focused($focusedField, equals: .startNumber)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("End Number")
                            .font(.subheadline)
                        TextField("End", value: $macroConfig.endNumber, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                            .frame(width: 100)
                            .focused($focusedField, equals: .endNumber)
                    }
                }
                
                Picker("Number Position", selection: $macroConfig.appendPosition) {
                    ForEach(MacroConfig.AppendPosition.allCases, id: \.self) { position in
                        Text(position.rawValue).tag(position)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            if let message = validationMessage {
                Text(message)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.clear)
        .alert("Image Required", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please select an image first to enable batch generation.")
        }
    }
} 
