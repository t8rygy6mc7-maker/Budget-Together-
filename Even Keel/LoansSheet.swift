import SwiftUI

// MARK: - What's owed
//
// Balances are typed in by hand — there's no bank connection and no credit
// bureau. The app holds the number and is honest about the payoff maths; it
// never claims to know a balance it wasn't told.

struct LoansSheet: View {
    @EnvironmentObject var model: AppModel

    @State private var editing: Loan?
    @State private var isAdding = false

    var body: some View {
        Page(title: "Owed", subtitle: Fmt.count(model.loans.count, "balance"), displayMode: .inline) {
            VStack(alignment: .leading, spacing: Space.md) {
                if model.loans.isEmpty {
                    Text("Add a student loan, a card balance or anything else you're paying down, and you'll see how long it takes at your current payment.")
                        .appFont(13)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                    totalCard
                    RowGroup(footer: "Payoff figures assume the payment and rate stay as entered. They're an estimate, not a statement from your lender.") {
                        ForEach(model.loans) { loan in
                            Button { editing = loan } label: { row(loan) }
                                .buttonStyle(.row)
                        }
                    }
                }
            }
        }
        .toolbar { AddItem(label: "Add a balance") { isAdding = true } }
        .sheet(item: $editing) { loan in LoanForm(loan: loan).environmentObject(model) }
        .sheet(isPresented: $isAdding) { LoanForm(loan: nil).environmentObject(model) }
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
        .padding(Space.md)
        .card()
    }

    private func row(_ loan: Loan) -> some View {
        RowLabel(symbol: "graduationcap.fill", color: Palette.purple,
                 title: Text(loan.name), subtitle: Text(loan.payoffLabel),
                 subtitleColor: loan.monthsToClear == nil ? Palette.overText : Palette.sub) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(loan.balance)).mono(13)
                Text("\(Fmt.money(loan.monthlyPayment))/mo")
                    .appFont(10.5).foregroundStyle(Palette.sub)
            }
        }
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
        ModalPage(title: loan == nil ? "New balance" : "Edit balance") {
            VStack(alignment: .leading, spacing: Space.md) {
                field("Name", text: $name, prompt: "e.g. Student loan")
                money("Balance owed", text: $balance)
                money("Payment a month", text: $payment)
                field("Interest rate", text: $rate, prompt: "e.g. 6.5", keyboard: .decimalPad,
                      suffix: "% a year")

                if let preview = previewLoan {
                    HStack(spacing: Space.sm) {
                        Image(systemName: preview.monthsToClear == nil
                              ? "exclamationmark.triangle.fill" : "clock.fill")
                            .appFont(13, weight: .semibold)
                            .foregroundStyle(preview.monthsToClear == nil ? Palette.over : Palette.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.payoffLabel).appFont(13, weight: .medium)
                            if let interest = preview.projectedInterest, interest > 0 {
                                Text("\(Fmt.money(interest)) of interest along the way")
                                    .appFont(11.5).foregroundStyle(Palette.sub)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Space.md)
                    .card()
                }

                if let loan {
                    SecondaryButton(title: "Delete", color: Palette.over) {
                        model.deleteLoan(loan.id)
                        dismiss()
                    }
                }
            }
            .toolbar {
                ConfirmItem(title: loan == nil ? "Add" : "Save", isEnabled: draft != nil, action: save)
            }
        }
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
            Text(title).appFont(12, weight: .medium).foregroundStyle(Palette.sub)
            HStack(spacing: 6) {
                TextField("", text: text,
                          prompt: Text(prompt).foregroundStyle(Palette.muted))
                    .textFieldStyle(.plain)
                    .keyboardType(keyboard)
                    .appFont(15)
                if let suffix {
                    Text(suffix).appFont(12).foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
            .fieldBackground()
        }
        .accessibilityElement(children: .contain)
    }

    private func money(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).appFont(12, weight: .medium).foregroundStyle(Palette.sub)
            HStack(spacing: 2) {
                Text(Fmt.currencySymbol).mono(14, weight: .regular).foregroundStyle(Palette.muted)
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .appFont(15, weight: .medium)
                    .monospacedDigit()
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
            .fieldBackground()
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
    PreviewShell { LoansSheet() }
}
