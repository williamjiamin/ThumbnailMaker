import SwiftUI

struct MacroSettingsView: View {
    @Binding var macroConfig: MacroConfig
    let hasSelectedImage: Bool
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
            Text("Macro Settings")
                .font(.headline)
                .padding(.bottom, 4)
            
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
                    }
                    
                    VStack(alignment: .leading) {
                        Text("End Number")
                            .font(.subheadline)
                        TextField("End", value: $macroConfig.endNumber, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                            .frame(width: 100)
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
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .alert("Image Required", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please select an image first to enable batch generation.")
        }
    }
} 
