#!/usr/bin/env python3
"""Generates EggSpend.xcodeproj/project.pbxproj"""

import os

# ── UUID scheme: AA + type_hex + 18 zeros + 2-digit sequence ──────────────
# type 0=project, 1=file refs, 2=build files, 3=groups
# type 4=targets, 5=config lists, 6=build configs, 7=build phases, 9=deps

def u(type_hex, seq):
    return f"AA0{type_hex}000000000000000000{seq:02X}"

# ── UUIDs ──────────────────────────────────────────────────────────────────
PROJECT    = u(0, 0x01)

# File references
FR = {
    "EggSpendApp":        u(1, 0x01),
    "ContentView":         u(1, 0x02),
    "Transaction":         u(1, 0x03),
    "TransactionCategory": u(1, 0x04),
    "Account":             u(1, 0x05),
    "DashboardView":       u(1, 0x06),
    "TransactionsListView":u(1, 0x07),
    "AddTransactionView":  u(1, 0x08),
    "TransactionDetailView":u(1, 0x09),
    "NetWorthView":        u(1, 0x0A),
    "MetricsView":         u(1, 0x0B),
    "AccountsView":        u(1, 0x0C),
    "AddAccountView":      u(1, 0x0D),
    "CategoryBadgeView":   u(1, 0x0E),
    "AmountLabel":         u(1, 0x0F),
    "TransactionRowView":  u(1, 0x10),
    "PersistenceController":u(1, 0x11),
    "Assets":              u(1, 0x12),
    # New v2 files
    "EggSpendTheme":      u(1, 0x13),
    "Budget":              u(1, 0x14),
    "RecurringTransaction":u(1, 0x15),
    "NestHeaderView":      u(1, 0x16),
    "EggProgressView":     u(1, 0x17),
    "BirdAnimationView":   u(1, 0x18),
    "BudgetView":          u(1, 0x19),
    "AddBudgetView":       u(1, 0x1A),
    "BudgetDetailView":    u(1, 0x40),
    "RecurringTransactionsView": u(1, 0x1B),
    "AddRecurringTransactionView": u(1, 0x1C),
    "Entitlements":        u(1, 0x1D),
    "CSVParser":           u(1, 0x1E),
    "CSVImportView":       u(1, 0x1F),
    "CategoryManagementView": u(1, 0x36),
    "AddEditCategoryView":    u(1, 0x37),
    "ForecastEngine":         u(1, 0x41),
    "CashFlowForecastView":   u(1, 0x42),
    "PROD_APP":            u(1, 0x20),  # EggSpend.app
    "PROD_TEST":           u(1, 0x21),  # EggSpendTests.xctest
    "TEST_Transaction":    u(1, 0x30),
    "TEST_Metrics":        u(1, 0x31),
    "TEST_NetWorth":       u(1, 0x32),
    "TEST_Category":       u(1, 0x33),
    "TEST_Budget":         u(1, 0x34),
    "TEST_Recurring":      u(1, 0x35),
    "TEST_CategoryMgmt":   u(1, 0x38),
    "TEST_CashFlowForecast": u(1, 0x43),
    "AccountBalanceService": u(1, 0x44),
    "TEST_TransactionAccount": u(1, 0x45),
    "MonthlyReviewCalculator": u(1, 0x46),
    "MonthlyReviewView":       u(1, 0x47),
    "TEST_MonthlyReview":      u(1, 0x48),
    "TransactionFilter":       u(1, 0x49),
    "TransactionFilterView":   u(1, 0x4A),
    "TEST_TransactionFilter":  u(1, 0x4B),
    "SavingsGoal":             u(1, 0x4C),
    "SavingsGoalsView":        u(1, 0x4D),
    "AddSavingsGoalView":      u(1, 0x4E),
    "TEST_SavingsGoal":        u(1, 0x4F),
    "TEST_CSVParser":          u(1, 0x50),
    "PrivacyInfo":             u(1, 0x51),
    "SyncStatus":              u(1, 0x52),
    "TEST_CloudKitSchema":     u(1, 0x53),
    "SafeSpendCalculator":     u(1, 0x54),
    "SafeToSpendView":         u(1, 0x55),
    "TEST_SafeSpend":          u(1, 0x56),
    "NotificationScheduler":       u(1, 0x57),
    "BudgetAlertCoordinator":      u(1, 0x58),
    "TEST_NotificationScheduler":  u(1, 0x59),
    "FloatingLeavesView":          u(1, 0x5A),
    "AnimatedCanopyBackground":    u(1, 0x5B),
    "Transfer":                u(1, 0x5C),
    "TransferBalanceService":  u(1, 0x5D),
    "TransferRowView":         u(1, 0x5E),
    "TransferDetailView":      u(1, 0x5F),
    "TEST_Transfer":           u(1, 0x60),
    "RecurringProjection":     u(1, 0x61),
    "RecurringNext30DaysView": u(1, 0x62),
    "DebtPayoffCalculator":    u(1, 0x63),
    "DebtPayoffPlannerView":   u(1, 0x64),
    "CashFlowCalendarView":    u(1, 0x65),
    "TEST_DebtPayoff":         u(1, 0x66),
    "NetWorthCalculator":      u(1, 0x67),
    "AmountParser":            u(1, 0x68),
    "TEST_AmountParser":       u(1, 0x69),
    "CurrencyFormat":          u(1, 0x6A),
    "TEST_CurrencyFormat":     u(1, 0x6B),
    "DataExporter":            u(1, 0x6C),
    "TEST_DataExporter":       u(1, 0x6D),
    "SettingsView":            u(1, 0x6E),
    "BalanceSnapshot":         u(1, 0x6F),
    "BalanceSnapshotService":  u(1, 0x70),
    "TEST_BalanceSnapshot":    u(1, 0x71),
    "SubscriptionDetector":    u(1, 0x72),
    "TEST_SubscriptionDetector": u(1, 0x73),
    "SubscriptionAuditView":   u(1, 0x74),
    "CategoryRule":            u(1, 0x75),
    "CategoryRuleEngine":      u(1, 0x76),
    "TEST_CategoryRule":       u(1, 0x77),
}

