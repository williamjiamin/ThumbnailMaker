//
//  AccessibleMenuPicker.swift
//  ThumbnailMaker
//
//  APP-07: a Form menu picker that never clips. Its current value is a
//  wrapping text label (a system menu picker keeps the value on one line),
//  and at accessibility text sizes the value moves under its title. AnyLayout
//  keeps the same views in both arrangements.
//

import SwiftUI

struct AccessibleMenuPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    /// The spoken and visible name of the current selection.
    let valueName: String
    @Binding var selection: SelectionValue
    @ViewBuilder let content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        _ title: String,
        valueName: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.valueName = valueName
        _selection = selection
        self.content = content
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        layout {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Picker(title, selection: $selection, content: content)
                    .pickerStyle(.inline)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(valueName)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(title)
            .accessibilityValue(valueName)
        }
    }
}
