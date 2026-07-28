import SwiftUI

// MARK: - Your data
//
// The screen that makes the privacy promise real rather than rhetorical. An app
// that keeps everything on your device has to also let you take it away and
// destroy it — otherwise "we never see your data" just means "you can't leave".
//
// Both halves live here, together and on purpose: seeing "export" immediately
// above "delete everything" is the nudge that stops someone wiping a year of
// entries they hadn't backed up.

struct DataSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var file: AppModel.ExportFile?
    @State private var confirming = false
    @State private var typed = ""
    @FocusState private var confirmFocused: Bool

    /// Typed rather than tapped. A destructive-role button in a dialog is one
    /// stray tap away; a word you have to spell is not.
    private static let phrase = "DELETE"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                promise
                exportSection
                deleteSection
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .sheet(item: $file) { ShareSheet(url: $0.url) }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your data").appFont(17, weight: .bold)
                Text("All of it is on this phone. Here's how to take it with you, "
                   + "or get rid of it.")
                    .appFont(12.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .background(Palette.chip, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, 6).padding(.bottom, 18)
    }

    private var promise: some View {
        let footprint = model.dataFootprint
        return HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .appFont(15, weight: .semibold)
                .foregroundStyle(Palette.teal)
                .frame(width: 34, height: 34)
                .background(Palette.teal.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.count(footprint.entries, "entry", plural: "entries")) across "
                   + "\(Fmt.count(footprint.months, "month"))")
                    .appFont(13.5, weight: .semibold)
                Text("No account, no server, no analytics. Nothing here has ever "
                   + "been sent anywhere.")
                    .appFont(11.5).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .card(border: Palette.cardBorderSoft, radius: 15)
        .padding(.bottom, 22)
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TAKE IT WITH YOU")
                .appFont(10, weight: .bold).tracking(0.8)
                .foregroundStyle(Palette.label9)

            exportRow(
                title: "Spreadsheet (CSV)",
                detail: "One row per transaction. Opens in Numbers, Excel, anything.",
                symbol: "tablecells",
                action: { file = model.exportCSV() }
            )

            exportRow(
                title: "Everything (JSON)",
                detail: "A complete backup — categories, limits, people, templates, "
                      + "the lot. Keep it somewhere safe.",
                symbol: "curlybraces",
                action: { file = model.exportJSON() }
            )

            Text("Both are written to a temporary file and handed to the share "
               + "sheet. Where they go from there is entirely your call.")
                .appFont(11)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 26)
    }

    private func exportRow(title: String, detail: String, symbol: String,
                           action: @escaping () -> Void) -> some View {
        Button {
            Haptics.saved()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(Palette.teal)
                    .frame(width: 34, height: 34)
                    .background(Palette.teal.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).appFont(14, weight: .semibold)
                    Text(detail)
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "square.and.arrow.up")
                    .appFont(13, weight: .semibold)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)
        }
        .buttonStyle(.plain)
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DELETE EVERYTHING")
                .appFont(10, weight: .bold).tracking(0.8)
                .foregroundStyle(Palette.label9)

            if confirming {
                confirmation
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { confirming = true }
                    confirmFocused = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .appFont(15, weight: .semibold)
                            .foregroundStyle(Palette.over)
                            .frame(width: 34, height: 34)
                            .background(Palette.over.opacity(0.16),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete everything").appFont(14, weight: .semibold)
                            Text("Every entry, person, category and limit. "
                               + "There is no undo and no copy anywhere else.")
                                .appFont(11.5).foregroundStyle(Palette.sub)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .card(border: Palette.cardBorderSoft, radius: 15)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var confirmation: some View {
        let footprint = model.dataFootprint
        let matches = typed.trimmingCharacters(in: .whitespaces).uppercased() == Self.phrase
        return VStack(alignment: .leading, spacing: 12) {
            Text("This deletes \(Fmt.count(footprint.entries, "entry", plural: "entries")) "
               + "and \(Fmt.count(footprint.people, "person", plural: "people")) from this "
               + "phone. It cannot be undone, and there is no copy on a server to "
               + "restore from — that's the whole point of the app.")
                .appFont(12.5)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            if footprint.entries > 0 {
                Text("Export first if you might want any of it later.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.moodJoy)
            }

            Text("Type \(Self.phrase) to confirm")
                .appFont(11.5, weight: .semibold)
                .foregroundStyle(Palette.sub)

            TextField("", text: $typed,
                      prompt: Text(Self.phrase).foregroundStyle(Palette.muted))
                .focused($confirmFocused)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .appFont(15, weight: .semibold, design: .monospaced)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .fieldBackground(radius: 13)
                .accessibilityLabel("Type \(Self.phrase) to confirm deletion")

            Button {
                Haptics.warned()
                model.eraseEverything()
                dismiss()
            } label: {
                Text("Delete everything")
                    .appFont(15, weight: .bold)
                    .frame(maxWidth: .infinity).padding(15)
                    .foregroundStyle(matches ? .white : Palette.muted)
                    .background(matches ? AnyShapeStyle(Palette.over)
                                        : AnyShapeStyle(Palette.chip))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .disabled(!matches)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    confirming = false
                    typed = ""
                }
            } label: {
                Text("Keep my data")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(Palette.chipText)
                    .frame(maxWidth: .infinity).padding(13)
                    .fieldBackground(radius: 14)
            }
        }
        .padding(14)
        .card(border: Palette.over.opacity(0.4), radius: 16)
    }
}

// MARK: - Share sheet

/// Thin wrapper over `UIActivityViewController`. `ShareLink` would do for a
/// single known file, but the URL here is produced on tap rather than known up
/// front, so the sheet is presented imperatively instead.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    DataSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