# Build files
BF = {k: u(2, i+1) for i, k in enumerate(FR.keys()) if not k.startswith("PROD_")}

# Groups
GR = {
    "Root":       u(3, 0x01),
    "Products":   u(3, 0x02),
    "EggSpend":  u(3, 0x03),
    "Models":     u(3, 0x04),
    "Views":      u(3, 0x05),
    "Dashboard":  u(3, 0x06),
    "Transactions":u(3, 0x07),
    "NetWorth":   u(3, 0x08),
    "Metrics":    u(3, 0x09),
    "Accounts":   u(3, 0x0A),
    "Components": u(3, 0x0B),
    "Persistence":u(3, 0x0C),
    "Tests":      u(3, 0x0D),
    "Budget":      u(3, 0x0E),
    "Recurring":   u(3, 0x0F),
    "Utilities":   u(3, 0x10),
    "ImportViews": u(3, 0x11),
    "Categories": u(3, 0x12),
    "Forecast":   u(3, 0x13),
    "MonthlyReview": u(3, 0x14),
    "SavingsGoals": u(3, 0x15),
    "SafeSpend":  u(3, 0x16),
    "Settings":   u(3, 0x17),
    "Subscriptions": u(3, 0x18),
}

# Targets
TG_APP  = u(4, 0x01)
TG_TEST = u(4, 0x02)

# Config lists
CL_PROJECT = u(5, 0x01)
CL_APP     = u(5, 0x02)
CL_TEST    = u(5, 0x03)

# Build configurations
BC_PROJ_DBG = u(6, 0x01)
BC_PROJ_REL = u(6, 0x02)
BC_APP_DBG  = u(6, 0x03)
BC_APP_REL  = u(6, 0x04)
BC_TEST_DBG = u(6, 0x05)
BC_TEST_REL = u(6, 0x06)

# Build phases
BP_APP_SRC  = u(7, 0x01)
BP_APP_RES  = u(7, 0x02)
BP_APP_FRM  = u(7, 0x03)
BP_TEST_SRC = u(7, 0x04)
BP_TEST_FRM = u(7, 0x05)

# Dependencies / proxy
TD_TEST = u(9, 0x01)
CI_TEST = u(9, 0x02)

# ── App source files (path relative to EggSpend/ folder) ─────────────────────────
APP_SOURCES = [
    ("EggSpendApp",         "EggSpendApp.swift"),
    ("ContentView",          "ContentView.swift"),
    ("EggSpendTheme",       "EggSpendTheme.swift"),
    ("Transaction",          "Models/Transaction.swift"),
    ("TransactionCategory",  "Models/TransactionCategory.swift"),
    ("Account",              "Models/Account.swift"),
    ("Budget",               "Models/Budget.swift"),
    ("RecurringTransaction", "Models/RecurringTransaction.swift"),
    ("SavingsGoal",          "Models/SavingsGoal.swift"),
    ("Transfer",             "Models/Transfer.swift"),
    ("BalanceSnapshot",      "Models/BalanceSnapshot.swift"),
    ("CategoryRule",         "Models/CategoryRule.swift"),
    ("RecurringProjection",  "Utilities/RecurringProjection.swift"),
    ("DashboardView",        "Views/Dashboard/DashboardView.swift"),
    ("TransactionsListView", "Views/Transactions/TransactionsListView.swift"),
    ("AddTransactionView",   "Views/Transactions/AddTransactionView.swift"),
    ("TransactionDetailView","Views/Transactions/TransactionDetailView.swift"),
    ("TransferDetailView",   "Views/Transactions/TransferDetailView.swift"),
    ("NetWorthView",         "Views/NetWorth/NetWorthView.swift"),
    ("MetricsView",          "Views/Metrics/MetricsView.swift"),
    ("AccountsView",         "Views/Accounts/AccountsView.swift"),
    ("AddAccountView",       "Views/Accounts/AddAccountView.swift"),
    ("DebtPayoffPlannerView", "Views/Accounts/DebtPayoffPlannerView.swift"),
    ("BudgetView",           "Views/Budget/BudgetView.swift"),
    ("AddBudgetView",        "Views/Budget/AddBudgetView.swift"),
    ("BudgetDetailView",     "Views/Budget/BudgetDetailView.swift"),
    ("RecurringTransactionsView", "Views/Recurring/RecurringTransactionsView.swift"),
    ("RecurringNext30DaysView", "Views/Recurring/RecurringNext30DaysView.swift"),
    ("AddRecurringTransactionView","Views/Recurring/AddRecurringTransactionView.swift"),
    ("NestHeaderView",       "Views/Components/NestHeaderView.swift"),
    ("EggProgressView",      "Views/Components/EggProgressView.swift"),
    ("BirdAnimationView",    "Views/Components/BirdAnimationView.swift"),
    ("FloatingLeavesView",   "Views/Components/FloatingLeavesView.swift"),
    ("AnimatedCanopyBackground", "Views/Components/AnimatedCanopyBackground.swift"),
    ("CategoryBadgeView",    "Views/Components/CategoryBadgeView.swift"),
    ("AmountLabel",          "Views/Components/AmountLabel.swift"),
    ("TransactionRowView",   "Views/Components/TransactionRowView.swift"),
    ("TransferRowView",      "Views/Components/TransferRowView.swift"),
    ("PersistenceController","Persistence/PersistenceController.swift"),
    ("SyncStatus",            "Persistence/SyncStatus.swift"),
    ("CSVParser",            "Utilities/CSVParser.swift"),
    ("AccountBalanceService","Utilities/AccountBalanceService.swift"),
    ("TransferBalanceService","Utilities/TransferBalanceService.swift"),
    ("CSVImportView",        "Views/Import/CSVImportView.swift"),
    ("CategoryManagementView", "Views/Categories/CategoryManagementView.swift"),
    ("AddEditCategoryView",    "Views/Categories/AddEditCategoryView.swift"),
    ("ForecastEngine",        "Views/Forecast/ForecastEngine.swift"),
    ("CashFlowForecastView",  "Views/Forecast/CashFlowForecastView.swift"),
    ("CashFlowCalendarView",  "Views/Forecast/CashFlowCalendarView.swift"),
    ("MonthlyReviewCalculator", "Utilities/MonthlyReviewCalculator.swift"),
    ("NetWorthCalculator",      "Utilities/NetWorthCalculator.swift"),
    ("MonthlyReviewView",       "Views/MonthlyReview/MonthlyReviewView.swift"),
    ("TransactionFilter",       "Utilities/TransactionFilter.swift"),
    ("TransactionFilterView",   "Views/Transactions/TransactionFilterView.swift"),
    ("SavingsGoalsView",        "Views/SavingsGoals/SavingsGoalsView.swift"),
    ("AddSavingsGoalView",      "Views/SavingsGoals/AddSavingsGoalView.swift"),
    ("SafeSpendCalculator",     "Utilities/SafeSpendCalculator.swift"),
    ("DebtPayoffCalculator",    "Utilities/DebtPayoffCalculator.swift"),
    ("SafeToSpendView",         "Views/SafeSpend/SafeToSpendView.swift"),
    ("NotificationScheduler",   "Utilities/NotificationScheduler.swift"),
    ("BudgetAlertCoordinator",  "Utilities/BudgetAlertCoordinator.swift"),
    ("AmountParser",            "Utilities/AmountParser.swift"),
    ("CurrencyFormat",          "Utilities/CurrencyFormat.swift"),
    ("DataExporter",            "Utilities/DataExporter.swift"),
    ("SettingsView",            "Views/Settings/SettingsView.swift"),
    ("BalanceSnapshotService",  "Utilities/BalanceSnapshotService.swift"),
    ("SubscriptionDetector",    "Utilities/SubscriptionDetector.swift"),
    ("CategoryRuleEngine",      "Utilities/CategoryRuleEngine.swift"),
    ("SubscriptionAuditView",   "Views/Subscriptions/SubscriptionAuditView.swift"),
]

