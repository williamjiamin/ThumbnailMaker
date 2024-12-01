import SwiftUI

struct CircularImageCropperView: View {
    @Binding var isPresented: Bool
    let originalImage: UIImage
    let onCropComplete: (UIImage) -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            let circleSize = min(geometry.size.width, geometry.size.height) * 0.8
            
            ZStack {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Text("Drag to Position & Pinch to Zoom")
                        .foregroundColor(.white)
                        .padding()
                    
                    ZStack {
                        Image(uiImage: originalImage)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let delta = value / lastScale
                                            lastScale = value
                                            scale *= delta
                                        }
                                        .onEnded { _ in
                                            lastScale = 1.0
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { value in
                                            lastOffset = offset
                                        }
                                )
                            )
                        
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: circleSize)
                    }
                    .frame(width: circleSize, height: circleSize)
                    .clipped()
                    
                    HStack {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .padding()
                        
                        Button("Confirm") {
                            let cropView = ZStack {
                                GeometryReader { cropGeometry in
                                    Image(uiImage: originalImage)
                                        .resizable()
                                        .scaledToFit()
                                        .scaleEffect(scale)
                                        .offset(offset)
                                        .frame(width: cropGeometry.size.width, height: cropGeometry.size.height)
                                }
                            }
                            .frame(width: circleSize, height: circleSize)
                            .clipShape(Circle())
                            
                            let renderer = ImageRenderer(content: cropView)
                            renderer.scale = 3.0
                            
                            if let croppedImage = renderer.uiImage {
                                onCropComplete(croppedImage)
                                isPresented = false
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
} 
