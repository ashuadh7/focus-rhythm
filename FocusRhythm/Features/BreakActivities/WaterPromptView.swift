import SwiftUI

struct WaterPromptView: View {
    @Bindable var viewModel: WaterLoggingViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("Drink water - log how much")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                ForEach(WaterLoggingViewModel.quickAmountsMl, id: \.self) { amount in
                    Button {
                        viewModel.logQuickAmount(amount)
                    } label: {
                        Text("\(amount) ml")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            HStack(spacing: 8) {
                TextField("Custom ml", text: $viewModel.customAmountText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                Button("Log") {
                    viewModel.logCustomAmount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(Int(viewModel.customAmountText) == nil)
            }

            if viewModel.totalLoggedTodayMl > 0 {
                Text("Logged today: \(viewModel.totalLoggedTodayMl) ml")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    WaterPromptView(viewModel: WaterLoggingViewModel())
}