TEST_SOURCES = [
    ("TEST_Transaction", "EggSpendTests/TransactionModelTests.swift"),
    ("TEST_Metrics",     "EggSpendTests/MetricsCalculationTests.swift"),
    ("TEST_NetWorth",    "EggSpendTests/NetWorthCalculationTests.swift"),
    ("TEST_Category",    "EggSpendTests/CategoryTests.swift"),
    ("TEST_Budget",       "EggSpendTests/BudgetTests.swift"),
    ("TEST_Recurring",    "EggSpendTests/RecurringTransactionTests.swift"),
    ("TEST_CategoryMgmt",      "EggSpendTests/CategoryManagementTests.swift"),
    ("TEST_CashFlowForecast",  "EggSpendTests/CashFlowForecastTests.swift"),
    ("TEST_TransactionAccount", "EggSpendTests/TransactionAccountTests.swift"),
    ("TEST_MonthlyReview",      "EggSpendTests/MonthlyReviewCalculatorTests.swift"),
    ("TEST_TransactionFilter",  "EggSpendTests/TransactionFilterTests.swift"),
    ("TEST_SavingsGoal",        "EggSpendTests/SavingsGoalTests.swift"),
    ("TEST_CSVParser",          "EggSpendTests/CSVParserTests.swift"),
    ("TEST_CloudKitSchema",     "EggSpendTests/CloudKitSchemaTests.swift"),
    ("TEST_SafeSpend",          "EggSpendTests/SafeSpendCalculatorTests.swift"),
    ("TEST_NotificationScheduler", "EggSpendTests/NotificationSchedulerTests.swift"),
    ("TEST_Transfer",           "EggSpendTests/TransferTests.swift"),
    ("TEST_DebtPayoff",         "EggSpendTests/DebtPayoffCalculatorTests.swift"),
    ("TEST_AmountParser",       "EggSpendTests/AmountParserTests.swift"),
    ("TEST_CurrencyFormat",     "EggSpendTests/CurrencyFormatTests.swift"),
    ("TEST_DataExporter",       "EggSpendTests/DataExporterTests.swift"),
    ("TEST_BalanceSnapshot",    "EggSpendTests/BalanceSnapshotTests.swift"),
    ("TEST_SubscriptionDetector", "EggSpendTests/SubscriptionDetectorTests.swift"),
    ("TEST_CategoryRule",       "EggSpendTests/CategoryRuleEngineTests.swift"),
]

