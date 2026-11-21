//
//  PremiumPreviewComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/30.
//

import SwiftUI

struct PremiumPreviewComponentView: View {
    @Binding var premiumMakerConfiguration: PremiumMakerConfigurationModel
    @State private var activeSnapGuide: CenterSnapGuide = []
    @GestureState private var isTextDragging = false
    @GestureState private var textDragTranslation: CGSize = .zero
    @GestureState private var textRotationDelta: Angle = .zero
    @GestureState private var textHandleRotationDelta: Double = 0
    @GestureState private var textResizeTranslation: CGSize = .zero
    @GestureState private var isProfileDragging = false
    @GestureState private var profileDragTranslation: CGSize = .zero
    @GestureState private var profileHandleRotationDelta: Double = 0
    @GestureState private var profileResizeTranslation: CGSize = .zero
    @GestureState private var isContentDragging = false
    @GestureState private var contentDragTranslation: CGSize = .zero
    @GestureState private var contentRotationDelta: Angle = .zero
    @GestureState private var contentHandleRotationDelta: Double = 0
    @GestureState private var contentResizeTranslation: CGSize = .zero
    private let selectedOverlay: Binding<ThumbnailLayerSelection>
    let width: CGFloat
    let height: CGFloat
    var isInteractive: Bool
    var safeZone: ThumbnailSafeZone?
    var fallbackStateDidChange: ((Bool) -> Void)? = nil
    private static let canvasCoordinateSpace = "premiumPreviewCanvas"
    private static let textSizeLimits: ClosedRange<CGFloat> = 0.08...0.34
    private static let profileSizeLimits: ClosedRange<CGFloat> = 0.1...0.3
    private static let accessibilityRotationStep = 5.0
    private static let accessibilitySizeStep: CGFloat = 0.02
    private static let accessibilityMoveStep: CGFloat = 0.02
    private static let canvasDragMinimumDistance: CGFloat = 2

    init(
        premiumMakerConfiguration: Binding<PremiumMakerConfigurationModel>,
        width: CGFloat,
        height: CGFloat,
        isInteractive: Bool = false,
        safeZone: ThumbnailSafeZone? = nil,
        selectedOverlay: Binding<ThumbnailLayerSelection> = .constant(.textOverlay),
        fallbackStateDidChange: ((Bool) -> Void)? = nil
    ) {
        self._premiumMakerConfiguration = premiumMakerConfiguration
        self.width = width
        self.height = height
        self.isInteractive = isInteractive
        self.safeZone = safeZone
        self.selectedOverlay = selectedOverlay
        self.fallbackStateDidChange = fallbackStateDidChange
    }

    init(
        premiumMakerConfiguration: PremiumMakerConfigurationModel,
        width: CGFloat,
        height: CGFloat,
        isInteractive: Bool = false,
        safeZone: ThumbnailSafeZone? = nil,
        selectedOverlay: Binding<ThumbnailLayerSelection> = .constant(.textOverlay),
        fallbackStateDidChange: ((Bool) -> Void)? = nil
    ) {
        self._premiumMakerConfiguration = .constant(premiumMakerConfiguration)
        self.width = width
        self.height = height
        self.isInteractive = isInteractive
        self.safeZone = safeZone
        self.selectedOverlay = selectedOverlay
        self.fallbackStateDidChange = fallbackStateDidChange
    }
    
    var body: some View {
        thumbnailContent
    }
    
