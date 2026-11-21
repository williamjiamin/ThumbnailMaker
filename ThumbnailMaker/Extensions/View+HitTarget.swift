//
//  View+HitTarget.swift
//  ThumbnailMaker
//
//  APP-07: a 44 x 44 pt minimum hit target without enlarging the visuals.
//  Apply it to a button's *label* (a frame on the Button itself does not
//  grow its accessibility frame), e.g. `Button { } label: { Text("Undo").minimumHitTarget() }`.
//

import SwiftUI

extension View {
    func minimumHitTarget(alignment: Alignment = .center) -> some View {
        frame(minWidth: 44, minHeight: 44, alignment: alignment)
            .contentShape(Rectangle())
    }
}

/// A tinted capsule button that grows with Dynamic Type (the bordered styles
/// stop scaling at accessibility sizes) and keeps a 44 pt minimum height.
struct TintedCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                Capsule().fill(Color.accentColor.opacity(configuration.isPressed ? 0.24 : 0.14))
            )
            .contentShape(Capsule())
    }
}

extension View {
    /// APP-07/08: a pinned bottom action bar at standard text sizes. At
    /// accessibility sizes the bar would cover much of a phone screen (and the
    /// text it hides), so the caller shows it inline at the end of its list
    /// instead; see `showsInlineActionBar`.
    @ViewBuilder
    func pinnedActionBar<Bar: View>(
        isInline: Bool,
        @ViewBuilder bar: () -> Bar
    ) -> some View {
        if isInline {
            self
        } else {
            // Laid out below the content rather than floated over it, so the
            // bar never sits on top of (and cuts through) list text.
            VStack(spacing: 0) {
                self
                bar()
            }
        }
    }
}

/// A full-width primary action that grows with Dynamic Type: its title
/// wraps instead of being clipped by a fixed-height system capsule.
struct ProminentActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
