//
//  AppShellSupport.swift
//  ThumbnailMaker
//
//  SHELL (1.1.0 rebuild): small pieces shared by the tab shell, the Create
//  home, the Quick Create wizard and the editors.
//

import SwiftUI

enum AppShellTab: Hashable {
    case create
    case projects
    case settings
}

/// GAPS: which editor's projects the Projects tab lists.
enum ProjectsTabEditorFilter: String, CaseIterable, Identifiable {
    case simple
    case premium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: "Simple"
        case .premium: "Premium"
        }
    }

    var editorMode: ThumbnailDocumentEditorMode {
        switch self {
        case .simple: .simple
        case .premium: .premium
        }
    }

    var createStage: CreateStage {
        switch self {
        case .simple: .simpleEditor
        case .premium: .premiumEditor
        }
    }
}

/// What the Create tab is showing.
enum CreateStage: Equatable {
    case home
    case simpleEditor
    case premiumEditor

    /// UI tests (and screenshot automation) that drive the editor directly
    /// pass `-UITestSkipHome`; `-UITestStartPremiumTab` keeps its old meaning
    /// of "start in the Premium editor".
    static func initial(arguments: [String]) -> CreateStage {
        if arguments.contains("-UITestStartPremiumTab") {
            return .premiumEditor
        }
        if arguments.contains("-UITestSkipHome") {
            return .simpleEditor
        }
        return .home
    }
}

enum QuickCreateTheme {
    static let gradientStart = Color(red: 0.40, green: 0.42, blue: 0.91)
    static let gradientEnd = Color(red: 0.69, green: 0.44, blue: 0.86)

    static var gradient: LinearGradient {
        LinearGradient(colors: [gradientStart, gradientEnd], startPoint: .leading, endPoint: .trailing)
    }
}

private struct ShowCreateHomeKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Set by the app shell on its editors: returns the Create tab to Home.
    /// nil (the default) hides the Home button, e.g. in previews.
    var showCreateHome: (() -> Void)? {
        get { self[ShowCreateHomeKey.self] }
        set { self[ShowCreateHomeKey.self] = newValue }
    }
}

struct CreateHomeToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "house")
                .minimumHitTarget()
        }
        .accessibilityIdentifier("showHomeButton")
        .accessibilityLabel("Home")
        .accessibilityHint("Returns to Create a Thumbnail.")
    }
}

extension Binding where Value == ThumbnailDocumentColor {
    /// Edits a document colour with a SwiftUI ColorPicker.
    var swiftUIColor: Binding<Color> {
        Binding<Color>(
            get: { wrappedValue.color },
            set: { wrappedValue = ThumbnailDocumentColor(color: $0) }
        )
    }
}