    @ViewBuilder
    private var thumbnailContent: some View {
        ZStack {
            ThumbnailBackgroundFillView( // SHELL: solid or gradient, same on export
                fill: premiumMakerConfiguration.backgroundFill,
                color: premiumMakerConfiguration.backgroundColor
            )
            
            if let image = premiumMakerConfiguration.selectedImage {
                // FEATURE-03: framed by the shared, non-destructive recipe solver.
                Image(uiImage: ThumbnailCutoutImageCache.shared.resolvedImage( // FEATURE-11
                    image: image,
                    identity: ThumbnailDocumentLayer.backgroundID,
                    mask: premiumMakerConfiguration.layers.cutout(forLayerID: ThumbnailDocumentLayer.backgroundID)
                ))
                    .framed(ThumbnailImageGeometry.solve(
                        sourceSize: image.size,
                        frameSize: CGSize(width: width, height: height),
                        recipe: premiumMakerConfiguration.imageRecipe
                    ))
                    .thumbnailAdjustments( // FEATURE-14
                        premiumMakerConfiguration.layers.renderAdjustments(forLayerID: ThumbnailDocumentLayer.backgroundID),
                        renderedSize: CGSize(width: width, height: height)
                    )
                    .accessibilityLabel("Selected thumbnail image")
            } else if premiumMakerConfiguration.overlayText.isEmpty
                && !premiumMakerConfiguration.layers.hasContentLayers {
                VStack(spacing: placeholderSpacing) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: placeholderIconSize))
                        .foregroundColor(.accessibleSecondaryText)
                    Text("Select an Image")
                        .font(.system(size: placeholderTextSize, weight: .semibold))
                        .foregroundColor(.accessibleSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.center)
                }
                .padding(placeholderPadding)
            }
            
            ForEach(renderableLayerRecords) { layer in
                renderedLayer(layer)
                    .zIndex(Double(layer.zIndex))
            }

            if let safeZone {
                SafeZoneOverlayView(
                    safeZone: safeZone,
                    width: width,
                    height: height
                )
                .allowsHitTesting(false)
            }

            CenterAlignmentGuideView(
                guide: activeSnapGuide,
                width: width,
                height: height
            )
            .zIndex(10_000)

            selectedManipulationChrome
                .zIndex(20_000)
        }
        .frame(width: width, height: height)
        .clipped()
        .coordinateSpace(name: Self.canvasCoordinateSpace)
        .onPreferenceChange(CenterSnapGuidePreferenceKey.self) { guide in
            activeSnapGuide = guide
        }
    }

    @ViewBuilder
    private func renderedLayer(_ layer: ThumbnailDocumentLayer) -> some View {
        if layer.id == ThumbnailDocumentLayer.profileID {
            profileLayer
        } else if layer.id == ThumbnailDocumentLayer.textID {
            textWithFont
        } else if case .image(let content) = layer.content {
            let isSelected = selectedOverlay.wrappedValue == .content(layer.id)
            ContentImageLayerCanvasItem(
                layer: layer,
                width: width,
                height: height,
                isInteractive: isInteractive,
                isSelected: isSelected,
                isDragging: isSelected && isContentDragging,
                dragTranslation: isSelected ? contentDragTranslation : .zero,
                rotationDelta: isSelected ? contentRotationDelta : .zero,
                handleRotationDelta: isSelected ? contentHandleRotationDelta : 0,
                resizeTranslation: isSelected ? contentResizeTranslation : .zero,
                select: {
                    selectedOverlay.wrappedValue = .content(layer.id)
                },
                dragGesture: imageContentDragGesture(layerID: layer.id, content: content),
                rotationGesture: imageContentRotationGesture(layerID: layer.id, content: content),
                updateContent: { nextContent in
                    premiumMakerConfiguration.layers.updateImageContent(id: layer.id) { content in
                        content = nextContent
                    }
                }
            )
        } else if case .text(let content) = layer.content {
            let isSelected = selectedOverlay.wrappedValue == .content(layer.id)
            ContentTextLayerCanvasItem(
                layer: layer,
                width: width,
                height: height,
                isInteractive: isInteractive,
                isSelected: isSelected,
                isDragging: isSelected && isContentDragging,
                dragTranslation: isSelected ? contentDragTranslation : .zero,
                rotationDelta: isSelected ? contentRotationDelta : .zero,
                handleRotationDelta: isSelected ? contentHandleRotationDelta : 0,
                resizeTranslation: isSelected ? contentResizeTranslation : .zero,
                select: {
                    selectedOverlay.wrappedValue = .content(layer.id)
                },
                dragGesture: textContentDragGesture(layerID: layer.id, content: content),
                rotationGesture: textContentRotationGesture(layerID: layer.id, content: content),
                updateContent: { nextContent in
                    premiumMakerConfiguration.layers.updateTextContent(id: layer.id) { content in
                        content = nextContent
                    }
                }
            )
        } else if case .shape(let content) = layer.content {
            let isSelected = selectedOverlay.wrappedValue == .content(layer.id)
            ContentShapeLayerCanvasItem(
                layer: layer,
                width: width,
                height: height,
                isInteractive: isInteractive,
                isSelected: isSelected,
                isDragging: isSelected && isContentDragging,
                dragTranslation: isSelected ? contentDragTranslation : .zero,
                rotationDelta: isSelected ? contentRotationDelta : .zero,
                handleRotationDelta: isSelected ? contentHandleRotationDelta : 0,
                resizeTranslation: isSelected ? contentResizeTranslation : .zero,
                select: {
                    selectedOverlay.wrappedValue = .content(layer.id)
                },
                dragGesture: shapeContentDragGesture(layerID: layer.id, content: content),
                rotationGesture: shapeContentRotationGesture(layerID: layer.id, content: content),
                updateContent: { nextContent in
                    premiumMakerConfiguration.layers.updateShapeContent(id: layer.id) { content in
                        content = nextContent
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var textWithFont: some View {
        let text = premiumMakerConfiguration.overlayText
        if !text.isEmpty && isTextLayerVisible {
            let fontSize = overlayFontSize(for: text) // GAPS: main-title auto-fit

            let needsFallback = FontManager.shared.needsFallback(
                for: text,
                selectedFont: premiumMakerConfiguration.selectedFont
            )

            // FEATURE-04: one styled renderer; nil style == the legacy look.
            let textLayer = StyledThumbnailTextView.overlay(
                text: text,
                font: premiumMakerConfiguration.selectedFont,
                color: premiumMakerConfiguration.textColor,
                fontSize: fontSize,
                style: premiumMakerConfiguration.textStyle,
                canvasSize: CGSize(width: width, height: height)
            )
                .accessibilityIdentifier(isInteractive ? "overlayTextLayer" : "overlayTextPreviewLayer")
                .accessibilityValue(
                    premiumMakerConfiguration.textTransform.canvasStateDescription(size: effectiveTextSize)
                )
                .onAppear { fallbackStateDidChange?(needsFallback) }
                .onChange(of: needsFallback) { oldValue, newValue in
                    fallbackStateDidChange?(newValue)
                }
                .rotationEffect(
                    .degrees(
                        premiumMakerConfiguration.textTransform.rotationDegrees
                            + textRotationDelta.degrees
                            + textHandleRotationDelta
                    )
                )
                .scaleEffect(
                    x: premiumMakerConfiguration.textTransform.isFlippedHorizontally ? -1 : 1,
                    y: 1
                )
                .position(textLayerPosition)
                .preference(key: CenterSnapGuidePreferenceKey.self, value: textSnapGuide)

            if isInteractive {
                let selectableTextLayer = textLayer
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(.isButton)
                    .simultaneousGesture(TapGesture().onEnded {
                        selectedOverlay.wrappedValue = .textOverlay
                    })

                if isTextLayerLocked {
                    selectableTextLayer
                } else {
                    selectableTextLayer
                        .overlayMoveAccessibilityActions(
                            moveUp: {
                                nudgeTextOverlay(dx: 0, dy: -Self.accessibilityMoveStep)
                            },
                            moveDown: {
                                nudgeTextOverlay(dx: 0, dy: Self.accessibilityMoveStep)
                            },
                            moveLeft: {
                                nudgeTextOverlay(dx: -Self.accessibilityMoveStep, dy: 0)
                            },
                            moveRight: {
                                nudgeTextOverlay(dx: Self.accessibilityMoveStep, dy: 0)
                            }
                        )
                        .gesture(textDragGesture)
                        .simultaneousGesture(textRotationGesture)
                }
            } else {
                textLayer
            }
        }
    }

    @ViewBuilder
    private var profileLayer: some View {
        if let profile = premiumMakerConfiguration.circularProfile,
           let profileImage = profile.image,
           isProfileLayerVisible {
            let profileDiameter = width * effectiveProfileSize(for: profile.size)
            let profileHitTarget = max(profileDiameter, 44)
            let profileContentLayer = ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: profileHitTarget, height: profileHitTarget)

                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: profileDiameter, height: profileDiameter)
                    .thumbnailAdjustments( // FEATURE-14
                        premiumMakerConfiguration.layers.renderAdjustments(forLayerID: ThumbnailDocumentLayer.profileID),
                        renderedSize: CGSize(width: profileDiameter, height: profileDiameter)
                    )
                    .clipShape(Circle())
            }
            .frame(width: profileHitTarget, height: profileHitTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(isInteractive ? "profileOverlayLayer" : "profilePreviewOverlayLayer")
            .accessibilityLabel("Profile image overlay")
            .accessibilityValue(
                premiumMakerConfiguration.profileTransform.canvasStateDescription(
                    size: effectiveProfileSize(for: profile.size)
                )
            )

            Group {
                if isInteractive {
                    let selectableProfileLayer = profileContentLayer
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(.isButton)
                        .simultaneousGesture(TapGesture().onEnded {
                            selectedOverlay.wrappedValue = .profileOverlay
                        })

                    if isProfileLayerLocked {
                        selectableProfileLayer
                    } else {
                        selectableProfileLayer
                            .overlayMoveAccessibilityActions(
                                moveUp: {
                                    nudgeProfileOverlay(dx: 0, dy: -Self.accessibilityMoveStep)
                                },
                                moveDown: {
                                    nudgeProfileOverlay(dx: 0, dy: Self.accessibilityMoveStep)
                                },
                                moveLeft: {
                                    nudgeProfileOverlay(dx: -Self.accessibilityMoveStep, dy: 0)
                                },
                                moveRight: {
                                    nudgeProfileOverlay(dx: Self.accessibilityMoveStep, dy: 0)
                                }
                            )
                            .gesture(profileDragGesture)
                    }
                } else {
                    profileContentLayer
                }
            }
            .rotationEffect(
                .degrees(
                    premiumMakerConfiguration.profileTransform.rotationDegrees
                        + profileHandleRotationDelta
                )
            )
            .scaleEffect(
                x: premiumMakerConfiguration.profileTransform.isFlippedHorizontally ? -1 : 1,
                y: 1
            )
            .position(profileLayerPosition)
            .preference(key: CenterSnapGuidePreferenceKey.self, value: profileSnapGuide)
        }
    }

    @ViewBuilder
    private var selectedManipulationChrome: some View {
        textManipulationChrome
        profileManipulationChrome
        contentManipulationChrome
    }

    @ViewBuilder
    private var textManipulationChrome: some View {
        let text = premiumMakerConfiguration.overlayText
        if isInteractive
            && activeOverlaySelection == .textOverlay
            && !isTextLayerLocked
            && !text.isEmpty
            && isTextLayerVisible {
            let fontSize = overlayFontSize(for: text) // GAPS: main-title auto-fit
            // FEATURE-04: hit/chrome proxy shares the rendered text geometry.
            StyledThumbnailTextView.overlay(
                text: text,
                font: premiumMakerConfiguration.selectedFont,
                color: premiumMakerConfiguration.textColor,
                fontSize: fontSize,
                style: premiumMakerConfiguration.textStyle,
                canvasSize: CGSize(width: width, height: height)
            )
                .opacity(0)
                .contentShape(Rectangle())
                .gesture(textDragGesture)
                .overlay {
                    OverlayManipulationChromeView(
                        accessibilityPrefix: "text",
                        cornerRadius: 6,
                        rotateGesture: textRotateHandleGesture,
                        resizeGesture: textResizeHandleGesture,
                        flipAction: {
                            premiumMakerConfiguration.textTransform.flipHorizontally()
                        },
                        rotateClockwiseAction: {
                            rotateTextOverlay(by: Self.accessibilityRotationStep)
                        },
                        rotateCounterClockwiseAction: {
                            rotateTextOverlay(by: -Self.accessibilityRotationStep)
                        },
                        increaseSizeAction: {
                            resizeTextOverlay(by: Self.accessibilitySizeStep)
                        },
                        decreaseSizeAction: {
                            resizeTextOverlay(by: -Self.accessibilitySizeStep)
                        }
                    )
                }
                .rotationEffect(
                    .degrees(
                        premiumMakerConfiguration.textTransform.rotationDegrees
                            + textRotationDelta.degrees
                            + textHandleRotationDelta
                    )
                )
                .scaleEffect(
                    x: premiumMakerConfiguration.textTransform.isFlippedHorizontally ? -1 : 1,
                    y: 1
                )
                .position(textLayerPosition)
        }
    }

    @ViewBuilder
    private var profileManipulationChrome: some View {
        if let profile = premiumMakerConfiguration.circularProfile,
           profile.image != nil,
           isInteractive,
           activeOverlaySelection == .profileOverlay,
           !isProfileLayerLocked,
           isProfileLayerVisible {
            let profileDiameter = width * effectiveProfileSize(for: profile.size)
            let profileHitTarget = max(profileDiameter, 44)
            let nextIsFlippedHorizontally = !premiumMakerConfiguration.profileTransform.isFlippedHorizontally

            Color.clear
                .frame(
                    width: max(profileHitTarget, OverlayManipulationChromeView.minimumInteractiveWidth),
                    height: max(profileHitTarget, OverlayManipulationChromeView.minimumInteractiveHeight)
                )
                .contentShape(Rectangle())
                .accessibilityHidden(true)
                .gesture(profileDragGesture)
                .overlay {
                    OverlayManipulationChromeView(
                        accessibilityPrefix: "profile",
                        cornerRadius: profileHitTarget / 2,
                        rotateGesture: profileRotateHandleGesture,
                        resizeGesture: profileResizeHandleGesture,
                        flipAction: {
                            premiumMakerConfiguration.profileTransform.isFlippedHorizontally = nextIsFlippedHorizontally
                            selectedOverlay.wrappedValue = .profileOverlay
                        },
                        rotateClockwiseAction: {
                            rotateProfileOverlay(by: Self.accessibilityRotationStep)
                        },
                        rotateCounterClockwiseAction: {
                            rotateProfileOverlay(by: -Self.accessibilityRotationStep)
                        },
                        increaseSizeAction: {
                            resizeProfileOverlay(by: Self.accessibilitySizeStep)
                        },
                        decreaseSizeAction: {
                            resizeProfileOverlay(by: -Self.accessibilitySizeStep)
                        }
                    )
                }
                .rotationEffect(
                    .degrees(
                        premiumMakerConfiguration.profileTransform.rotationDegrees
                            + profileHandleRotationDelta
                    )
                )
                .scaleEffect(
                    x: premiumMakerConfiguration.profileTransform.isFlippedHorizontally ? -1 : 1,
                    y: 1
                )
                .position(profileLayerPosition)
        }
    }

    @ViewBuilder
    private var contentManipulationChrome: some View {
        if isInteractive,
           let layer = selectedContentLayer,
           !layer.isLocked {
            switch layer.content {
            case .image(let content):
                imageManipulationChrome(layerID: layer.id, content: content)
            case .text(let content):
                textContentManipulationChrome(layerID: layer.id, content: content)
            case .shape(let content):
                shapeManipulationChrome(layerID: layer.id, content: content)
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func imageManipulationChrome(layerID: String, content: ThumbnailImageLayerContent) -> some View {
        if let image = UIImage(data: content.imageData) {
            let canvasSize = CGSize(width: width, height: height)
            let frameSize = ContentLayerCanvasGeometry.imageFrameSize(
                for: image,
                content: content,
                resizeTranslation: contentResizeTranslation,
                canvasSize: canvasSize
            )
            let hitSize = ContentLayerCanvasGeometry.hitSize(for: frameSize)
            let nextIsFlippedHorizontally = !content.transform.isFlippedHorizontally

            OverlayManipulationChromeView(
                accessibilityPrefix: "image",
                cornerRadius: 6,
                rotateGesture: imageContentRotateHandleGesture(layerID: layerID, content: content),
                resizeGesture: imageContentResizeHandleGesture(layerID: layerID, content: content),
                flipAction: {
                    updateImageContent(layerID: layerID) { nextContent in
                        nextContent.transform.isFlippedHorizontally = nextIsFlippedHorizontally
                    }
                    selectedOverlay.wrappedValue = .content(layerID)
                },
                rotateClockwiseAction: {
                    rotateImageContent(layerID: layerID, content: content, by: Self.accessibilityRotationStep)
                },
                rotateCounterClockwiseAction: {
                    rotateImageContent(layerID: layerID, content: content, by: -Self.accessibilityRotationStep)
                },
                increaseSizeAction: {
                    resizeImageContent(layerID: layerID, content: content, by: Self.accessibilitySizeStep)
                },
                decreaseSizeAction: {
                    resizeImageContent(layerID: layerID, content: content, by: -Self.accessibilitySizeStep)
                }
            )
                .frame(
                    width: max(hitSize.width, OverlayManipulationChromeView.minimumInteractiveWidth),
                    height: max(hitSize.height, OverlayManipulationChromeView.minimumInteractiveHeight)
                )
                .rotationEffect(
                    .degrees(
                        content.transform.rotationDegrees
                            + contentRotationDelta.degrees
                            + contentHandleRotationDelta
                    )
                )
                .scaleEffect(x: content.transform.isFlippedHorizontally ? -1 : 1, y: 1)
                .position(contentLayerPosition(for: content.transform))
        }
    }

    @ViewBuilder
    private func textContentManipulationChrome(layerID: String, content: ThumbnailTextLayerContent) -> some View {
        let frameSize = ContentLayerCanvasGeometry.textFrameSize(
            for: content,
            resizeTranslation: contentResizeTranslation,
            canvasSize: CGSize(width: width, height: height)
        )
        let hitSize = ContentLayerCanvasGeometry.hitSize(for: frameSize)
        let nextIsFlippedHorizontally = !content.transform.isFlippedHorizontally

        OverlayManipulationChromeView(
            accessibilityPrefix: "textContent",
            cornerRadius: 6,
            rotateGesture: textContentRotateHandleGesture(layerID: layerID, content: content),
            resizeGesture: textContentResizeHandleGesture(layerID: layerID, content: content),
            flipAction: {
                updateTextContent(layerID: layerID) { nextContent in
                    nextContent.transform.isFlippedHorizontally = nextIsFlippedHorizontally
                }
                selectedOverlay.wrappedValue = .content(layerID)
            },
            rotateClockwiseAction: {
                rotateTextContent(layerID: layerID, content: content, by: Self.accessibilityRotationStep)
            },
            rotateCounterClockwiseAction: {
                rotateTextContent(layerID: layerID, content: content, by: -Self.accessibilityRotationStep)
            },
            increaseSizeAction: {
                resizeTextContent(layerID: layerID, content: content, by: Self.accessibilitySizeStep)
            },
            decreaseSizeAction: {
                resizeTextContent(layerID: layerID, content: content, by: -Self.accessibilitySizeStep)
            }
        )
            .frame(
                width: max(hitSize.width, OverlayManipulationChromeView.minimumInteractiveWidth),
                height: max(hitSize.height, OverlayManipulationChromeView.minimumInteractiveHeight)
            )
            .rotationEffect(
                .degrees(
                    content.transform.rotationDegrees
                        + contentRotationDelta.degrees
                        + contentHandleRotationDelta
                )
            )
            .scaleEffect(x: content.transform.isFlippedHorizontally ? -1 : 1, y: 1)
            .position(contentLayerPosition(for: content.transform))
    }

    @ViewBuilder
    private func shapeManipulationChrome(layerID: String, content: ThumbnailShapeLayerContent) -> some View {
        let frameSize = ContentLayerCanvasGeometry.shapeFrameSize(
            for: content,
            resizeTranslation: contentResizeTranslation,
            canvasSize: CGSize(width: width, height: height)
        )
        let hitSize = ContentLayerCanvasGeometry.hitSize(for: frameSize)
        let nextIsFlippedHorizontally = !content.transform.isFlippedHorizontally

        OverlayManipulationChromeView(
            accessibilityPrefix: "shape",
            cornerRadius: 6,
            rotateGesture: shapeContentRotateHandleGesture(layerID: layerID, content: content),
            resizeGesture: shapeContentResizeHandleGesture(layerID: layerID, content: content),
            flipAction: {
                updateShapeContent(layerID: layerID) { nextContent in
                    nextContent.transform.isFlippedHorizontally = nextIsFlippedHorizontally
                }
                selectedOverlay.wrappedValue = .content(layerID)
            },
            rotateClockwiseAction: {
                rotateShapeContent(layerID: layerID, content: content, by: Self.accessibilityRotationStep)
            },
            rotateCounterClockwiseAction: {
                rotateShapeContent(layerID: layerID, content: content, by: -Self.accessibilityRotationStep)
            },
            increaseSizeAction: {
                resizeShapeContent(layerID: layerID, content: content, by: Self.accessibilitySizeStep)
            },
            decreaseSizeAction: {
                resizeShapeContent(layerID: layerID, content: content, by: -Self.accessibilitySizeStep)
            }
        )
            .frame(
                width: max(hitSize.width, OverlayManipulationChromeView.minimumInteractiveWidth),
                height: max(hitSize.height, OverlayManipulationChromeView.minimumInteractiveHeight)
            )
            .rotationEffect(
                .degrees(
                    content.transform.rotationDegrees
                        + contentRotationDelta.degrees
                        + contentHandleRotationDelta
                )
            )
            .scaleEffect(x: content.transform.isFlippedHorizontally ? -1 : 1, y: 1)
            .position(contentLayerPosition(for: content.transform))
    }

    private var textLayerPosition: CGPoint {
        let position = ThumbnailOverlayTransform.normalizedPosition(
            x: premiumMakerConfiguration.textTransform.x,
            y: premiumMakerConfiguration.textTransform.y,
            translation: textDragTranslation,
            in: CGSize(width: width, height: height),
            snapping: isTextDragging
        )
        return CGPoint(x: width * position.x, y: height * position.y)
    }

    private func contentLayerPosition(for transform: ThumbnailOverlayTransform) -> CGPoint {
        let position = ThumbnailOverlayTransform.normalizedPosition(
            x: transform.x,
            y: transform.y,
            translation: contentDragTranslation,
            in: CGSize(width: width, height: height),
            snapping: isContentDragging
        )
        return CGPoint(x: width * position.x, y: height * position.y)
    }

    private var profileLayerPosition: CGPoint {
        let position = ThumbnailOverlayTransform.normalizedPosition(
            x: premiumMakerConfiguration.profileTransform.x,
            y: premiumMakerConfiguration.profileTransform.y,
            translation: profileDragTranslation,
            in: CGSize(width: width, height: height),
            snapping: isProfileDragging
        )
        return CGPoint(x: width * position.x, y: height * position.y)
    }

    private var textSnapGuide: CenterSnapGuide {
        guard isTextDragging else { return [] }

        return ThumbnailOverlayTransform.centerSnapGuide(
            for: premiumMakerConfiguration.textTransform,
            translation: textDragTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    private var profileSnapGuide: CenterSnapGuide {
        guard isProfileDragging else { return [] }

        return ThumbnailOverlayTransform.centerSnapGuide(
            for: premiumMakerConfiguration.profileTransform,
            translation: profileDragTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    /// GAPS: the main title's draw size; auto-fit shrinks it into its box.
    private func overlayFontSize(for text: String) -> CGFloat {
        ThumbnailTextAutoFit.overlayFontSize(
            text: text,
            font: premiumMakerConfiguration.selectedFont,
            requested: height * effectiveTextSize,
            style: premiumMakerConfiguration.textStyle,
            autoFit: premiumMakerConfiguration.overlayAutoFit,
            canvasSize: CGSize(width: width, height: height)
        )
    }

    private var effectiveTextSize: CGFloat {
        Self.adjustedTextSize(
            premiumMakerConfiguration.textSize,
            by: textResizeTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    private func effectiveProfileSize(for size: CGFloat) -> CGFloat {
        Self.adjustedProfileSize(
            size,
            by: profileResizeTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    private var isTextLayerVisible: Bool {
        premiumMakerConfiguration.layers.isVisible(ThumbnailEditorLayer.text)
    }

    private var isTextLayerLocked: Bool {
        premiumMakerConfiguration.layers.isLocked(ThumbnailEditorLayer.text)
    }

    private var isProfileLayerVisible: Bool {
        premiumMakerConfiguration.layers.isVisible(ThumbnailEditorLayer.profile)
    }

    private var isProfileLayerLocked: Bool {
        premiumMakerConfiguration.layers.isLocked(ThumbnailEditorLayer.profile)
    }

    private var renderableLayerRecords: [ThumbnailDocumentLayer] {
        let selections = premiumMakerConfiguration.layers.selectableLayerSelections(
            hasText: !premiumMakerConfiguration.overlayText.isEmpty,
            hasProfile: premiumMakerConfiguration.circularProfile?.image != nil
        )

        return premiumMakerConfiguration.layers.sortedSelections(selections).compactMap { selection in
            guard let record = premiumMakerConfiguration.layers.record(for: selection)
                ?? fallbackRecord(for: selection) else {
                return nil
            }
            guard record.isVisible else {
                return nil
            }
            return record
        }
    }

    private func fallbackRecord(for selection: ThumbnailLayerSelection) -> ThumbnailDocumentLayer? {
        switch selection {
        case .textOverlay:
            return .defaultTextLayer
        case .profileOverlay:
            return .defaultProfileLayer
        case .content:
            return nil
        }
    }

    private var activeOverlaySelection: ThumbnailLayerSelection? {
        if selectedOverlay.wrappedValue == .textOverlay && !premiumMakerConfiguration.overlayText.isEmpty {
            return isTextLayerVisible ? .textOverlay : nil
        }

        if selectedOverlay.wrappedValue == .profileOverlay && premiumMakerConfiguration.circularProfile?.image != nil {
            return isProfileLayerVisible ? .profileOverlay : nil
        }

        if case .content(let layerID) = selectedOverlay.wrappedValue,
           let layer = premiumMakerConfiguration.layers.record(id: layerID),
           layer.isVisible,
           layer.content != nil {
            return .content(layerID)
        }

        if !premiumMakerConfiguration.overlayText.isEmpty && isTextLayerVisible {
            return .textOverlay
        }

        if premiumMakerConfiguration.circularProfile?.image != nil && isProfileLayerVisible {
            return .profileOverlay
        }

        return nil
    }

    private var selectedContentLayer: ThumbnailDocumentLayer? {
        guard case .content(let layerID) = selectedOverlay.wrappedValue,
              let layer = premiumMakerConfiguration.layers.record(id: layerID),
              layer.isVisible,
              layer.content != nil else {
            return nil
        }

        return layer
    }

    private var textDragGesture: some Gesture {
        DragGesture(minimumDistance: Self.canvasDragMinimumDistance)
            .onChanged { _ in
                selectedOverlay.wrappedValue = .textOverlay
            }
            .updating($isTextDragging) { _, state, _ in
                state = true
            }
            .updating($textDragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                selectedOverlay.wrappedValue = .textOverlay
                let groupStart = premiumMakerConfiguration.arrangeCenter(for: .textOverlay) // FEATURE-07
                premiumMakerConfiguration.textTransform.moveWithSnap(
                    by: value.translation,
                    in: CGSize(width: width, height: height)
                )
                if let followed = premiumMakerConfiguration.followingGroupMove(of: .textOverlay, from: groupStart) {
                    premiumMakerConfiguration = followed // FEATURE-07: the rest of the group follows
                }
            }
    }

    private var profileDragGesture: some Gesture {
        DragGesture(minimumDistance: Self.canvasDragMinimumDistance)
            .onChanged { _ in
                selectedOverlay.wrappedValue = .profileOverlay
            }
            .updating($isProfileDragging) { _, state, _ in
                state = true
            }
            .updating($profileDragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                selectedOverlay.wrappedValue = .profileOverlay
                let groupStart = premiumMakerConfiguration.arrangeCenter(for: .profileOverlay) // FEATURE-07
                premiumMakerConfiguration.profileTransform.moveWithSnap(
                    by: value.translation,
                    in: CGSize(width: width, height: height)
                )
                if let followed = premiumMakerConfiguration.followingGroupMove(of: .profileOverlay, from: groupStart) {
                    premiumMakerConfiguration = followed // FEATURE-07: the rest of the group follows
                }
            }
    }

    private var textRotationGesture: some Gesture {
        RotationGesture()
            .updating($textRotationDelta) { value, state, _ in
                state = value
            }
            .onEnded { value in
                premiumMakerConfiguration.textTransform.rotate(by: value.degrees)
            }
    }

    private var textResizeHandleGesture: AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasCoordinateSpace))
                .updating($textResizeTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    selectedOverlay.wrappedValue = .textOverlay
                    premiumMakerConfiguration.textSize = Self.adjustedTextSize(
                        premiumMakerConfiguration.textSize,
                        by: value.translation,
                        in: CGSize(width: width, height: height)
                    )
                }
                .map { _ in () }
        )
    }

    private var profileResizeHandleGesture: AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasCoordinateSpace))
                .updating($profileResizeTranslation) { value, state, _ in
                    if premiumMakerConfiguration.circularProfile != nil {
                        state = value.translation
                    }
                }
                .onEnded { value in
                    if let size = premiumMakerConfiguration.circularProfile?.size {
                        selectedOverlay.wrappedValue = .profileOverlay
                        premiumMakerConfiguration.circularProfile?.size = Self.adjustedProfileSize(
                            size,
                            by: value.translation,
                            in: CGSize(width: width, height: height)
                        )
                    }
                }
                .map { _ in () }
        )
    }

    private var textRotateHandleGesture: AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasCoordinateSpace))
                .updating($textHandleRotationDelta) { value, state, _ in
                    state = textHandleRotationDelta(for: value)
                }
                .onEnded { value in
                    selectedOverlay.wrappedValue = .textOverlay
                    premiumMakerConfiguration.textTransform.rotate(
                        by: textHandleRotationDelta(for: value)
                    )
                }
                .map { _ in () }
        )
    }

    private var profileRotateHandleGesture: AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasCoordinateSpace))
                .updating($profileHandleRotationDelta) { value, state, _ in
                    state = profileHandleRotationDelta(for: value)
                }
                .onEnded { value in
                    selectedOverlay.wrappedValue = .profileOverlay
                    premiumMakerConfiguration.profileTransform.rotate(
                        by: profileHandleRotationDelta(for: value)
                    )
                }
                .map { _ in () }
        )
    }

    private func textHandleRotationDelta(for value: DragGesture.Value) -> Double {
        ThumbnailOverlayTransform.rotationDelta(
            from: value.startLocation,
            to: value.location,
            around: textLayerPosition
        )
    }

    private func profileHandleRotationDelta(for value: DragGesture.Value) -> Double {
        ThumbnailOverlayTransform.rotationDelta(
            from: value.startLocation,
            to: value.location,
            around: profileLayerPosition
        )
    }

    private func imageContentDragGesture(
        layerID: String,
        content: ThumbnailImageLayerContent
    ) -> AnyGesture<Void> {
        contentDragGesture(
            layerID: layerID,
            transform: content.transform,
            updateTransform: { nextTransform in
                updateImageContent(layerID: layerID) { nextContent in
                    nextContent.transform = nextTransform
                }
            }
        )
    }

    private func shapeContentDragGesture(
        layerID: String,
        content: ThumbnailShapeLayerContent
    ) -> AnyGesture<Void> {
        contentDragGesture(
            layerID: layerID,
            transform: content.transform,
            updateTransform: { nextTransform in
                updateShapeContent(layerID: layerID) { nextContent in
                    nextContent.transform = nextTransform
                }
            }
        )
    }

    private func textContentDragGesture(
        layerID: String,
        content: ThumbnailTextLayerContent
    ) -> AnyGesture<Void> {
        contentDragGesture(
            layerID: layerID,
            transform: content.transform,
            updateTransform: { nextTransform in
                updateTextContent(layerID: layerID) { nextContent in
                    nextContent.transform = nextTransform
                }
            }
        )
    }

    private func contentDragGesture(
        layerID: String,
        transform: ThumbnailOverlayTransform,
        updateTransform: @escaping (ThumbnailOverlayTransform) -> Void
    ) -> AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: Self.canvasDragMinimumDistance)
                .onChanged { _ in
                    selectedOverlay.wrappedValue = .content(layerID)
                }
                .updating($isContentDragging) { _, state, _ in
                    state = true
                }
                .updating($contentDragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let groupStart = premiumMakerConfiguration.arrangeCenter(for: .content(layerID)) // FEATURE-07
                    var nextTransform = transform
                    nextTransform.moveWithSnap(
                        by: value.translation,
                        in: CGSize(width: width, height: height)
                    )
                    updateTransform(nextTransform)
                    if let followed = premiumMakerConfiguration.followingGroupMove(of: .content(layerID), from: groupStart) {
                        premiumMakerConfiguration = followed // FEATURE-07: the rest of the group follows
                    }
                    selectedOverlay.wrappedValue = .content(layerID)
                }
                .map { _ in () }
        )
    }

    private func imageContentRotationGesture(
        layerID: String,
        content: ThumbnailImageLayerContent
    ) -> AnyGesture<Void> {
        contentRotationGesture(layerID: layerID, transform: content.transform) { nextTransform in
            updateImageContent(layerID: layerID) { nextContent in
                nextContent.transform = nextTransform
            }
        }
    }

    private func textContentRotationGesture(
        layerID: String,
        content: ThumbnailTextLayerContent
    ) -> AnyGesture<Void> {
        contentRotationGesture(layerID: layerID, transform: content.transform) { nextTransform in
            updateTextContent(layerID: layerID) { nextContent in
                nextContent.transform = nextTransform
            }
        }
    }

    private func shapeContentRotationGesture(
        layerID: String,
        content: ThumbnailShapeLayerContent
    ) -> AnyGesture<Void> {
        contentRotationGesture(layerID: layerID, transform: content.transform) { nextTransform in
            updateShapeContent(layerID: layerID) { nextContent in
                nextContent.transform = nextTransform
            }
        }
    }

    private func contentRotationGesture(
        layerID: String,
        transform: ThumbnailOverlayTransform,
        updateTransform: @escaping (ThumbnailOverlayTransform) -> Void
    ) -> AnyGesture<Void> {
        AnyGesture(
            RotationGesture()
                .updating($contentRotationDelta) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    var nextTransform = transform
                    nextTransform.rotate(by: value.degrees)
                    updateTransform(nextTransform)
                    selectedOverlay.wrappedValue = .content(layerID)
                }
                .map { _ in () }
        )
    }

    private func imageContentResizeHandleGesture(
        layerID: String,
        content: ThumbnailImageLayerContent
    ) -> AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasCoordinateSpace))
                .updating($contentResizeTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    updateImageContent(layerID: layerID) { nextContent in
                        nextContent.size = Double(
                            ContentLayerCanvasGeometry.adjustedImageSize(
                                CGFloat(content.size),
                                by: value.translation,
                                in: CGSize(width: width, height: height)
                            )
                        )
                    }
                    selectedOverlay.wrappedValue = .content(layerID)
                }
                .map { _ in () }
        )
    }

    private func textContentResizeHandleGesture(
        layerID: String,
        content: ThumbnailTextLayerContent
    ) -> AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasCoordinateSpace))
                .updating($contentResizeTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    updateTextContent(layerID: layerID) { nextContent in
                        nextContent.size = Double(
                            ContentLayerCanvasGeometry.adjustedTextSize(
                                CGFloat(content.size),
                                by: value.translation,
                                in: CGSize(width: width, height: height)
                            )
                        )
                    }
                    selectedOverlay.wrappedValue = .content(layerID)
                }
                .map { _ in () }
        )
    }

    private func shapeContentResizeHandleGesture(
        layerID: String,
        content: ThumbnailShapeLayerContent
    ) -> AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasCoordinateSpace))
                .updating($contentResizeTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let nextSize = ContentLayerCanvasGeometry.normalizedShapeSize(
                        for: content,
                        by: value.translation,
                        in: CGSize(width: width, height: height)
                    )
                    updateShapeContent(layerID: layerID) { nextContent in
                        nextContent.width = nextSize.width
                        nextContent.height = nextSize.height
                    }
                    selectedOverlay.wrappedValue = .content(layerID)
                }
                .map { _ in () }
        )
    }

    private func imageContentRotateHandleGesture(
        layerID: String,
        content: ThumbnailImageLayerContent
    ) -> AnyGesture<Void> {
        contentRotateHandleGesture(layerID: layerID, transform: content.transform) { nextTransform in
            updateImageContent(layerID: layerID) { nextContent in
                nextContent.transform = nextTransform
            }
        }
    }

    private func textContentRotateHandleGesture(
        layerID: String,
        content: ThumbnailTextLayerContent
    ) -> AnyGesture<Void> {
        contentRotateHandleGesture(layerID: layerID, transform: content.transform) { nextTransform in
            updateTextContent(layerID: layerID) { nextContent in
                nextContent.transform = nextTransform
            }
        }
    }

    private func shapeContentRotateHandleGesture(
        layerID: String,
        content: ThumbnailShapeLayerContent
    ) -> AnyGesture<Void> {
        contentRotateHandleGesture(layerID: layerID, transform: content.transform) { nextTransform in
            updateShapeContent(layerID: layerID) { nextContent in
                nextContent.transform = nextTransform
            }
        }
    }

    private func contentRotateHandleGesture(
        layerID: String,
        transform: ThumbnailOverlayTransform,
        updateTransform: @escaping (ThumbnailOverlayTransform) -> Void
    ) -> AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasCoordinateSpace))
                .updating($contentHandleRotationDelta) { value, state, _ in
                    state = contentHandleRotationDelta(for: value, transform: transform)
                }
                .onEnded { value in
                    var nextTransform = transform
                    nextTransform.rotate(
                        by: contentHandleRotationDelta(for: value, transform: transform)
                    )
                    updateTransform(nextTransform)
                    selectedOverlay.wrappedValue = .content(layerID)
                }
                .map { _ in () }
        )
    }

    private func contentHandleRotationDelta(
        for value: DragGesture.Value,
        transform: ThumbnailOverlayTransform
    ) -> Double {
        ThumbnailOverlayTransform.rotationDelta(
            from: value.startLocation,
            to: value.location,
            around: contentLayerPosition(for: transform)
        )
    }

    private func updateImageContent(
        layerID: String,
        mutate: (inout ThumbnailImageLayerContent) -> Void
    ) {
        premiumMakerConfiguration.layers.updateImageContent(id: layerID, mutate: mutate)
    }

    private func updateTextContent(
        layerID: String,
        mutate: (inout ThumbnailTextLayerContent) -> Void
    ) {
        premiumMakerConfiguration.layers.updateTextContent(id: layerID, mutate: mutate)
    }

    private func updateShapeContent(
        layerID: String,
        mutate: (inout ThumbnailShapeLayerContent) -> Void
    ) {
        premiumMakerConfiguration.layers.updateShapeContent(id: layerID, mutate: mutate)
    }

    private func rotateImageContent(
        layerID: String,
        content: ThumbnailImageLayerContent,
        by degrees: Double
    ) {
        updateImageContent(layerID: layerID) { nextContent in
            nextContent.transform.rotate(by: degrees)
        }
        selectedOverlay.wrappedValue = .content(layerID)
    }

    private func rotateTextContent(
        layerID: String,
        content: ThumbnailTextLayerContent,
        by degrees: Double
    ) {
        updateTextContent(layerID: layerID) { nextContent in
            nextContent.transform.rotate(by: degrees)
        }
        selectedOverlay.wrappedValue = .content(layerID)
    }

    private func rotateShapeContent(
        layerID: String,
        content: ThumbnailShapeLayerContent,
        by degrees: Double
    ) {
        updateShapeContent(layerID: layerID) { nextContent in
            nextContent.transform.rotate(by: degrees)
        }
        selectedOverlay.wrappedValue = .content(layerID)
    }

    private func resizeImageContent(
        layerID: String,
        content: ThumbnailImageLayerContent,
        by delta: CGFloat
    ) {
        updateImageContent(layerID: layerID) { nextContent in
            nextContent.size = Double(min(
                ContentLayerCanvasGeometry.imageSizeLimits.upperBound,
                max(ContentLayerCanvasGeometry.imageSizeLimits.lowerBound, CGFloat(content.size) + delta)
            ))
        }
        selectedOverlay.wrappedValue = .content(layerID)
    }

    private func resizeTextContent(
        layerID: String,
        content: ThumbnailTextLayerContent,
        by delta: CGFloat
    ) {
        updateTextContent(layerID: layerID) { nextContent in
            nextContent.size = Double(min(
                ContentLayerCanvasGeometry.textSizeLimits.upperBound,
                max(ContentLayerCanvasGeometry.textSizeLimits.lowerBound, CGFloat(content.size) + delta)
            ))
        }
        selectedOverlay.wrappedValue = .content(layerID)
    }

    private func resizeShapeContent(
        layerID: String,
        content: ThumbnailShapeLayerContent,
        by delta: CGFloat
    ) {
        updateShapeContent(layerID: layerID) { nextContent in
            nextContent.width = Double(min(
                ContentLayerCanvasGeometry.shapeWidthLimits.upperBound,
                max(ContentLayerCanvasGeometry.shapeWidthLimits.lowerBound, CGFloat(content.width) + delta)
            ))
            nextContent.height = Double(min(
                ContentLayerCanvasGeometry.shapeHeightLimits.upperBound,
                max(ContentLayerCanvasGeometry.shapeHeightLimits.lowerBound, CGFloat(content.height) + delta)
            ))
        }
        selectedOverlay.wrappedValue = .content(layerID)
    }

    private func rotateTextOverlay(by degrees: Double) {
        selectedOverlay.wrappedValue = .textOverlay
        premiumMakerConfiguration.textTransform.rotate(by: degrees)
    }

    private func rotateProfileOverlay(by degrees: Double) {
        selectedOverlay.wrappedValue = .profileOverlay
        premiumMakerConfiguration.profileTransform.rotate(by: degrees)
    }

    private func resizeTextOverlay(by delta: CGFloat) {
        selectedOverlay.wrappedValue = .textOverlay
        premiumMakerConfiguration.textSize = Self.adjustedTextSize(
            premiumMakerConfiguration.textSize,
            by: delta
        )
    }

    private func resizeProfileOverlay(by delta: CGFloat) {
        guard let size = premiumMakerConfiguration.circularProfile?.size else { return }

        selectedOverlay.wrappedValue = .profileOverlay
        premiumMakerConfiguration.circularProfile?.size = Self.adjustedProfileSize(size, by: delta)
    }

    private func nudgeTextOverlay(dx: CGFloat, dy: CGFloat) {
        selectedOverlay.wrappedValue = .textOverlay
        premiumMakerConfiguration.textTransform.move(
            by: CGSize(width: width * dx, height: height * dy),
            in: CGSize(width: width, height: height)
        )
    }

    private func nudgeProfileOverlay(dx: CGFloat, dy: CGFloat) {
        selectedOverlay.wrappedValue = .profileOverlay
        premiumMakerConfiguration.profileTransform.move(
            by: CGSize(width: width * dx, height: height * dy),
            in: CGSize(width: width, height: height)
        )
    }

    private static func adjustedTextSize(
        _ size: CGFloat,
        by translation: CGSize,
        in canvasSize: CGSize
    ) -> CGFloat {
        ThumbnailOverlayTransform.adjustedOverlaySize(
            size,
            by: translation,
            in: canvasSize,
            limits: textSizeLimits
        )
    }

    private static func adjustedTextSize(_ size: CGFloat, by delta: CGFloat) -> CGFloat {
        min(textSizeLimits.upperBound, max(textSizeLimits.lowerBound, size + delta))
    }

    private static func adjustedProfileSize(
        _ size: CGFloat,
        by translation: CGSize,
        in canvasSize: CGSize
    ) -> CGFloat {
        ThumbnailOverlayTransform.adjustedOverlaySize(
            size,
            by: translation,
            in: canvasSize,
            limits: profileSizeLimits
        )
    }

    private static func adjustedProfileSize(_ size: CGFloat, by delta: CGFloat) -> CGFloat {
        min(profileSizeLimits.upperBound, max(profileSizeLimits.lowerBound, size + delta))
    }

    private var placeholderIconSize: CGFloat {
        min(40, max(12, height * 0.22))
    }

    private var placeholderTextSize: CGFloat {
        min(17, max(8, height * 0.1))
    }

    private var placeholderSpacing: CGFloat {
        min(12, max(4, height * 0.04))
    }

    private var placeholderPadding: CGFloat {
        min(16, max(4, min(width, height) * 0.08))
    }
}