def pbxproj():
    lines = []
    a = lines.append

    a("// !$*UTF8*$!")
    a("{")
    a("\tarchiveVersion = 1;")
    a("\tclasses = {")
    a("\t};")
    a("\tobjectVersion = 77;")
    a("\tobjects = {")
    a("")

    # ── PBXBuildFile ────────────────────────────────────────────────────────
    a("\t\t/* Begin PBXBuildFile section */")
    for key, path in APP_SOURCES:
        filename = path.split("/")[-1]
        a(f"\t\t{BF[key]} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {FR[key]} /* {filename} */; }};")
    a(f"\t\t{BF['Assets']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {FR['Assets']} /* Assets.xcassets */; }};")
    a(f"\t\t{BF['PrivacyInfo']} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {FR['PrivacyInfo']} /* PrivacyInfo.xcprivacy */; }};")
    for key, path in TEST_SOURCES:
        filename = path.split("/")[-1]
        a(f"\t\t{BF[key]} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {FR[key]} /* {filename} */; }};")
    a("\t\t/* End PBXBuildFile section */")
    a("")

    # ── PBXContainerItemProxy ───────────────────────────────────────────────
    a("\t\t/* Begin PBXContainerItemProxy section */")
    a(f"\t\t{CI_TEST} /* PBXContainerItemProxy */ = {{")
    a(f"\t\t\tisa = PBXContainerItemProxy;")
    a(f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;")
    a(f"\t\t\tproxyType = 1;")
    a(f"\t\t\tremoteGlobalIDString = {TG_APP};")
    a(f"\t\t\tremoteInfo = EggSpend;")
    a(f"\t\t}};")
    a("\t\t/* End PBXContainerItemProxy section */")
    a("")

    # ── PBXFileReference ────────────────────────────────────────────────────
    a("\t\t/* Begin PBXFileReference section */")
    a(f"\t\t{FR['PROD_APP']} /* EggSpend.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = EggSpend.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    a(f"\t\t{FR['PROD_TEST']} /* EggSpendTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = EggSpendTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for key, path in APP_SOURCES:
        filename = path.split("/")[-1]
        a(f"\t\t{FR[key]} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};")
    a(f"\t\t{FR['Assets']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
    a(f"\t\t{FR['Entitlements']} /* EggSpend.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = EggSpend.entitlements; sourceTree = \"<group>\"; }};")
    a(f"\t\t{FR['PrivacyInfo']} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = \"<group>\"; }};")
    for key, path in TEST_SOURCES:
        filename = path.split("/")[-1]
        a(f"\t\t{FR[key]} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};")
    a("\t\t/* End PBXFileReference section */")
    a("")

    # ── PBXFrameworksBuildPhase ─────────────────────────────────────────────
    a("\t\t/* Begin PBXFrameworksBuildPhase section */")
    a(f"\t\t{BP_APP_FRM} /* Frameworks */ = {{")
    a(f"\t\t\tisa = PBXFrameworksBuildPhase;")
    a(f"\t\t\tbuildActionMask = 2147483647;")
    a(f"\t\t\tfiles = (")
    a(f"\t\t\t);")
    a(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a(f"\t\t}};")
    a(f"\t\t{BP_TEST_FRM} /* Frameworks */ = {{")
    a(f"\t\t\tisa = PBXFrameworksBuildPhase;")
    a(f"\t\t\tbuildActionMask = 2147483647;")
    a(f"\t\t\tfiles = (")
    a(f"\t\t\t);")
    a(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a(f"\t\t}};")
    a("\t\t/* End PBXFrameworksBuildPhase section */")
    a("")

    # ── PBXGroup ─────────────────────────────────────────────────────────────
    a("\t\t/* Begin PBXGroup section */")

    # Root group
    a(f"\t\t{GR['Root']} = {{")
    a(f"\t\t\tisa = PBXGroup;")
    a(f"\t\t\tchildren = (")
    a(f"\t\t\t\t{GR['EggSpend']} /* EggSpend */,")
    a(f"\t\t\t\t{GR['Tests']} /* EggSpendTests */,")
    a(f"\t\t\t\t{GR['Products']} /* Products */,")
    a(f"\t\t\t);")
    a(f"\t\t\tsourceTree = \"<group>\";")
    a(f"\t\t}};")

    # Products group
    a(f"\t\t{GR['Products']} /* Products */ = {{")
    a(f"\t\t\tisa = PBXGroup;")
    a(f"\t\t\tchildren = (")
    a(f"\t\t\t\t{FR['PROD_APP']} /* EggSpend.app */,")
    a(f"\t\t\t\t{FR['PROD_TEST']} /* EggSpendTests.xctest */,")
    a(f"\t\t\t);")
    a(f"\t\t\tname = Products;")
    a(f"\t\t\tsourceTree = \"<group>\";")
    a(f"\t\t}};")

    # EggSpend group (main app folder)
    a(f"\t\t{GR['EggSpend']} /* EggSpend */ = {{")
    a(f"\t\t\tisa = PBXGroup;")
    a(f"\t\t\tchildren = (")
    a(f"\t\t\t\t{FR['EggSpendApp']} /* EggSpendApp.swift */,")
    a(f"\t\t\t\t{FR['ContentView']} /* ContentView.swift */,")
    a(f"\t\t\t\t{FR['EggSpendTheme']} /* EggSpendTheme.swift */,")
    a(f"\t\t\t\t{FR['Entitlements']} /* EggSpend.entitlements */,")
    a(f"\t\t\t\t{FR['PrivacyInfo']} /* PrivacyInfo.xcprivacy */,")
    a(f"\t\t\t\t{GR['Models']} /* Models */,")
    a(f"\t\t\t\t{GR['Views']} /* Views */,")
    a(f"\t\t\t\t{GR['Utilities']} /* Utilities */,")
    a(f"\t\t\t\t{GR['Persistence']} /* Persistence */,")
    a(f"\t\t\t\t{FR['Assets']} /* Assets.xcassets */,")
    a(f"\t\t\t);")
    a(f"\t\t\tpath = EggSpend;")
    a(f"\t\t\tsourceTree = \"<group>\";")
    a(f"\t\t}};")

    # Models group
    a(f"\t\t{GR['Models']} /* Models */ = {{")
    a(f"\t\t\tisa = PBXGroup;")
    a(f"\t\t\tchildren = (")
    a(f"\t\t\t\t{FR['Transaction']} /* Transaction.swift */,")
    a(f"\t\t\t\t{FR['TransactionCategory']} /* TransactionCategory.swift */,")
    a(f"\t\t\t\t{FR['Account']} /* Account.swift */,")
    a(f"\t\t\t\t{FR['Budget']} /* Budget.swift */,")
    a(f"\t\t\t\t{FR['RecurringTransaction']} /* RecurringTransaction.swift */,")
    a(f"\t\t\t\t{FR['SavingsGoal']} /* SavingsGoal.swift */,")
    a(f"\t\t\t\t{FR['Transfer']} /* Transfer.swift */,")
    a(f"\t\t\t\t{FR['BalanceSnapshot']} /* BalanceSnapshot.swift */,")
    a(f"\t\t\t\t{FR['CategoryRule']} /* CategoryRule.swift */,")
    a(f"\t\t\t);")
    a(f"\t\t\tpath = Models;")
    a(f"\t\t\tsourceTree = \"<group>\";")
    a(f"\t\t}};")

    # Views group
    a(f"\t\t{GR['Views']} /* Views */ = {{")
    a(f"\t\t\tisa = PBXGroup;")
    a(f"\t\t\tchildren = (")
    a(f"\t\t\t\t{GR['Dashboard']} /* Dashboard */,")
    a(f"\t\t\t\t{GR['Transactions']} /* Transactions */,")
    a(f"\t\t\t\t{GR['Budget']} /* Budget */,")
    a(f"\t\t\t\t{GR['Recurring']} /* Recurring */,")
    a(f"\t\t\t\t{GR['Subscriptions']} /* Subscriptions */,")
    a(f"\t\t\t\t{GR['ImportViews']} /* Import */,")
    a(f"\t\t\t\t{GR['NetWorth']} /* NetWorth */,")
    a(f"\t\t\t\t{GR['Metrics']} /* Metrics */,")
    a(f"\t\t\t\t{GR['Accounts']} /* Accounts */,")
    a(f"\t\t\t\t{GR['Components']} /* Components */,")
    a(f"\t\t\t\t{GR['Categories']} /* Categories */,")
    a(f"\t\t\t\t{GR['Forecast']} /* Forecast */,")
    a(f"\t\t\t\t{GR['MonthlyReview']} /* MonthlyReview */,")
    a(f"\t\t\t\t{GR['SavingsGoals']} /* SavingsGoals */,")
    a(f"\t\t\t\t{GR['SafeSpend']} /* SafeSpend */,")
    a(f"\t\t\t\t{GR['Settings']} /* Settings */,")
    a(f"\t\t\t);")
    a(f"\t\t\tpath = Views;")
    a(f"\t\t\tsourceTree = \"<group>\";")
    a(f"\t\t}};")

    def simple_group(grp_key, grp_path, file_keys):
        a(f"\t\t{GR[grp_key]} /* {grp_key} */ = {{")
        a(f"\t\t\tisa = PBXGroup;")
        a(f"\t\t\tchildren = (")
        for fk in file_keys:
            fn = fk.split("/")[-1] if "/" in fk else fk
            a(f"\t\t\t\t{FR[fk]} /* {fn}.swift */,")
        a(f"\t\t\t);")
        a(f"\t\t\tpath = {grp_path};")
        a(f"\t\t\tsourceTree = \"<group>\";")
        a(f"\t\t}};")

    simple_group("Dashboard",    "Dashboard",    ["DashboardView"])
    simple_group("Transactions", "Transactions", ["TransactionsListView","AddTransactionView","TransactionDetailView","TransactionFilterView","TransferDetailView"])
    simple_group("Budget",       "Budget",       ["BudgetView","AddBudgetView","BudgetDetailView"])
    simple_group("Recurring",    "Recurring",    ["RecurringTransactionsView","RecurringNext30DaysView","AddRecurringTransactionView"])
    simple_group("Subscriptions", "Subscriptions", ["SubscriptionAuditView"])
    simple_group("NetWorth",     "NetWorth",     ["NetWorthView"])
    simple_group("Metrics",      "Metrics",      ["MetricsView"])
    simple_group("Accounts",     "Accounts",     ["AccountsView","AddAccountView","DebtPayoffPlannerView"])
    simple_group("Components",   "Components",   ["NestHeaderView","EggProgressView","BirdAnimationView","FloatingLeavesView","AnimatedCanopyBackground","CategoryBadgeView","AmountLabel","TransactionRowView","TransferRowView"])
    simple_group("ImportViews",  "Import",       ["CSVImportView"])
    simple_group("Categories",   "Categories",   ["CategoryManagementView", "AddEditCategoryView"])
    simple_group("Utilities",    "Utilities",    ["CSVParser", "AccountBalanceService", "TransferBalanceService", "MonthlyReviewCalculator", "NetWorthCalculator", "TransactionFilter", "SafeSpendCalculator", "DebtPayoffCalculator", "RecurringProjection", "NotificationScheduler", "BudgetAlertCoordinator", "AmountParser", "CurrencyFormat", "DataExporter", "BalanceSnapshotService", "SubscriptionDetector", "CategoryRuleEngine"])
    simple_group("Forecast",    "Forecast",     ["ForecastEngine", "CashFlowForecastView", "CashFlowCalendarView"])
    simple_group("MonthlyReview", "MonthlyReview", ["MonthlyReviewView"])
    simple_group("SavingsGoals", "SavingsGoals", ["SavingsGoalsView", "AddSavingsGoalView"])
    simple_group("SafeSpend",   "SafeSpend",    ["SafeToSpendView"])
    simple_group("Settings",   "Settings",     ["SettingsView"])
    simple_group("Persistence",  "Persistence",  ["PersistenceController", "SyncStatus"])

    # Tests group
    a(f"\t\t{GR['Tests']} /* EggSpendTests */ = {{")
    a(f"\t\t\tisa = PBXGroup;")
    a(f"\t\t\tchildren = (")
    for key, path in TEST_SOURCES:
        filename = path.split("/")[-1]
        a(f"\t\t\t\t{FR[key]} /* {filename} */,")
    a(f"\t\t\t);")
    a(f"\t\t\tpath = EggSpendTests;")
    a(f"\t\t\tsourceTree = \"<group>\";")
    a(f"\t\t}};")

    a("\t\t/* End PBXGroup section */")
    a("")

    # ── PBXNativeTarget ────────────────────────────────────────────────────
    a("\t\t/* Begin PBXNativeTarget section */")
    a(f"\t\t{TG_APP} /* EggSpend */ = {{")
    a(f"\t\t\tisa = PBXNativeTarget;")
    a(f"\t\t\tbuildConfigurationList = {CL_APP} /* Build configuration list for PBXNativeTarget \"EggSpend\" */;")
    a(f"\t\t\tbuildPhases = (")
    a(f"\t\t\t\t{BP_APP_SRC} /* Sources */,")
    a(f"\t\t\t\t{BP_APP_FRM} /* Frameworks */,")
    a(f"\t\t\t\t{BP_APP_RES} /* Resources */,")
    a(f"\t\t\t);")
    a(f"\t\t\tbuildRules = (")
    a(f"\t\t\t);")
    a(f"\t\t\tdependencies = (")
    a(f"\t\t\t);")
    a(f"\t\t\tname = EggSpend;")
    a(f"\t\t\tproductName = EggSpend;")
    a(f"\t\t\tproductReference = {FR['PROD_APP']} /* EggSpend.app */;")
    a(f"\t\t\tproductType = \"com.apple.product-type.application\";")
    a(f"\t\t}};")
    a(f"\t\t{TG_TEST} /* EggSpendTests */ = {{")
    a(f"\t\t\tisa = PBXNativeTarget;")
    a(f"\t\t\tbuildConfigurationList = {CL_TEST} /* Build configuration list for PBXNativeTarget \"EggSpendTests\" */;")
    a(f"\t\t\tbuildPhases = (")
    a(f"\t\t\t\t{BP_TEST_SRC} /* Sources */,")
    a(f"\t\t\t\t{BP_TEST_FRM} /* Frameworks */,")
    a(f"\t\t\t);")
    a(f"\t\t\tbuildRules = (")
    a(f"\t\t\t);")
    a(f"\t\t\tdependencies = (")
    a(f"\t\t\t\t{TD_TEST} /* PBXTargetDependency */,")
    a(f"\t\t\t);")
    a(f"\t\t\tname = EggSpendTests;")
    a(f"\t\t\tproductName = EggSpendTests;")
    a(f"\t\t\tproductReference = {FR['PROD_TEST']} /* EggSpendTests.xctest */;")
    a(f"\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    a(f"\t\t}};")
    a("\t\t/* End PBXNativeTarget section */")
    a("")

    # ── PBXProject ─────────────────────────────────────────────────────────
    a("\t\t/* Begin PBXProject section */")
    a(f"\t\t{PROJECT} /* Project object */ = {{")
    a(f"\t\t\tisa = PBXProject;")
    a(f"\t\t\tattributes = {{")
    a(f"\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    a(f"\t\t\t\tLastSwiftUpdateCheck = 1600;")
    a(f"\t\t\t\tLastUpgradeCheck = 1600;")
    a(f"\t\t\t\tTargetAttributes = {{")
    a(f"\t\t\t\t\t{TG_APP} = {{")
    a(f"\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    a(f"\t\t\t\t\t\tDevelopmentTeam = 5T5444U7W2;")
    a(f"\t\t\t\t\t\tProvisioningStyle = Automatic;")
    a(f"\t\t\t\t\t\tSystemCapabilities = {{")
    a(f"\t\t\t\t\t\t\tcom.apple.iCloud = {{")
    a(f"\t\t\t\t\t\t\t\tenabled = 1;")
    a(f"\t\t\t\t\t\t\t}};")
    a(f"\t\t\t\t\t\t}};")
    a(f"\t\t\t\t\t}};")
    a(f"\t\t\t\t\t{TG_TEST} = {{")
    a(f"\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    a(f"\t\t\t\t\t\tDevelopmentTeam = 5T5444U7W2;")
    a(f"\t\t\t\t\t\tProvisioningStyle = Automatic;")
    a(f"\t\t\t\t\t\tTestTargetID = {TG_APP};")
    a(f"\t\t\t\t\t}};")
    a(f"\t\t\t\t}};")
    a(f"\t\t\t}};")
    a(f"\t\t\tbuildConfigurationList = {CL_PROJECT} /* Build configuration list for PBXProject \"EggSpend\" */;")
    a(f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    a(f"\t\t\tdevelopmentRegion = en;")
    a(f"\t\t\thasScannedForEncodings = 0;")
    a(f"\t\t\tknownRegions = (")
    a(f"\t\t\t\ten,")
    a(f"\t\t\t\tBase,")
    a(f"\t\t\t);")
    a(f"\t\t\tmainGroup = {GR['Root']};")
    a(f"\t\t\tproductRefGroup = {GR['Products']} /* Products */;")
    a(f"\t\t\tprojectDirPath = \"\";")
    a(f"\t\t\tprojectRoot = \"\";")
    a(f"\t\t\ttargets = (")
    a(f"\t\t\t\t{TG_APP} /* EggSpend */,")
    a(f"\t\t\t\t{TG_TEST} /* EggSpendTests */,")
    a(f"\t\t\t);")
    a(f"\t\t}};")
    a("\t\t/* End PBXProject section */")
    a("")

    # ── PBXResourcesBuildPhase ──────────────────────────────────────────────
    a("\t\t/* Begin PBXResourcesBuildPhase section */")
    a(f"\t\t{BP_APP_RES} /* Resources */ = {{")
    a(f"\t\t\tisa = PBXResourcesBuildPhase;")
    a(f"\t\t\tbuildActionMask = 2147483647;")
    a(f"\t\t\tfiles = (")
    a(f"\t\t\t\t{BF['Assets']} /* Assets.xcassets in Resources */,")
    a(f"\t\t\t\t{BF['PrivacyInfo']} /* PrivacyInfo.xcprivacy in Resources */,")
    a(f"\t\t\t);")
    a(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a(f"\t\t}};")
    a("\t\t/* End PBXResourcesBuildPhase section */")
    a("")

    # ── PBXSourcesBuildPhase ────────────────────────────────────────────────
    a("\t\t/* Begin PBXSourcesBuildPhase section */")
    a(f"\t\t{BP_APP_SRC} /* Sources */ = {{")
    a(f"\t\t\tisa = PBXSourcesBuildPhase;")
    a(f"\t\t\tbuildActionMask = 2147483647;")
    a(f"\t\t\tfiles = (")
    for key, path in APP_SOURCES:
        filename = path.split("/")[-1]
        a(f"\t\t\t\t{BF[key]} /* {filename} in Sources */,")
    a(f"\t\t\t);")
    a(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a(f"\t\t}};")
    a(f"\t\t{BP_TEST_SRC} /* Sources */ = {{")
    a(f"\t\t\tisa = PBXSourcesBuildPhase;")
    a(f"\t\t\tbuildActionMask = 2147483647;")
    a(f"\t\t\tfiles = (")
    for key, path in TEST_SOURCES:
        filename = path.split("/")[-1]
        a(f"\t\t\t\t{BF[key]} /* {filename} in Sources */,")
    a(f"\t\t\t);")
    a(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a(f"\t\t}};")
    a("\t\t/* End PBXSourcesBuildPhase section */")
    a("")

    # ── PBXTargetDependency ─────────────────────────────────────────────────
    a("\t\t/* Begin PBXTargetDependency section */")
    a(f"\t\t{TD_TEST} /* PBXTargetDependency */ = {{")
    a(f"\t\t\tisa = PBXTargetDependency;")
    a(f"\t\t\ttarget = {TG_APP} /* EggSpend */;")
    a(f"\t\t\ttargetProxy = {CI_TEST} /* PBXContainerItemProxy */;")
    a(f"\t\t}};")
    a("\t\t/* End PBXTargetDependency section */")
    a("")

    # ── XCBuildConfiguration ────────────────────────────────────────────────
    a("\t\t/* Begin XCBuildConfiguration section */")

    def project_config(uuid, name):
        a(f"\t\t{uuid} /* {name} */ = {{")
        a(f"\t\t\tisa = XCBuildConfiguration;")
        a(f"\t\t\tbuildSettings = {{")
        a(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
        a(f"\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
        a(f"\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;")
        a(f"\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
        a(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
        a(f"\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
        a(f"\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;")
        a(f"\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;")
        a(f"\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;")
        a(f"\t\t\t\tCLANG_WARN_COMMA = YES;")
        a(f"\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;")
        a(f"\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;")
        a(f"\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;")
        a(f"\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;")
        a(f"\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;")
        a(f"\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;")
        a(f"\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;")
        a(f"\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;")
        a(f"\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;")
        a(f"\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;")
        a(f"\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;")
        a(f"\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;")
        a(f"\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;")
        a(f"\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;")
        a(f"\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;")
        a(f"\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;")
        a(f"\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;")
        a(f"\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;")
        a(f"\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;")
        a(f"\t\t\t\tCOPY_PHASE_STRIP = NO;")
        debug_only = name == "Debug"
        a(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = {'dwarf' if debug_only else 'dwarf-with-dsym'};")
        a(f"\t\t\t\tENABLE_NS_ASSERTIONS = {'YES' if debug_only else 'NO'};")
        a(f"\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
        a(f"\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
        a(f"\t\t\t\tGCC_DYNAMIC_NO_PIC = {'NO' if debug_only else 'YES'};")
        a(f"\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
        a(f"\t\t\t\tGCC_OPTIMIZATION_LEVEL = {'0' if debug_only else 's'};")
        a(f"\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (")
        if debug_only:
            a(f"\t\t\t\t\t\"DEBUG=1\",")
        a(f"\t\t\t\t\t\"$(inherited)\",")
        a(f"\t\t\t\t);")
        a(f"\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
        a(f"\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
        a(f"\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
        a(f"\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
        a(f"\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
        a(f"\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
        a(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
        a(f"\t\t\t\tMTL_ENABLE_DEBUG_INFO = {'INCLUDE_SOURCE' if debug_only else 'NO'};")
        a(f"\t\t\t\tMTL_FAST_MATH = YES;")
        a(f"\t\t\t\tONLY_ACTIVE_ARCH = {'YES' if debug_only else 'NO'};")
        a(f"\t\t\t\tSDKROOT = iphoneos;")
        if debug_only:
            a(f"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";")
            a(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
        else:
            a(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
        a(f"\t\t\t}};")
        a(f"\t\t\tname = {name};")
        a(f"\t\t}};")

    project_config(BC_PROJ_DBG, "Debug")
    project_config(BC_PROJ_REL, "Release")

    def app_config(uuid, name):
        debug = name == "Debug"
        a(f"\t\t{uuid} /* {name} */ = {{")
        a(f"\t\t\tisa = XCBuildConfiguration;")
        a(f"\t\t\tbuildSettings = {{")
        a(f"\t\t\t\tASSTCATALOG_COMPILER_APPICON_NAME = AppIcon;")
        a(f"\t\t\t\tASSTCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
        a(f"\t\t\t\tASETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
        a(f"\t\t\t\tASETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
        a(f"\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
        a(f"\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
        a(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = EggSpend/EggSpend.entitlements;")
        a(f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")
        a(f"\t\t\t\tDEVELOPMENT_TEAM = 5T5444U7W2;")
        if debug:
            a(f"\t\t\t\tENABLE_TESTABILITY = YES;")
        a(f"\t\t\t\tCURRENT_PROJECT_VERSION = 5;")
        a(f"\t\t\t\tENABLE_PREVIEWS = YES;")
        a(f"\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
        a(f"\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = EggSpend;")
        a(f"\t\t\t\tINFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;")
        a(f"\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;")
        a(f"\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;")
        a(f"\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;")
        a(f"\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown\";")
        a(f"\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = \"UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait\";")
        a(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
        a(f"\t\t\t\tMARKETING_VERSION = 1.1;")
        a(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = dev.gnwn.EggSpend;")
        a(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
        a(f"\t\t\t\tSDKROOT = iphoneos;")
        a(f"\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
        a(f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
        a(f"\t\t\t\tSWIFT_VERSION = 6.0;")
        a(f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
        a(f"\t\t\t}};")
        a(f"\t\t\tname = {name};")
        a(f"\t\t}};")

    app_config(BC_APP_DBG, "Debug")
    app_config(BC_APP_REL, "Release")

    def test_config(uuid, name):
        a(f"\t\t{uuid} /* {name} */ = {{")
        a(f"\t\t\tisa = XCBuildConfiguration;")
        a(f"\t\t\tbuildSettings = {{")
        a(f"\t\t\t\tBUNDLE_LOADER = \"$(TEST_HOST)\";")
        a(f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")
        a(f"\t\t\t\tDEVELOPMENT_TEAM = 5T5444U7W2;")
        a(f"\t\t\t\tCURRENT_PROJECT_VERSION = 5;")
        a(f"\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
        a(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
        a(f"\t\t\t\tMARKETING_VERSION = 1.1;")
        a(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = dev.gnwn.EggSpendTests;")
        a(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
        a(f"\t\t\t\tSDKROOT = iphoneos;")
        a(f"\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
        a(f"\t\t\t\tSWIFT_VERSION = 6.0;")
        a(f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
        a(f"\t\t\t\tTEST_HOST = \"$(BUILT_PRODUCTS_DIR)/EggSpend.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/EggSpend\";")
        a(f"\t\t\t}};")
        a(f"\t\t\tname = {name};")
        a(f"\t\t}};")

    test_config(BC_TEST_DBG, "Debug")
    test_config(BC_TEST_REL, "Release")

    a("\t\t/* End XCBuildConfiguration section */")
    a("")

    # ── XCConfigurationList ─────────────────────────────────────────────────
    a("\t\t/* Begin XCConfigurationList section */")
    a(f"\t\t{CL_PROJECT} /* Build configuration list for PBXProject \"EggSpend\" */ = {{")
    a(f"\t\t\tisa = XCConfigurationList;")
    a(f"\t\t\tbuildConfigurations = (")
    a(f"\t\t\t\t{BC_PROJ_DBG} /* Debug */,")
    a(f"\t\t\t\t{BC_PROJ_REL} /* Release */,")
    a(f"\t\t\t);")
    a(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    a(f"\t\t\tdefaultConfigurationName = Release;")
    a(f"\t\t}};")
    a(f"\t\t{CL_APP} /* Build configuration list for PBXNativeTarget \"EggSpend\" */ = {{")
    a(f"\t\t\tisa = XCConfigurationList;")
    a(f"\t\t\tbuildConfigurations = (")
    a(f"\t\t\t\t{BC_APP_DBG} /* Debug */,")
    a(f"\t\t\t\t{BC_APP_REL} /* Release */,")
    a(f"\t\t\t);")
    a(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    a(f"\t\t\tdefaultConfigurationName = Release;")
    a(f"\t\t}};")
    a(f"\t\t{CL_TEST} /* Build configuration list for PBXNativeTarget \"EggSpendTests\" */ = {{")
    a(f"\t\t\tisa = XCConfigurationList;")
    a(f"\t\t\tbuildConfigurations = (")
    a(f"\t\t\t\t{BC_TEST_DBG} /* Debug */,")
    a(f"\t\t\t\t{BC_TEST_REL} /* Release */,")
    a(f"\t\t\t);")
    a(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    a(f"\t\t\tdefaultConfigurationName = Release;")
    a(f"\t\t}};")
    a("\t\t/* End XCConfigurationList section */")
    a("")

    a("\t};")
    a(f"\trootObject = {PROJECT} /* Project object */;")
    a("}")

    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    base = os.path.dirname(os.path.abspath(__file__))
    proj_dir = os.path.join(base, "EggSpend.xcodeproj")
    os.makedirs(proj_dir, exist_ok=True)
    pbxproj_path = os.path.join(proj_dir, "project.pbxproj")
    content = pbxproj()
    with open(pbxproj_path, "w") as f:
        f.write(content)
    print(f"Generated: {pbxproj_path}")
    print(f"Lines: {len(content.splitlines())}")
