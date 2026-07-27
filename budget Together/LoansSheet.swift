import SwiftUI

// MARK: - What's owed
//
// Balances are typed in by hand — there's no bank connection and no credit
// bureau. The app holds the number and is honest about the payoff maths; it
// never claims to know a balance it wasn't told.

struct LoansSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Loan?
    @State private var isAdding = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if model.loans.isEmpty {
                    Text("Add a student loan, a card balance or anything else you're paying down, and you'll see how long it takes at your current payment.")
                        .appFont(13)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 22)
                } else {
                    totalCard.padding(.bottom, 12)
                    VStack(spacing: 8) {
                        ForEach(model.loans) { loan in
                            Button { editing = loan } label: { row(loan) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                Button { isAdding = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").appFont(15, weight: .bold)
                        Text("Add a balance").appFont(15, weight: .bold)
                    }
                    .frame(maxWidth: .infinity).padding(15)
                    .foregroundStyle(Palette.tealInk)
                    .background(Palette.tealGradient,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .padding(.top, 16)

                Text("Payoff figures assume the payment and rate stay as entered. They're an estimate, not a statement from your lender.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .sheet(item: $editing) { loan in LoanForm(loan: loan).environmentObject(model) }
        .sheet(isPresented: $isAdding) { LoanForm(loan: nil).environmentObject(model) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Owed").appFont(17, weight: .bold)
                Text("^[\(model.loans.count) balance](inflect: true)")
                    .appFont(12.5, weight: .medium)
                    .foregroundStyle(Palette.sub)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .background(Palette.chip, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, 6).padding(.bottom, 16)
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total owed").appFont(12.5, weight: .medium)
                .foregroundStyle(Palette.sub)
            Text(Fmt.money(model.totalOwed)).mono(30)
            Text("\(Fmt.money(model.monthlyLoanPayments)) a month across ^[\(model.loans.count) balance](inflect: true)")
                .appFont(12).foregroundStyle(Palette.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17).padding(.vertical, 16)
        .card()
    }

    private func row(_ loan: Loan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .appFont(15, weight: .semibold)
                .foregroundStyle(Palette.purple)
                .frame(width: 34, height: 34)
                .background(Palette.purple.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(loan.name).appFont(14, weight: .semibold).lineLimit(1)
                Text(loan.payoffLabel)
                    .appFont(11.5)
                    .foregroundStyle(loan.monthsToClear == nil ? Palette.overText : Palette.sub)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(loan.balance)).mono(13)
                Text("\(Fmt.money(loan.monthlyPayment))/mo")
                    .appFont(10.5).foregroundStyle(Palette.sub)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .card(border: Palette.cardBorderSoft, radius: 15)
    }
}

// MARK: - Form

struct LoanForm: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let loan: Loan?

    @State private var name = ""
    @State private var balance = ""
    @State private var rate = ""
    @State private var payment = ""

    private var draft: (name: String, balance: Double, payment: Double)? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let balance = Fmt.amount(from: balance) else { return nil }
        return (name, balance, Fmt.amount(from: payment) ?? 0)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(loan == nil ? "New balance" : "Edit balance")
                        .appFont(17, weight: .bold)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .appFont(14, weight: .semibold)
                            .foregroundStyle(Palette.label9)
                            .frame(width: 30, height: 30)
                            .background(Palette.chip, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.top, 6)

                field("Name", text: $name, prompt: "e.g. Student loan")
                money("Balance owed", text: $balance)
                money("Payment a month", text: $payment)
                field("Interest rate", text: $rate, prompt: "e.g. 6.5", keyboard: .decimalPad,
                      suffix: "% a year")

                if let preview = previewLoan {
                    HStack(spacing: 10) {
                        Image(systemName: preview.monthsToClear == nil
                              ? "exclamationmark.triangle.fill" : "clock.fill")
                            .appFont(13, weight: .semibold)
                            .foregroundStyle(preview.monthsToClear == nil ? Palette.over : Palette.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.payoffLabel).appFont(13, weight: .semibold)
                            if let interest = preview.projectedInterest, interest > 0 {
                                Text("\(Fmt.money(interest)) of interest along the way")
                                    .appFont(11.5).foregroundStyle(Palette.sub)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .card(border: Palette.cardBorderSoft, radius: 13)
                }

                let canSave = draft != nil
                Button(action: save) {
                    Text(loan == nil ? "Add" : "Save changes")
                        .appFont(15, weight: .bold)
                        .frame(maxWidth: .infinity).padding(15)
                        .foregroundStyle(canSave ? Palette.tealInk : Palette.muted)
                        .background {
                            if canSave { Palette.tealGradient } else { Palette.chip }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .disabled(!canSave)

                if let loan {
                    Button {
                        model.deleteLoan(loan.id)
                        dismiss()
                    } label: {
                        Text("Delete")
                            .appFont(14, weight: .semibold)
                            .foregroundStyle(Palette.over)
                            .frame(maxWidth: .infinity).padding(13)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .onAppear(perform: load)
    }

    /// Live payoff maths as the numbers are typed, so the consequence of a
    /// payment is visible before it's committed.
    private var previewLoan: Loan? {
        guard let draft, draft.payment > 0 else { return nil }
        return Loan(id: "preview", name: draft.name, balance: draft.balance,
                    rate: Fmt.amount(from: rate) ?? 0, monthlyPayment: draft.payment,
                    createdAt: Date())
    }

    private func field(_ title: String, text: Binding<String>, prompt: String,
                       keyboard: UIKeyboardType = .default,
                       suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).appFont(12, weight: .semibold).foregroundStyle(Palette.sub)
            HStack(spacing: 6) {
                TextField("", text: text,
                          prompt: Text(prompt).foregroundStyle(Palette.muted))
                    .textFieldStyle(.plain)
                    .keyboardType(keyboard)
                    .appFont(15, weight: .medium)
                if let suffix {
                    Text(suffix).appFont(12).foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .fieldBackground(radius: 13)
        }
        .accessibilityElement(children: .contain)
    }

    private func money(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).appFont(12, weight: .semibold).foregroundStyle(Palette.sub)
            HStack(spacing: 2) {
                Text(Fmt.currencySymbol).mono(14, weight: .regular).foregroundStyle(Palette.muted)
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .appFont(15, weight: .bold, design: .monospaced)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .fieldBackground(radius: 13)
        }
        .accessibilityElement(children: .contain)
    }

    private func load() {
        guard let loan else { return }
        name = loan.name
        balance = Fmt.plain(loan.balance)
        rate = loan.rate > 0 ? Fmt.plain(loan.rate) : ""
        payment = Fmt.plain(loan.monthlyPayment)
    }

    private func save() {
        guard let draft else { return }
        model.saveLoan(Loan(
            id: loan?.id ?? UUID().uuidString,
            name: draft.name,
            balance: draft.balance,
            rate: Fmt.amount(from: rate) ?? 0,
            monthlyPayment: draft.payment,
            createdAt: loan?.createdAt ?? Date()
        ))
        dismiss()
    }
}

#Preview {
    LoansSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
