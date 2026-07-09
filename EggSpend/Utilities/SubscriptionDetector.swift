import Foundation

/// Detects recurring "subscription-shaped" spending from ordinary transaction
/// history — distinct from `RecurringTransaction`, which is an explicit,
/// user-declared schedule. This groups historical `Transaction` rows by a
/// normalized merchant key, checks for a stable cadence and amount, and
/// surfaces candidates the user hasn't already set up as a recurring item.
/// UI for reviewing/converting detections is a separate (T16b) concern —
/// this file is detection-only and never touches `ModelContext` or balances.
enum SubscriptionDetector {

    // MARK: - Clustering key

    /// Builds on `CSVParser.normalizedTitle` (lowercased, trimmed, whitespace
    /// collapsed) and additionally strips digits and non-letter punctuation so
    /// statement-line reference numbers don't fragment one merchant into many
    /// clusters, e.g. "netflix.com 0423" and "Netflix.com 0523" both key to
    /// "netflix com". Punctuation runs still separate distinct merchant
    /// strings, e.g. "apple.com/bill" -> "apple com bill", which stays
    /// distinct from "apple store".
    private static func clusterKey(_ raw: String) -> String {
        var key = CSVParser.normalizedTitle(raw)
        key = key.replacingOccurrences(of: "[0-9]", with: "", options: .regularExpression)
        key = key.replacingOccurrences(of: "[^a-z ]+", with: " ", options: .regularExpression)
        key = key.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return key.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Result

    struct DetectedSubscription: Identifiable {
        var id: String { normalizedKey }

        /// Most recent transaction's original (unnormalized) title.
        let title: String
        let normalizedKey: String
        let cadence: RecurrenceFrequency
        /// Rounded-to-cents mode of the cluster's HISTORICAL amounts (every
        /// occurrence except the most recent). Excluding the latest lets a
        /// genuine price bump be flagged via `priceChanged` instead of
        /// tainting the stability check it would otherwise be judged
        /// against. Ties are broken in favor of the most recent historical
        /// occurrence's amount (see `modeAmount`).
        let modeAmount: Double
        /// The most recent occurrence's actual (unrounded) amount — the price
        /// the user is currently being charged.
        let latestAmount: Double
        /// True when the latest charge differs (after cent-rounding) from the
        /// cluster's historical mode amount.
        let priceChanged: Bool
        /// Both cost fields are derived from `latestAmount`, not
        /// `modeAmount` — they reflect what the user pays going forward.
        let monthlyCost: Double
        let annualizedCost: Double
        let occurrenceCount: Int
        let lastDate: Date
        /// First cadence-projected occurrence strictly after `now`.
        let nextExpectedDate: Date
        /// Most common category across the cluster, or `nil` if there's no
        /// single most-common category (a tie, i.e. "mixed").
        let category: TransactionCategory?
        /// The account shared by every transaction in the cluster, or `nil`
        /// if the cluster spans more than one account (or account-less rows
        /// mixed with account-linked ones).
        let account: Account?
    }

    // MARK: - Detection

    /// Scans `transactions` for expense clusters that look like subscriptions:
    /// 3+ occurrences of the same normalized merchant, a consistent cadence,
    /// and a stable amount — excluding anything already tracked as an active
    /// `RecurringTransaction`.
    static func detect(
        transactions: [Transaction],
        recurring: [RecurringTransaction],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DetectedSubscription] {
        // Only organic expense history is subscription-shaped: generated
        // rows are already-materialized recurring charges, and adjustments
        // aren't real merchant activity.
        let candidates = transactions.filter { $0.type == .expense && !$0.isGenerated && !$0.isAdjustment }

        var clusters: [String: [Transaction]] = [:]
        for tx in candidates {
            clusters[clusterKey(tx.title), default: []].append(tx)
        }

        // Active (not paused) recurring items suppress detection of the same
        // merchant — the user has already declared this as recurring. Paused
        // items (isActive == false) intentionally do not suppress, so a
        // user who paused a subscription still sees it surfaced again.
        let activeRecurringKeys = Set(
            recurring.filter(\.isActive).map { clusterKey($0.title) }
        )

        var results: [DetectedSubscription] = []

        for (key, txs) in clusters {
            guard txs.count >= 3 else { continue }
            guard !activeRecurringKeys.contains(key) else { continue }

            let sorted = txs.sorted { $0.date < $1.date }
            guard let cadence = detectCadence(dates: sorted.map(\.date), calendar: calendar) else { continue }

            let latest = sorted[sorted.count - 1]
            let latestRounded = roundToCents(latest.amount)

            // Stability is judged on the HISTORY only (everything but the
            // most recent occurrence). A genuine price increase on the
            // latest charge must not get lumped in with — and reject the
            // whole cluster alongside — actually erratic historical
            // amounts. `sorted.count >= 3` (checked above) guarantees at
            // least 2 historical occurrences here.
            let historical = sorted.dropLast()
            let historicalRounded = historical.map { roundToCents($0.amount) }
            let mode = modeAmount(historicalRounded, recent: historicalRounded.last ?? latestRounded)
            guard historicalRounded.allSatisfy({ isWithinPercentage($0, of: mode, tolerance: 0.1) }) else { continue }

            // Wide sanity bound on the latest occurrence only: a real price
            // bump (even a steep one — Netflix's real-world increases have
            // run ~11-16%) must still surface with `priceChanged = true`,
            // but a same-merchant-key charge that's wildly different (e.g. a
            // one-off $200 purchase where a $15.49 subscription usually
            // posts) is unrelated activity, not a price change. 50% is
            // deliberately generous so only genuinely unrelated charges are
            // caught here, not real subscription price increases.
            guard isWithinPercentage(latestRounded, of: mode, tolerance: 0.5) else { continue }

            // Cost fields use the latest amount — what the user is paying
            // going forward — not the historical mode.
            let monthly = monthlyCost(amount: latest.amount, cadence: cadence)

            results.append(DetectedSubscription(
                title: latest.title,
                normalizedKey: key,
                cadence: cadence,
                modeAmount: mode,
                latestAmount: latest.amount,
                // Exact inequality against the historical mode, now that the
                // latest occurrence is evaluated separately from it above.
                priceChanged: latestRounded != mode,
                monthlyCost: monthly,
                annualizedCost: monthly * 12,
                occurrenceCount: sorted.count,
                lastDate: latest.date,
                nextExpectedDate: nextFutureOccurrence(after: latest.date, cadence: cadence, now: now, calendar: calendar),
                category: dominantCategory(sorted),
                account: consistentAccount(sorted)
            ))
        }

        return results.sorted { lhs, rhs in
            if lhs.monthlyCost != rhs.monthlyCost { return lhs.monthlyCost > rhs.monthlyCost }
            return lhs.normalizedKey < rhs.normalizedKey
        }
    }

    // MARK: - Cadence

    /// Non-overlapping day-gap windows. Every consecutive gap in a cluster
    /// must fall in the *same* window for a cadence to be assigned — mixed
    /// gaps (e.g. some ~7-day, some ~30-day) are rejected as erratic rather
    /// than guessed at.
    private static let cadenceWindows: [(RecurrenceFrequency, ClosedRange<Int>)] = [
        (.weekly, 4...10),
        (.biweekly, 11...17),
        (.monthly, 27...34),
        (.yearly, 362...369)
    ]

    private static func detectCadence(dates: [Date], calendar: Calendar) -> RecurrenceFrequency? {
        guard dates.count >= 2 else { return nil }
        let gaps: [Int] = zip(dates, dates.dropFirst()).map { earlier, later in
            calendar.dateComponents([.day], from: earlier, to: later).day ?? 0
        }
        for (frequency, window) in cadenceWindows where gaps.allSatisfy({ window.contains($0) }) {
            return frequency
        }
        return nil
    }

    // MARK: - Amount helpers

    private static func roundToCents(_ amount: Double) -> Double {
        (amount * 100).rounded() / 100
    }

    /// Rounded-cents mode of `amounts`. When multiple values tie for the
    /// highest count, the most recent occurrence's amount (of the amounts
    /// being modeled — historical occurrences, since the caller excludes the
    /// latest) wins if it's one of the tied values; otherwise the smallest
    /// tied value is used so the result stays deterministic.
    private static func modeAmount(_ amounts: [Double], recent: Double) -> Double {
        var counts: [Double: Int] = [:]
        for amount in amounts { counts[amount, default: 0] += 1 }
        let maxCount = counts.values.max() ?? 0
        let tied = counts.filter { $0.value == maxCount }.map(\.key)
        if tied.contains(recent) { return recent }
        return tied.sorted().first ?? recent
    }

    private static func isWithinPercentage(_ amount: Double, of mode: Double, tolerance: Double) -> Bool {
        guard mode != 0 else { return amount == 0 }
        return abs(amount - mode) <= abs(mode) * tolerance
    }

    private static func monthlyCost(amount: Double, cadence: RecurrenceFrequency) -> Double {
        switch cadence {
        case .weekly:   return amount * 52 / 12
        case .biweekly: return amount * 26 / 12
        case .monthly:  return amount
        case .yearly:   return amount / 12
        case .daily:
            // `detectCadence` never produces `.daily` (no daily window
            // above); included only so this switch stays exhaustive.
            return amount * 365 / 12
        }
    }

    // MARK: - Category / account consistency

    private static func dominantCategory(_ txs: [Transaction]) -> TransactionCategory? {
        // Group by category identity (nil/uncategorized counts as its own
        // group). Clusters are small, so a linear scan is fine here.
        var groups: [(category: TransactionCategory?, count: Int)] = []
        for tx in txs {
            if let idx = groups.firstIndex(where: { $0.category?.id == tx.category?.id }) {
                groups[idx].count += 1
            } else {
                groups.append((tx.category, 1))
            }
        }
        let maxCount = groups.map(\.count).max() ?? 0
        let top = groups.filter { $0.count == maxCount }
        // A tie between two or more categories (or a category vs.
        // uncategorized) is reported as "mixed" -> nil rather than
        // arbitrarily picking one.
        guard top.count == 1 else { return nil }
        return top[0].category
    }

    private static func consistentAccount(_ txs: [Transaction]) -> Account? {
        let ids = Set(txs.map { $0.account?.id })
        return ids.count == 1 ? txs.first?.account : nil
    }

    // MARK: - Future occurrence projection

    /// Advances `after` forward by `cadence` until strictly past `now`.
    /// Mirrors `RecurringTransaction.advanceNextDueDate`'s calendar math, with
    /// the same non-advancing guard to avoid looping forever on a malformed
    /// calendar/frequency combination.
    static func nextFutureOccurrence(
        after lastDate: Date,
        cadence: RecurrenceFrequency,
        now: Date,
        calendar: Calendar
    ) -> Date {
        var cursor = lastDate
        while cursor <= now {
            let advanced = calendar.date(
                byAdding: cadence.calendarComponent,
                value: cadence.calendarValue,
                to: cursor
            ) ?? cursor
            guard advanced > cursor else { break }
            cursor = advanced
        }
        return cursor
    }

    // MARK: - Conversion into a RecurringTransaction

    /// Field values for creating a `RecurringTransaction` from a detected
    /// subscription. Model creation/insertion into a `ModelContext` is a
    /// T16b UI concern; this only computes the values.
    ///
    /// `amount` uses `latestAmount` — the price the user is *currently* being
    /// charged — rather than `modeAmount`, so converting a subscription that
    /// just had a price increase doesn't lock in a stale historical price.
    ///
    /// CRITICAL: `startDate`/`nextDueDate` MUST be strictly in the future
    /// (`nextFutureOccurrence` guarantees this). `processRecurringTransactions`
    /// materializes a `Transaction` for every due date <= now in a while loop
    /// (see `RecurringTransaction.swift`). If `nextDueDate` were left at or
    /// before the last historical charge, launch-time processing would
    /// generate duplicate back-charges for occurrences that already exist as
    /// ordinary (non-generated) transactions in history — this is the trap
    /// this function exists to avoid.
    ///
    /// No `AccountBalanceService` call is needed here, nor in the eventual
    /// T16b insertion of the `RecurringTransaction` itself: creating the
    /// schedule doesn't move money by itself. The next charge only affects
    /// account balances once `processRecurringTransactions` later
    /// materializes it as a real `Transaction`.
    static func conversionFields(
        for detected: DetectedSubscription,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (title: String, amount: Double, type: TransactionType, frequency: RecurrenceFrequency, startDate: Date, nextDueDate: Date) {
        let nextDue = nextFutureOccurrence(after: detected.lastDate, cadence: detected.cadence, now: now, calendar: calendar)
        return (
            title: detected.title,
            amount: detected.latestAmount,
            type: .expense,
            frequency: detected.cadence,
            startDate: nextDue,
            nextDueDate: nextDue
        )
    }
}
