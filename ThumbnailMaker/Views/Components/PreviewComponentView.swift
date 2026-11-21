//
//  PreviewComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct CenterSnapGuidePreferenceKey: PreferenceKey {
    static var defaultValue: CenterSnapGuide = []

    static func reduce(value: inout CenterSnapGuide, nextValue: () -> CenterSnapGuide) {
        value.formUnion(nextValue())
    }
}

struct CenterAlignmentGuideView: View {
    let guide: CenterSnapGuide
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            if guide.contains(.xCentered) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.84))
                    .frame(width: 1.5, height: height)
                    .position(x: width / 2, y: height / 2)
                    .accessibilityIdentifier("canvasVerticalCenterGuide")
            }

            if guide.contains(.yCentered) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.84))
                    .frame(width: width, height: 1.5)
                    .position(x: width / 2, y: height / 2)
                    .accessibilityIdentifier("canvasHorizontalCenterGuide")
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PreviewComponentView: View {
    @Binding var simpleMakerConfiguration: SimpleMakerConfigurationModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var activeSnapGuide: CenterSnapGuide = []
    @GestureState private var isTextDragging = false
    @GestureState private var textDragTranslation: CGSize = .zero
    @GestureState private var textRotationDelta: Angle = .zero
    @GestureState private var textHandleRotationDelta: Double = 0
    @GestureState private var textResizeTranslation: CGSize = .zero
    @GestureState private var isContentDragging = false
    @GestureState private var contentDragTranslation: CGSize = .zero
    @GestureState private var contentRotationDelta: Angle = .zero
    @GestureState private var contentHandleRotationDelta: Double = 0
    @GestureState private var contentResizeTranslation: CGSize = .zero
    private let selectedOverlay: Binding<ThumbnailLayerSelection>
    let width: CGFloat
    let height: CGFloat
    var isTextInteractive = false
    var safeZone: ThumbnailSafeZone?
    private static let canvasCoordinateSpace = "simplePreviewCanvas"
    private static let textSizeLimits: ClosedRange<CGFloat> = 0.08...0.34
    private static let accessibilityRotationStep = 5.0
    private static let accessibilitySizeStep: CGFloat = 0.02
    private static let accessibilityMoveStep: CGFloat = 0.02
    private static let canvasDragMinimumDistance: CGFloat = 2

    init(
        simpleMakerConfiguration: Binding<SimpleMakerConfigurationModel>,
        width: CGFloat,
        height: CGFloat,
        isTextInteractive: Bool = false,
        safeZone: ThumbnailSafeZone? = nil,
        selectedOverlay: Binding<ThumbnailLayerSelection> = .constant(.textOverlay)
    ) {
        self._simpleMakerConfiguration = simpleMakerConfiguration
        self.width = width
        self.height = height
        self.isTextInteractive = isTextInteractive
        self.safeZone = safeZone
        self.selectedOverlay = selectedOverlay
    }
    
    var body: some View {
        thumbnailContent
    }
    
    @ViewBuilder
    private var thumbnailContent: some View {
        ZStack {
            ThumbnailBackgroundFillView( // SHELL: solid or gradient, same on export
                fill: simpleMakerConfiguration.backgroundFill,
                color: simpleMakerConfiguration.backgroundColor == Color(uiColor: .secondarySystemBackground)
                    ? (colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : .white)
                    : simpleMakerConfiguration.backgroundColor
            )
            
            if let image = simpleMakerConfiguration.selectedImage {
                // FEATURE-03: framed by the shared, non-destructive recipe solver.
                Image(uiImage: ThumbnailCutoutImageCache.shared.resolvedImage( // FEATURE-11
                    image: image,
                    identity: ThumbnailDocumentLayer.backgroundID,
                    mask: simpleMakerConfiguration.layers.cutout(forLayerID: ThumbnailDocumentLayer.backgroundID)
                ))
                    .framed(ThumbnailImageGeometry.solve(
                        sourceSize: image.size,
                        frameSize: CGSize(width: width, height: height),
                        recipe: simpleMakerConfiguration.imageRecipe
                    ))
                    .thumbnailAdjustments( // FEATURE-14
                        simpleMakerConfiguration.layers.renderAdjustments(forLayerID: ThumbnailDocumentLayer.backgroundID),
                        renderedSize: CGSize(width: width, height: height)
                    )
                    .accessibilityLabel("Selected thumbnail image")
            } else if simpleMakerConfiguration.overlayText.isEmpty
                && !simpleMakerConfiguration.layers.hasContentLayers {
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
                .accessibilityLabel("Image selection placeholder")
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
        if layer.id == ThumbnailDocumentLayer.textID {
            textWithFont
        } else if case .image(let content) = layer.content {
            let isSelected = selectedOverlay.wrappedValue == .content(layer.id)
            ContentImageLayerCanvasItem(
                layer: layer,
                width: width,
                height: height,
                isInteractive: isTextInteractive,
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
                    simpleMakerConfiguration.layers.updateImageContent(id: layer.id) { content in
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
                isInteractive: isTextInteractive,
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
                    simpleMakerConfiguration.layers.updateTextContent(id: layer.id) { content in
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
                isInteractive: isTextInteractive,
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
                    simpleMakerConfiguration.layers.updateShapeContent(id: layer.id) { content in
                        content = nextContent
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private var textWithFont: some View {
        let text = simpleMakerConfiguration.overlayText
        if !text.isEmpty && isTextLayerVisible {
        let fontSize = overlayFontSize(for: text) // GAPS: main-title auto-fit

        let needsFallback = FontManager.shared.needsFallback(
            for: text,
            selectedFont: simpleMakerConfiguration.selectedFont
        )

        // FEATURE-04: one styled renderer; nil style == the legacy look.
        let textLayer = StyledThumbnailTextView.overlay(
            text: text,
            font: simpleMakerConfiguration.selectedFont,
            color: simpleMakerConfiguration.textColor,
            fontSize: fontSize,
            style: simpleMakerConfiguration.textStyle,
            canvasSize: CGSize(width: width, height: height)
        )
            .accessibilityIdentifier(isTextInteractive ? "overlayTextLayer" : "overlayTextPreviewLayer")
            .accessibilityValue(
                simpleMakerConfiguration.textTransform.canvasStateDescription(size: effectiveTextSize)
            )
            .onAppear { simpleMakerConfiguration.usesFallbackFont = needsFallback }
            .onChange(of: needsFallback) { oldValue, newValue in
                simpleMakerConfiguration.usesFallbackFont = newValue
            }
            .rotationEffect(
                .degrees(
                    simpleMakerConfiguration.textTransform.rotationDegrees
                        + textRotationDelta.degrees
                        + textHandleRotationDelta
                )
            )
            .scaleEffect(
                x: simpleMakerConfiguration.textTransform.isFlippedHorizontally ? -1 : 1,
                y: 1
            )
            .position(textLayerPosition)
            .preference(key: CenterSnapGuidePreferenceKey.self, value: textSnapGuide)

        if isTextInteractive {
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
    private var selectedManipulationChrome: some View {
        textManipulationChrome
        contentManipulationChrome
    }

    @ViewBuilder
    private var textManipulationChrome: some View {
        let text = simpleMakerConfiguration.overlayText
        if isTextInteractive
            && selectedOverlay.wrappedValue == .textOverlay
            && !isTextLayerLocked
            && !text.isEmpty
            && isTextLayerVisible {
            let fontSize = overlayFontSize(for: text) // GAPS: main-title auto-fit
            // FEATURE-04: hit/chrome proxy shares the rendered text geometry.
            StyledThumbnailTextView.overlay(
                text: text,
                font: simpleMakerConfiguration.selectedFont,
                color: simpleMakerConfiguration.textColor,
                fontSize: fontSize,
                style: simpleMakerConfiguration.textStyle,
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
                            simpleMakerConfiguration.textTransform.flipHorizontally()
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
                        simpleMakerConfiguration.textTransform.rotationDegrees
                            + textRotationDelta.degrees
                            + textHandleRotationDelta
                    )
                )
                .scaleEffect(
                    x: simpleMakerConfiguration.textTransform.isFlippedHorizontally ? -1 : 1,
                    y: 1
                )
                .position(textLayerPosition)
        }
    }

    @ViewBuilder
    private var contentManipulationChrome: some View {
        if isTextInteractive,
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

    private var selectedContentLayer: ThumbnailDocumentLayer? {
        guard case .content(let layerID) = selectedOverlay.wrappedValue,
              let layer = simpleMakerConfiguration.layers.record(id: layerID),
              layer.isVisible,
              layer.content != nil else {
            return nil
        }

        return layer
    }

    private var textLayerPosition: CGPoint {
        let position = ThumbnailOverlayTransform.normalizedPosition(
            x: simpleMakerConfiguration.textTransform.x,
            y: simpleMakerConfiguration.textTransform.y,
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

    private var textSnapGuide: CenterSnapGuide {
        guard isTextDragging else { return [] }

        return ThumbnailOverlayTransform.centerSnapGuide(
            for: simpleMakerConfiguration.textTransform,
            translation: textDragTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    /// GAPS: the main title's draw size; auto-fit shrinks it into its box.
    private func overlayFontSize(for text: String) -> CGFloat {
        ThumbnailTextAutoFit.overlayFontSize(
            text: text,
            font: simpleMakerConfiguration.selectedFont,
            requested: height * effectiveTextSize,
            style: simpleMakerConfiguration.textStyle,
            autoFit: simpleMakerConfiguration.overlayAutoFit,
            canvasSize: CGSize(width: width, height: height)
        )
    }

    private var effectiveTextSize: CGFloat {
        Self.adjustedTextSize(
            simpleMakerConfiguration.textSize,
            by: textResizeTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    private var isTextLayerVisible: Bool {
        simpleMakerConfiguration.layers.isVisible(ThumbnailEditorLayer.text)
    }

    private var isTextLayerLocked: Bool {
        simpleMakerConfiguration.layers.isLocked(ThumbnailEditorLayer.text)
    }

    private var renderableLayerRecords: [ThumbnailDocumentLayer] {
        let selections = simpleMakerConfiguration.layers.selectableLayerSelections(
            hasText: !simpleMakerConfiguration.overlayText.isEmpty,
            hasProfile: false
        )

        return simpleMakerConfiguration.layers.sortedSelections(selections).compactMap { selection in
            guard let record = simpleMakerConfiguration.layers.record(for: selection)
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
            return nil
        case .content:
            return nil
        }
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
                let groupStart = simpleMakerConfiguration.arrangeCenter(for: .textOverlay) // FEATURE-07
                simpleMakerConfiguration.textTransform.moveWithSnap(
                    by: value.translation,
                    in: CGSize(width: width, height: height)
                )
                if let followed = simpleMakerConfiguration.followingGroupMove(of: .textOverlay, from: groupStart) {
                    simpleMakerConfiguration = followed // FEATURE-07: the rest of the group follows
                }
            }
    }

    private var textRotationGesture: some Gesture {
        RotationGesture()
            .updating($textRotationDelta) { value, state, _ in
                state = value
            }
            .onEnded { value in
                simpleMakerConfiguration.textTransform.rotate(by: value.degrees)
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
                    simpleMakerConfiguration.textSize = Self.adjustedTextSize(
                        simpleMakerConfiguration.textSize,
                        by: value.translation,
                        in: CGSize(width: width, height: height)
                    )
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
                    simpleMakerConfiguration.textTransform.rotate(
                        by: textHandleRotationDelta(for: value)
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
                    let groupStart = simpleMakerConfiguration.arrangeCenter(for: .content(layerID)) // FEATURE-07
                    var nextTransform = transform
                    nextTransform.moveWithSnap(
                        by: value.translation,
                        in: CGSize(width: width, height: height)
                    )
                    updateTransform(nextTransform)
                    if let followed = simpleMakerConfiguration.followingGroupMove(of: .content(layerID), from: groupStart) {
                        simpleMakerConfiguration = followed // FEATURE-07: the rest of the group follows
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
        simpleMakerConfiguration.layers.updateImageContent(id: layerID, mutate: mutate)
    }

    private func updateTextContent(
        layerID: String,
        mutate: (inout ThumbnailTextLayerContent) -> Void
    ) {
        simpleMakerConfiguration.layers.updateTextContent(id: layerID, mutate: mutate)
    }

    private func updateShapeContent(
        layerID: String,
        mutate: (inout ThumbnailShapeLayerContent) -> Void
    ) {
        simpleMakerConfiguration.layers.updateShapeContent(id: layerID, mutate: mutate)
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
        simpleMakerConfiguration.textTransform.rotate(by: degrees)
    }

    private func resizeTextOverlay(by delta: CGFloat) {
        selectedOverlay.wrappedValue = .textOverlay
        simpleMakerConfiguration.textSize = Self.adjustedTextSize(
            simpleMakerConfiguration.textSize,
            by: delta
        )
    }

    private func nudgeTextOverlay(dx: CGFloat, dy: CGFloat) {
        selectedOverlay.wrappedValue = .textOverlay
        simpleMakerConfiguration.textTransform.move(
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

struct ContentImageLayerCanvasItem: View {
    let layer: ThumbnailDocumentLayer
    let width: CGFloat
    let height: CGFloat
    let isInteractive: Bool
    let isSelected: Bool
    let isDragging: Bool
    let dragTranslation: CGSize
    let rotationDelta: Angle
    let handleRotationDelta: Double
    let resizeTranslation: CGSize
    let select: () -> Void
    let dragGesture: AnyGesture<Void>
    let rotationGesture: AnyGesture<Void>
    let updateContent: (ThumbnailImageLayerContent) -> Void
    private static let accessibilityRotationStep = 5.0
    private static let accessibilitySizeStep: CGFloat = 0.02
    private static let accessibilityMoveStep: CGFloat = 0.02

    var body: some View {
        if case .image(let content) = layer.content,
           let image = ThumbnailCutoutImageCache.shared.resolvedImage( // FEATURE-11: synchronous, so export matches
            imageData: content.imageData,
            identity: layer.id,
            mask: layer.cutout
           ) {
            let imageSize = ContentLayerCanvasGeometry.imageFrameSize(
                for: image,
                content: content,
                resizeTranslation: resizeTranslation,
                canvasSize: CGSize(width: width, height: height)
            )
            let hitSize = ContentLayerCanvasGeometry.hitSize(for: imageSize)

            ZStack {
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: hitSize.width, height: hitSize.height)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageSize.width, height: imageSize.height)
                        .thumbnailAdjustments(layer.adjustments, renderedSize: imageSize) // FEATURE-14
                }
                .frame(width: hitSize.width, height: hitSize.height)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(isInteractive ? "imageContentLayer-\(layer.id)" : "imageContentPreviewLayer-\(layer.id)")
                .accessibilityLabel(layer.name.isEmpty ? "Image layer" : layer.name)
                .accessibilityValue(content.transform.canvasStateDescription(size: CGFloat(content.size)))
                .modifier(
                    ContentImageLayerInteractionModifier(
                        isInteractive: isInteractive,
                        isLocked: layer.isLocked,
                        select: select,
                        dragGesture: dragGesture,
                        rotationGesture: rotationGesture,
                        moveUpAction: {
                            nudgeContent(content, dx: 0, dy: -Self.accessibilityMoveStep)
                        },
                        moveDownAction: {
                            nudgeContent(content, dx: 0, dy: Self.accessibilityMoveStep)
                        },
                        moveLeftAction: {
                            nudgeContent(content, dx: -Self.accessibilityMoveStep, dy: 0)
                        },
                        moveRightAction: {
                            nudgeContent(content, dx: Self.accessibilityMoveStep, dy: 0)
                        }
                    )
                )
            }
            .frame(width: hitSize.width, height: hitSize.height)
            .rotationEffect(
                .degrees(
                    content.transform.rotationDegrees
                        + rotationDelta.degrees
                        + handleRotationDelta
                )
            )
            .scaleEffect(
                x: content.transform.isFlippedHorizontally ? -1 : 1,
                y: 1
            )
            .position(position(for: content))
            .preference(key: CenterSnapGuidePreferenceKey.self, value: snapGuide(for: content))
        }
    }

    private func position(for content: ThumbnailImageLayerContent) -> CGPoint {
        let position = ThumbnailOverlayTransform.normalizedPosition(
            x: content.transform.x,
            y: content.transform.y,
            translation: dragTranslation,
            in: CGSize(width: width, height: height),
            snapping: isDragging
        )
        return CGPoint(x: width * position.x, y: height * position.y)
    }

    private func snapGuide(for content: ThumbnailImageLayerContent) -> CenterSnapGuide {
        guard isDragging else { return [] }

        return ThumbnailOverlayTransform.centerSnapGuide(
            for: content.transform,
            translation: dragTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    private func rotateContent(_ content: ThumbnailImageLayerContent, by degrees: Double) {
        var nextContent = content
        nextContent.transform.rotate(by: degrees)
        updateContent(nextContent)
        select()
    }

    private func resizeContent(_ content: ThumbnailImageLayerContent, by delta: CGFloat) {
        var nextContent = content
        nextContent.size = Double(min(
            ContentLayerCanvasGeometry.imageSizeLimits.upperBound,
            max(ContentLayerCanvasGeometry.imageSizeLimits.lowerBound, CGFloat(content.size) + delta)
        ))
        updateContent(nextContent)
        select()
    }

    private func nudgeContent(_ content: ThumbnailImageLayerContent, dx: CGFloat, dy: CGFloat) {
        var nextContent = content
        nextContent.transform.move(
            by: CGSize(width: width * dx, height: height * dy),
            in: CGSize(width: width, height: height)
        )
        updateContent(nextContent)
        select()
    }
}

struct ContentTextLayerCanvasItem: View {
    let layer: ThumbnailDocumentLayer
    let width: CGFloat
    let height: CGFloat
    let isInteractive: Bool
    let isSelected: Bool
    let isDragging: Bool
    let dragTranslation: CGSize
    let rotationDelta: Angle
    let handleRotationDelta: Double
    let resizeTranslation: CGSize
    let select: () -> Void
    let dragGesture: AnyGesture<Void>
    let rotationGesture: AnyGesture<Void>
    let updateContent: (ThumbnailTextLayerContent) -> Void
    private static let accessibilityRotationStep = 5.0
    private static let accessibilitySizeStep: CGFloat = 0.02
    private static let accessibilityMoveStep: CGFloat = 0.02

    var body: some View {
        if case .text(let content) = layer.content {
            let frameSize = ContentLayerCanvasGeometry.textFrameSize(
                for: content,
                resizeTranslation: resizeTranslation,
                canvasSize: CGSize(width: width, height: height)
            )
            let hitSize = ContentLayerCanvasGeometry.hitSize(for: frameSize)
            // DONOR auto-fit: shrinks to the box when the layer opts in.
            let fontSize = content.renderedFontSize(
                normalizedSize: effectiveSize(for: content),
                canvasSize: CGSize(width: width, height: height),
                boxSize: frameSize
            )
            let displayText = content.value.isEmpty ? "Text" : content.value

            ZStack {
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: hitSize.width, height: hitSize.height)

                    // FEATURE-04: one styled renderer; nil style == the legacy look.
                    StyledThumbnailTextView.contentLayer(
                        text: displayText,
                        font: content.selectedFont,
                        color: content.color.color,
                        fontSize: fontSize,
                        style: content.style,
                        canvasSize: CGSize(width: width, height: height),
                        boxSize: frameSize
                    )
                    .frame(width: frameSize.width, height: frameSize.height)
                }
                .frame(width: hitSize.width, height: hitSize.height)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(isInteractive ? "textContentLayer-\(layer.id)" : "textContentPreviewLayer-\(layer.id)")
                .accessibilityLabel(layer.name.isEmpty ? "Text layer" : layer.name)
                .accessibilityValue(
                    "\(displayText). \(content.transform.canvasStateDescription(size: CGFloat(content.size)))"
                )
                .modifier(
                    ContentImageLayerInteractionModifier(
                        isInteractive: isInteractive,
                        isLocked: layer.isLocked,
                        select: select,
                        dragGesture: dragGesture,
                        rotationGesture: rotationGesture,
                        moveUpAction: {
                            nudgeContent(content, dx: 0, dy: -Self.accessibilityMoveStep)
                        },
                        moveDownAction: {
                            nudgeContent(content, dx: 0, dy: Self.accessibilityMoveStep)
                        },
                        moveLeftAction: {
                            nudgeContent(content, dx: -Self.accessibilityMoveStep, dy: 0)
                        },
                        moveRightAction: {
                            nudgeContent(content, dx: Self.accessibilityMoveStep, dy: 0)
                        }
                    )
                )
            }
            .frame(width: hitSize.width, height: hitSize.height)
            .rotationEffect(
                .degrees(
                    content.transform.rotationDegrees
                        + rotationDelta.degrees
                        + handleRotationDelta
                )
            )
            .scaleEffect(
                x: content.transform.isFlippedHorizontally ? -1 : 1,
                y: 1
            )
            .position(position(for: content))
            .preference(key: CenterSnapGuidePreferenceKey.self, value: snapGuide(for: content))
        }
    }

    private func effectiveSize(for content: ThumbnailTextLayerContent) -> CGFloat {
        ContentLayerCanvasGeometry.adjustedTextSize(
            CGFloat(content.size),
            by: resizeTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    private func position(for content: ThumbnailTextLayerContent) -> CGPoint {
        let position = ThumbnailOverlayTransform.normalizedPosition(
            x: content.transform.x,
            y: content.transform.y,
            translation: dragTranslation,
            in: CGSize(width: width, height: height),
            snapping: isDragging
        )
        return CGPoint(x: width * position.x, y: height * position.y)
    }

    private func snapGuide(for content: ThumbnailTextLayerContent) -> CenterSnapGuide {
        guard isDragging else { return [] }

        return ThumbnailOverlayTransform.centerSnapGuide(
            for: content.transform,
            translation: dragTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    private func rotateContent(_ content: ThumbnailTextLayerContent, by degrees: Double) {
        var nextContent = content
        nextContent.transform.rotate(by: degrees)
        updateContent(nextContent)
        select()
    }

    private func resizeContent(_ content: ThumbnailTextLayerContent, by delta: CGFloat) {
        var nextContent = content
        nextContent.size = Double(min(
            ContentLayerCanvasGeometry.textSizeLimits.upperBound,
            max(ContentLayerCanvasGeometry.textSizeLimits.lowerBound, CGFloat(content.size) + delta)
        ))
        updateContent(nextContent)
        select()
    }

    private func nudgeContent(_ content: ThumbnailTextLayerContent, dx: CGFloat, dy: CGFloat) {
        var nextContent = content
        nextContent.transform.move(
            by: CGSize(width: width * dx, height: height * dy),
            in: CGSize(width: width, height: height)
        )
        updateContent(nextContent)
        select()
    }
}

struct ContentShapeLayerCanvasItem: View {
    let layer: ThumbnailDocumentLayer
    let width: CGFloat
    let height: CGFloat
    let isInteractive: Bool
    let isSelected: Bool
    let isDragging: Bool
    let dragTranslation: CGSize
    let rotationDelta: Angle
    let handleRotationDelta: Double
    let resizeTranslation: CGSize
    let select: () -> Void
    let dragGesture: AnyGesture<Void>
    let rotationGesture: AnyGesture<Void>
    let updateContent: (ThumbnailShapeLayerContent) -> Void
    private static let accessibilityRotationStep = 5.0
    private static let accessibilitySizeStep: CGFloat = 0.02
    private static let accessibilityMoveStep: CGFloat = 0.02

    var body: some View {
        if case .shape(let content) = layer.content {
            let shapeSize = ContentLayerCanvasGeometry.shapeFrameSize(
                for: content,
                resizeTranslation: resizeTranslation,
                canvasSize: CGSize(width: width, height: height)
            )
            let hitSize = ContentLayerCanvasGeometry.hitSize(for: shapeSize)

            ZStack {
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: hitSize.width, height: hitSize.height)

                    shapeView(content: content, size: shapeSize)
                        .frame(width: shapeSize.width, height: shapeSize.height)
                }
                .frame(width: hitSize.width, height: hitSize.height)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(isInteractive ? "shapeContentLayer-\(layer.id)" : "shapeContentPreviewLayer-\(layer.id)")
                .accessibilityLabel(ThumbnailShapeAccessibility.label(name: layer.name, content: content))
                .accessibilityValue(
                    content.transform.canvasStateDescription(
                        width: CGFloat(content.width),
                        height: CGFloat(content.height)
                    )
                )
                .modifier(
                    ContentImageLayerInteractionModifier(
                        isInteractive: isInteractive,
                        isLocked: layer.isLocked,
                        select: select,
                        dragGesture: dragGesture,
                        rotationGesture: rotationGesture,
                        moveUpAction: {
                            nudgeContent(content, dx: 0, dy: -Self.accessibilityMoveStep)
                        },
                        moveDownAction: {
                            nudgeContent(content, dx: 0, dy: Self.accessibilityMoveStep)
                        },
                        moveLeftAction: {
                            nudgeContent(content, dx: -Self.accessibilityMoveStep, dy: 0)
                        },
                        moveRightAction: {
                            nudgeContent(content, dx: Self.accessibilityMoveStep, dy: 0)
                        }
                    )
                )
            }
            .frame(width: hitSize.width, height: hitSize.height)
            .rotationEffect(
                .degrees(
                    content.transform.rotationDegrees
                        + rotationDelta.degrees
                        + handleRotationDelta
                )
            )
            .scaleEffect(
                x: content.transform.isFlippedHorizontally ? -1 : 1,
                y: 1
            )
            .position(position(for: content))
            .preference(key: CenterSnapGuidePreferenceKey.self, value: snapGuide(for: content))
        }
    }

    @ViewBuilder
    private func shapeView(content: ThumbnailShapeLayerContent, size: CGSize) -> some View {
        let lineWidth = max(1, min(width, height) * CGFloat(content.strokeWidth))
        switch content.shapeKind {
        case .rectangle:
            RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.08, style: .continuous)
                .fill(content.fillColor.color)
                .overlay {
                    if let strokeColor = content.strokeColor {
                        RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.08, style: .continuous)
                            .stroke(strokeColor.color, lineWidth: lineWidth)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // FEATURE-12: renders nothing unless the shape has a label.
                    ThumbnailShapeLabelView(content: content, size: size)
                }
        case .ellipse:
            Ellipse()
                .fill(content.fillColor.color)
                .overlay {
                    if let strokeColor = content.strokeColor {
                        Ellipse()
                            .stroke(strokeColor.color, lineWidth: lineWidth)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // FEATURE-12: renders nothing unless the shape has a label.
                    ThumbnailShapeLabelView(content: content, size: size)
                }
        default:
            // FEATURE-12: arrows, badges and callouts.
            ThumbnailShapeRenderView(content: content, canvasSize: CGSize(width: width, height: height), size: size)
        }
    }

    private func position(for content: ThumbnailShapeLayerContent) -> CGPoint {
        let position = ThumbnailOverlayTransform.normalizedPosition(
            x: content.transform.x,
            y: content.transform.y,
            translation: dragTranslation,
            in: CGSize(width: width, height: height),
            snapping: isDragging
        )
        return CGPoint(x: width * position.x, y: height * position.y)
    }

    private func snapGuide(for content: ThumbnailShapeLayerContent) -> CenterSnapGuide {
        guard isDragging else { return [] }

        return ThumbnailOverlayTransform.centerSnapGuide(
            for: content.transform,
            translation: dragTranslation,
            in: CGSize(width: width, height: height)
        )
    }

    private func rotateContent(_ content: ThumbnailShapeLayerContent, by degrees: Double) {
        var nextContent = content
        nextContent.transform.rotate(by: degrees)
        updateContent(nextContent)
        select()
    }

    private func resizeContent(_ content: ThumbnailShapeLayerContent, by delta: CGFloat) {
        var nextContent = content
        nextContent.width = Double(min(
            ContentLayerCanvasGeometry.shapeWidthLimits.upperBound,
            max(ContentLayerCanvasGeometry.shapeWidthLimits.lowerBound, CGFloat(content.width) + delta)
        ))
        nextContent.height = Double(min(
            ContentLayerCanvasGeometry.shapeHeightLimits.upperBound,
            max(ContentLayerCanvasGeometry.shapeHeightLimits.lowerBound, CGFloat(content.height) + delta)
        ))
        updateContent(nextContent)
        select()
    }

    private func nudgeContent(_ content: ThumbnailShapeLayerContent, dx: CGFloat, dy: CGFloat) {
        var nextContent = content
        nextContent.transform.move(
            by: CGSize(width: width * dx, height: height * dy),
            in: CGSize(width: width, height: height)
        )
        updateContent(nextContent)
        select()
    }
}

private struct ContentImageLayerInteractionModifier: ViewModifier {
    let isInteractive: Bool
    let isLocked: Bool
    let select: () -> Void
    let dragGesture: AnyGesture<Void>
    let rotationGesture: AnyGesture<Void>
    let moveUpAction: () -> Void
    let moveDownAction: () -> Void
    let moveLeftAction: () -> Void
    let moveRightAction: () -> Void

    func body(content: Content) -> some View {
        if isInteractive {
            let selectableContent = content
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isButton)
                .simultaneousGesture(TapGesture().onEnded(select))

            if isLocked {
                selectableContent
            } else {
                selectableContent
                    .overlayMoveAccessibilityActions(
                        moveUp: moveUpAction,
                        moveDown: moveDownAction,
                        moveLeft: moveLeftAction,
                        moveRight: moveRightAction
                    )
                    .gesture(dragGesture)
                    .simultaneousGesture(rotationGesture)
            }
        } else {
            content
        }
    }
}

extension View {
    func overlayMoveAccessibilityActions(
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        moveLeft: @escaping () -> Void,
        moveRight: @escaping () -> Void
    ) -> some View {
        self
            .accessibilityAction(named: Text("Move Up")) {
                moveUp()
            }
            .accessibilityAction(named: Text("Move Down")) {
                moveDown()
            }
            .accessibilityAction(named: Text("Move Left")) {
                moveLeft()
            }
            .accessibilityAction(named: Text("Move Right")) {
                moveRight()
            }
    }
}

//#Preview {
//    PreviewComponentView()
//}
