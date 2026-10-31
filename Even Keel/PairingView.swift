import SwiftUI

// MARK: - Pairing / onboarding
//
// Shown when this device hasn't joined a budget yet. The owner creates one
// here; a partner joins by opening the invite link, which iOS delivers straight
// to the app (see `SceneDelegate`), so there's no code to type in.
//
// Three deliberate changes from the first version of this screen, all aimed at
// the same thing — that a money app's first screen is where most people decide
// it isn't for them:
//
// 1. **You can look before you decide.** "Have a look around first" fills the
//    app with a worked example. Nothing else here is a commitment either, but
//    that one is visibly, obviously reversible.
//
// 2. **The budget question is optional and folded away.** It used to be a
//    required field above the button, which asked people to name a monthly
//    figure before they'd seen a single screen. Most don't know it; the ones
//    who do still resent guessing. Left blank, the app starts with no limits
//    at all and offers to work them out later from real spending.
//
// 3. **The trust promise is stated, not implied.** No bank login, nothing
//    leaves the phone. It's the app's biggest advantage over everything else in
//    the category and it went unmentioned.

struct PairingView: View {
    @EnvironmentObject var model: AppModel
    @State private var name = "Together"
    @State private var yourName = ""
    @State private var monthlyTotal = ""
    @State private var showBudgetField = false
    @FocusState private var focusedField: Field?

    private enum Field { case budget, you, total }

    /// Says what the number will actually do, so it doesn't read as a
    /// commitment the user has to get right.
    private var planNote: String {
        guard let total = Fmt.amount(from: monthlyTotal) else {
            return "Leave this blank and the app just tracks what you spend. "
                 + "Once it's seen a few weeks, it'll offer limits based on that."
        }
        return "We'll split \(Fmt.money(total)) across the categories to start. "
             + "Change any of it later."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: Space.xl)

                Image(systemName: "heart.text.square.fill")
                    .appFont(34, weight: .semibold)
                    .foregroundStyle(Palette.tealInk)
                    .frame(width: 74, height: 74)
                    .background(Palette.tealGradient,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.bottom, Space.lg)

                Text("Share a budget,\ntogether")
                    .appFont(28, weight: .bold)
                    .foregroundStyle(Palette.text)
                    .padding(.bottom, Space.xs)
                Text("One budget, however many of you there are. Add everyone who spends "
                   + "from it — entries stay in sync on every phone through iCloud.")
                    .appFont(13)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.lg)

                VStack(spacing: Space.md) {
                    trustCard
                    createCard
                    RowGroup {
                        lookAroundButton
                        joinHint
                    }
                }

                Spacer(minLength: Space.xxl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.md)
            .readableColumn()
        }
    }

    // MARK: - Sections

    /// The reason to trust this thing with your money, stated first. Everything
    /// scary about finance apps — handing over bank credentials, data sold on,
    /// a stranger seeing your spending — is something this app simply doesn't
    /// do, and saying so plainly is worth more than any feature on the list.
    private var trustCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            promise("lock.fill", "No bank login, ever",
                    "You type in what you spend. There's nothing to connect and nothing to leak.")
            promise("iphone", "It lives on your phone",
                    "Entries reach your other devices, and anyone you invite, through iCloud. They don't come to us — there is no us.")
            promise("eye.slash.fill", "Nobody's watching",
                    "No ads, no tracking, no credit score. Anything you mark private stays yours — nobody else in the budget can see it.")
        }
        .padding(Space.md)
        .card()
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            IconTile(symbol: symbol, color: Palette.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appFont(13, weight: .medium)
                Text(detail)
                    .appFont(11.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var lookAroundButton: some View {
        Button {
            Haptics.selected()
            model.startLookingAround()
        } label: {
            RowLabel(symbol: "eye", title: Text("Have a look around first"),
                     subtitle: Text("A worked example you can poke at. Nothing kept."))
        }
        .buttonStyle(.row)
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Name your budget")
                .appFont(12, weight: .medium)
                .foregroundStyle(Palette.sub)

            TextField("", text: $name,
                      prompt: Text("e.g. Together").foregroundStyle(Palette.muted))
                .focused($focusedField, equals: .budget)
                .textFieldStyle(.plain)
                .appFont(15)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .fieldBackground()

            Text("Your name")
                .appFont(12, weight: .medium)
                .foregroundStyle(Palette.sub)
                .padding(.top, 2)

            TextField("", text: $yourName,
                      prompt: Text("e.g. Sam").foregroundStyle(Palette.muted))
                .focused($focusedField, equals: .you)
                .textFieldStyle(.plain)
                .appFont(15)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .fieldBackground()

            // Folded away, and explicitly optional. Being a required field here
            // was the single biggest thing standing between someone opening the
            // app and actually seeing it.
            if showBudgetField {
                Text("Roughly per month")
                    .appFont(12, weight: .medium)
                    .foregroundStyle(Palette.sub)
                    .padding(.top, 2)

                HStack(spacing: 2) {
                    Text(Fmt.currencySymbol).mono(14, weight: .regular)
                        .foregroundStyle(Palette.muted)
                    TextField("", text: $monthlyTotal,
                              prompt: Text("e.g. 800").foregroundStyle(Palette.muted))
                        .focused($focusedField, equals: .total)
                        .keyboardType(.decimalPad)
                        .appFont(15, weight: .medium)
                        .monospacedDigit()
                }
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .fieldBackground()

                Text(planNote)
                    .appFont(12)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    withAppAnimation(.easeInOut(duration: 0.2)) { showBudgetField = true }
                    focusedField = .total
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").appFont(10, weight: .bold)
                        Text("Set a monthly figure now (optional)")
                            .appFont(12.5, weight: .semibold)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.teal)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                Text("You don't need one to start. Log a few things first and the app "
                   + "will suggest limits from what you actually spend.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(title: "Start", symbol: "arrow.right") {
                focusedField = nil
                Haptics.saved()
                model.createHousehold(name: name, ownerName: yourName,
                                      monthlyTotal: Fmt.amount(from: monthlyTotal))
            }
            .padding(.top, Space.xxs)
        }
        .padding(Space.md)
        .card()
    }

    private var joinHint: some View {
        RowLabel(symbol: "link", color: Palette.purple, title: Text("Got an invite?"),
                 subtitle: Text("Open the link they sent you — you'll join their budget automatically.")) {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PairingView()
        .environmentObject(AppModel(store: BudgetStore(inMemory: true)))
        .background(Palette.screen.ignoresSafeArea())
        .foregroundStyle(Palette.text)
        .preferredColorScheme(.dark)
}

#Preview("Welcome — light") {
    PairingView()
        .environmentObject(AppModel(store: BudgetStore(inMemory: true)))
        .background(Palette.screen.ignoresSafeArea())
        .foregroundStyle(Palette.text)
        .preferredColorScheme(.light)
}
