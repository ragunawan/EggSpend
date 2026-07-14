import SwiftUI
import SwiftData

/// First-run onboarding: welcome → create first account → optional extras.
/// Presented as a `fullScreenCover` from `EggSpendApp` until the user
/// finishes or skips it — every screen offers a visible "Skip" so the user
/// is never trapped.
struct OnboardingView: View {
    /// Shared UserDefaults key for the first-run flag — defined once here so
    /// the key string can't drift between this view and `EggSpendApp`,
    /// mirroring `SettingsView.aiNarrativeStorageKey`'s precedent.
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    @AppStorage(OnboardingView.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @Query private var accounts: [Account]

    @State private var step = 0
    @State private var showAddAccount = false
    @State private var showCSVImport = false
    @State private var showAddBudget = false

    private let totalSteps = 3

    var body: some View {
        ZStack {
            NestBackground()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .foregroundStyle(Color.twig)
                        .padding()
                }

                Spacer()

                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: createAccountStep
                    default: extrasStep
                    }
                }
                .padding(.horizontal, 24)
                .transition(.opacity)

                Spacer()

                pageDots
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showAddAccount) {
            AddAccountView()
        }
        .sheet(isPresented: $showCSVImport) {
            CSVImportView(importType: .transactions)
        }
        .sheet(isPresented: $showAddBudget) {
            AddBudgetView()
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "bird.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.nestBrown)
                .symbolEffect(.pulse)

            Text("Welcome to EggSpend")
                .font(.title.bold())
                .foregroundStyle(Color.nestBrown)
                .multilineTextAlignment(.center)

            Text("EggSpend helps you track transactions, budgets, subscriptions, and your nest egg all in one place — so you always know where your money stands and what's coming next.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                withAnimation { step = 1 }
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Color.nestBrown)
            .controlSize(.large)
            .padding(.top, 12)
        }
        .padding(24)
        .nestCard()
    }

    // MARK: - Step 2: Create first account

    private var createAccountStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "building.columns")
                .font(.largeTitle)
                .foregroundStyle(Color.eggBlue)
                .symbolEffect(.pulse)

            Text("Add Your First Account")
                .font(.title2.bold())
                .foregroundStyle(Color.nestBrown)
                .multilineTextAlignment(.center)

            Text("Accounts are how EggSpend tracks balances and net worth — add a checking, savings, or credit card account to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !accounts.isEmpty {
                Label("Account added", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.nestLeafGreen)
                    .font(.subheadline.weight(.semibold))
            }

            Button {
                showAddAccount = true
            } label: {
                Label("Add Account", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Color.nestBrown)
            .controlSize(.large)

            Button {
                withAnimation { step = 2 }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(Color.twig)
        }
        .padding(24)
        .nestCard()
    }

    // MARK: - Step 3: Optional extras

    private var extrasStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Color.yolk)
                .symbolEffect(.pulse)

            Text("A Couple More Things")
                .font(.title2.bold())
                .foregroundStyle(Color.nestBrown)
                .multilineTextAlignment(.center)

            Text("These are optional — you can always do them later from the app.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showCSVImport = true
            } label: {
                Label("Import CSV", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(Color.nestBrown)
            .controlSize(.large)

            Button {
                showAddBudget = true
            } label: {
                Label("Create a Budget", systemImage: "dollarsign.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(Color.nestBrown)
            .controlSize(.large)

            Button {
                finish()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Color.nestBrown)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(24)
        .nestCard()
    }

    // MARK: - Page indicator

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.nestBrown : Color.twig.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func finish() {
        hasCompletedOnboarding = true
    }
}

#Preview {
    OnboardingView()
        .modelContainer(PersistenceController.previewContainer())
}
