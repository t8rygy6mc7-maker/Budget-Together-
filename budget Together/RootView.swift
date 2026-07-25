import SwiftUI

@main
struct BudgetTogetherApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var showSheet = false

    var body: some View {
        Group {
            if model.hasHousehold {
                main
            } else {
                PairingView()
            }
        }
        .background(Palette.screen.ignoresSafeArea())
        .environmentObject(model)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .preferredColorScheme(.dark)
    }

    private var main: some View {
        ScrollView(showsIndicators: false) {
            Group {
                switch model.tab {
                case .home:   HomeView()
                case .log:    LogView()
                case .budget: BudgetView()
                case .stats:  StatsView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(showSheet: $showSheet)
        }
        .sheet(isPresented: $showSheet) { AddSheet().environmentObject(model) }
        // Asked once the user is actually in a household — permission prompts
        // before there's anything to alert about get declined.
        .onAppear { Notifier.shared.start() }
    }
}

// MARK: - Bottom navigation

struct BottomBar: View {
    @EnvironmentObject var model: AppModel
    @Binding var showSheet: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                navButton(.home)
                navButton(.log)
                Spacer().frame(width: 56)   // gap for the floating add button
                navButton(.budget)
                navButton(.stats)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 11)
            .background(Palette.navBar)
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.navBorder).frame(height: 1)
            }

            Button { showSheet = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Palette.tealInk)
                    .frame(width: 56, height: 56)
                    .background(Palette.tealGradient,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Palette.teal.opacity(0.55), radius: 13, x: 0, y: 12)
            }
            .accessibilityLabel("Add a spend")
            .offset(y: -24)
        }
    }

    private func navButton(_ tab: Tab) -> some View {
        let isSelected = model.tab == tab
        return Button { model.tab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol).font(.system(size: 20, weight: .medium))
                Text(tab.title).font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Palette.teal : Palette.muted)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Shared rows

/// Steps the whole app between months. Forward stops at the current month,
/// since there's nothing to show past it; tapping the label jumps back to today.
struct MonthStepper: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            arrow("chevron.left", enabled: true) { model.stepMonth(-1) }
            Button { model.goToCurrentMonth() } label: {
                Text(model.monthTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.isCurrentMonth ? Palette.sub : Palette.teal)
                    .frame(minWidth: 96)
            }
            .accessibilityLabel(model.isCurrentMonth ? model.monthTitle
                                                     : "\(model.monthTitle), back to this month")
            arrow("chevron.right", enabled: model.canGoForward) { model.stepMonth(1) }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Palette.chipText : Palette.muted.opacity(0.4))
                .frame(width: 26, height: 26)
                .background(Palette.chip, in: Circle())
        }
        .disabled(!enabled)
        .accessibilityLabel(symbol == "chevron.left" ? "Previous month" : "Next month")
    }
}

/// A member's initial on their colour. `ring` draws the separating outline used
/// where avatars overlap in a stack.
struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 32
    var ring: Color?

    var body: some View {
        Text(member.letter)
            .font(.system(size: size * 0.375, weight: .bold))
            .foregroundStyle(member.ink)
            .frame(width: size, height: size)
            .background(member.color, in: Circle())
            .overlay {
                if let ring { Circle().strokeBorder(ring, lineWidth: 2) }
            }
            .accessibilityLabel(member.name)
    }
}

struct EntryRow: View {
    @EnvironmentObject var model: AppModel
    let entry: Entry
    var showDelete = false

    var body: some View {
        let bucket = Bucket.named(entry.bucket)
        let member = model.member(entry.memberID)
        HStack(spacing: 12) {
            Image(systemName: bucket.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(bucket.color)
                .frame(width: 36, height: 36)
                .background(bucket.tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.place).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(bucket.label).font(.system(size: 11.5)).foregroundStyle(Palette.sub)
            }

            Spacer(minLength: 4)

            // With more than two people a bare dot stops being readable, so the
            // initial rides along with it.
            HStack(spacing: 4) {
                Circle().fill(member.color).frame(width: 8, height: 8)
                Text(member.letter)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.sub)
            }
            .accessibilityLabel(member.name)

            Text(entry.signedAmount).mono(14).foregroundStyle(entry.kind.color)

            if showDelete {
                Button { model.delete(entry.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                .accessibilityLabel("Delete \(entry.place)")
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .card(border: Palette.cardBorderSoft, radius: 15)
    }
}

// MARK: - Progress bar

struct ProgressBar<Fill: ShapeStyle>: View {
    let pct: Double
    let fill: Fill
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.field)
                Capsule().fill(fill)
                    .frame(width: max(0, geo.size.width * pct / 100))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Preview harness

/// Wraps a screen in the chrome `RootView` normally supplies, backed by the
/// in-memory demo store.
struct PreviewShell<Content: View>: View {
    @ViewBuilder var content: Content
    @StateObject private var model = AppModel.preview

    var body: some View {
        ScrollView(showsIndicators: false) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
        .background(Palette.screen.ignoresSafeArea())
        .environmentObject(model)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .preferredColorScheme(.dark)
    }
}
