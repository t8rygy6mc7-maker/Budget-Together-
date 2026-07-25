import SwiftUI

// MARK: - Pairing / onboarding
//
// Shown when this device hasn't joined a household yet. The owner creates a
// household here; the partner joins by opening the invite link their partner
// sends (handled outside the app by CloudKit — see AppDelegate, Step 3), so
// there's no code to type in.

struct PairingView: View {
    @EnvironmentObject var model: AppModel
    @State private var name = "Together"
    @State private var yourName = ""
    @FocusState private var focusedField: Field?

    private enum Field { case budget, you }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 40)

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Palette.tealInk)
                    .frame(width: 74, height: 74)
                    .background(Palette.tealGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Palette.teal.opacity(0.5), radius: 16, x: 0, y: 12)
                    .padding(.bottom, 22)

                Text("Share a budget,\ntogether")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.text)
                    .padding(.bottom, 8)
                Text("One budget, however many of you there are. Add everyone who spends from it — entries and caps stay in sync on every phone through iCloud.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 26)

                // Create household
                VStack(alignment: .leading, spacing: 12) {
                    Text("Name your budget")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.sub)

                    TextField("", text: $name,
                              prompt: Text("e.g. Together").foregroundStyle(Palette.muted))
                        .focused($focusedField, equals: .budget)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .fieldBackground(radius: 13)

                    Text("Your name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.sub)
                        .padding(.top, 2)

                    TextField("", text: $yourName,
                              prompt: Text("e.g. Sam").foregroundStyle(Palette.muted))
                        .focused($focusedField, equals: .you)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .fieldBackground(radius: 13)

                    Text("You can add everyone else once you're in.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)

                    Button {
                        focusedField = nil
                        model.createHousehold(name: name, ownerName: yourName)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Create household")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity).padding(15)
                        .foregroundStyle(Palette.tealInk)
                        .background(Palette.tealGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                }
                .padding(16)
                .card()
                .padding(.bottom, 18)

                // Join hint
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.purple)
                        .frame(width: 34, height: 34)
                        .background(Palette.purple.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Got an invite?")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Open the link they sent you — you'll join their budget automatically.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .card(border: Palette.cardBorderSoft, radius: 15)

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    PairingView()
        .environmentObject(AppModel(store: BudgetStore(inMemory: true)))
        .background(Palette.screen.ignoresSafeArea())
        .foregroundStyle(Palette.text)
        .preferredColorScheme(.dark)
}
