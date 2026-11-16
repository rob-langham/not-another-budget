package app.longview

import app.longview.domain.Balances
import app.longview.domain.Money
import app.longview.domain.RuleEngine
import app.longview.domain.daysBetween
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil

/** Read-only calculations over a [Ledger]. Nothing here touches the database. */
class Views(private val l: Ledger, private val today: LocalDate, private val receiptsDomain: String = "") {

    private val dm = DateTimeFormatter.ofPattern("d MMM", Locale.UK)
    private fun short(d: LocalDate) = d.format(dm)

    // ---------- accounts ----------

    private val txByAccountDate: Map<Long, Map<LocalDate, Long>> =
        l.transactions.groupBy { it.accountId }.mapValues { (_, list) -> list.groupBy { it.date }.mapValues { e -> e.value.sumOf { it.amount } } }

    fun balanceOf(a: Acc): Long =
        Balances.current(a.openingBalance, a.openingDate, txByAccountDate[a.id].orEmpty(), l.overrides[a.id].orEmpty(), today)

    fun dailyBalances(a: Acc, days: Int): List<DayBalanceDto> {
        val from = today.minusDays(days.toLong() - 1)
        return Balances.daily(a.openingBalance, a.openingDate, txByAccountDate[a.id].orEmpty(), l.overrides[a.id].orEmpty(), from, today)
            .reversed().map { DayBalanceDto(it.date.toString(), it.calculated, it.balance, it.overridden, it.note) }
    }

    fun account(a: Acc): AccountDto = AccountDto(
        a.id, a.name, a.type, a.source, balanceOf(a), a.countsTowardsSavings, a.lastSyncedAt,
        a.openingBalance, a.openingDate.toString(), logo(a),
        l.transactions.firstOrNull { it.accountId == a.id }?.date?.toString(),
    )

    fun accounts() = l.accounts.map(::account)

    /** Logo order for "automatic": uploaded image → website icon → social picture → letter icon. */
    private fun logo(a: Acc): LogoDto {
        // Every image goes through the API (see LogoFetcher) so browsers don't hit CORS and third parties never see the viewer.
        val proxied = "/api/accounts/${a.id}/logo?v=" + (a.logoMode + a.logoWebsite + a.logoSocial + a.hasUpload).hashCode().toUInt().toString(16)
        fun site(@Suppress("UNUSED_PARAMETER") w: String) = proxied
        fun social(@Suppress("UNUSED_PARAMETER") h: String) = proxied
        val upload = if (a.hasUpload) proxied else null
        val (resolved, url) = when (a.logoMode) {
            "upload" -> if (upload != null) "upload" to upload else "letter" to null
            "website" -> if (!a.logoWebsite.isNullOrBlank()) "website" to site(a.logoWebsite) else "letter" to null
            "social" -> if (!a.logoSocial.isNullOrBlank()) "social" to social(a.logoSocial) else "letter" to null
            "letter" -> "letter" to null
            else -> when {
                upload != null -> "upload" to upload
                !a.logoWebsite.isNullOrBlank() -> "website" to site(a.logoWebsite)
                !a.logoSocial.isNullOrBlank() -> "social" to social(a.logoSocial)
                else -> "letter" to null
            }
        }
        return LogoDto(a.logoMode, resolved, url, a.name.firstOrNull()?.uppercase() ?: "?", a.logoColor, a.logoWebsite, a.logoSocial)
    }

    // ---------- transactions ----------

    /** Payments that tick off a bill and have no category of their own take the bill's category. */
    private val billCategory: Map<Long, Long> by lazy {
        val byName = l.scheduled.filter { it.categoryId != null }.associate { it.name to it.categoryId!! }
        l.transactions.map { YearMonth.from(it.date) }.distinct()
            .flatMap { m -> billMatches(m).entries }
            .mapNotNull { (txId, name) -> byName[name]?.let { txId to it } }.toMap()
    }

    private fun categoryOf(t: Tx): Long? = t.categoryId ?: if (t.awaitingReceipt) null else billCategory[t.id]

    /** Category spend lines for a transaction: its splits if it has any, else the whole amount. */
    private fun lines(t: Tx): List<Pair<Long?, Long>> =
        l.splitsByTx[t.id]?.takeIf { it.isNotEmpty() }?.map { it.categoryId to -abs(it.amount) * (if (t.amount < 0) 1 else -1) }
            ?: listOf(categoryOf(t) to t.amount)

    private fun kindOf(catId: Long?) = catId?.let { l.catById[it]?.kind } ?: "spending"

    fun txDto(t: Tx, outliers: Set<Long> = emptySet(), planned: Map<Long, String> = emptyMap()) = TransactionDto(
        t.id, t.accountId, l.accById[t.accountId]?.name ?: "", t.date.toString(), t.time?.toString(),
        t.merchant, t.description, t.amount, categoryOf(t), t.ruleId?.let { l.ruleById[it]?.name }, t.manualCategory,
        t.awaitingReceipt, t.notes, l.splitsByTx[t.id].orEmpty().map { SplitDto(it.id, it.name, it.amount, it.categoryId) },
        t.id in outliers, planned[t.id],
    )

    fun transactionPage(from: LocalDate, to: LocalDate, q: String?, categoryId: Long?, accountId: Long?): TransactionPage {
        val inRange = l.transactions.filter { !it.date.isBefore(from) && !it.date.isAfter(to) && (accountId == null || it.accountId == accountId) }
        val months = generateSequence(YearMonth.from(from)) { it.plusMonths(1) }.takeWhile { it <= YearMonth.from(to) }.toList()
        val outlierIds = months.flatMap { outlierTxs(it) }.map { it.id }.toSet()
        val planned = months.flatMap { m -> billMatches(m).map { it.key to it.value } }.toMap()
        val needle = q?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        val filtered = inRange.filter { t ->
            (needle == null || t.merchant.lowercase().contains(needle) || t.description.lowercase().contains(needle) ||
                l.splitsByTx[t.id].orEmpty().any { it.name.lowercase().contains(needle) }) &&
                (categoryId == null || lines(t).any { it.first == categoryId })
        }
        var spent = 0L; var moneyIn = 0L; var saved = 0L
        inRange.forEach { t ->
            lines(t).forEach { (c, a) ->
                when (kindOf(c)) {
                    "income" -> if (a > 0) moneyIn += a
                    "savings" -> saved += -a
                    "transfer" -> {}
                    else -> if (a < 0) spent += -a else spent -= a // refunds reduce spend
                }
            }
        }
        val pots = l.scheduled.filter { it.group == "pot" && it.categoryId != null }.groupBy { it.categoryId }
        val byCat = inRange.flatMap { t -> lines(t) }.filter { kindOf(it.first) == "spending" }
            .groupBy { it.first }
            .map { (c, ls) ->
                val cat = c?.let { l.catById[it] }
                CategoryTotal(c, cat?.name ?: "Uncategorised", cat?.color ?: "#8A8F98", -ls.sumOf { it.second }, ls.size,
                    pots[c]?.sumOf { it.repeat.monthlyEquivalent(it.amount) })
            }.sortedByDescending { it.total }
        return TransactionPage(from.toString(), to.toString(), spent, moneyIn, saved, filtered.size,
            filtered.map { txDto(it, outlierIds, planned) }, byCat)
    }

    // ---------- budget ----------

    /** txId -> scheduled expense name, for bills paid in [month]. Each payment ticks off at most one occurrence. */
    fun billMatches(month: YearMonth): Map<Long, String> {
        val used = HashSet<Long>()
        val out = HashMap<Long, String>()
        val monthTx = l.transactions.filter { YearMonth.from(it.date) == month && it.amount < 0 }.sortedBy { it.date }
        for (s in l.scheduled.filter { it.group != "pot" }) {
            val occ = if (s.group == "yearly") 1 else s.repeat.inMonth(month).size
            monthTx.filter { it.id !in used && (it.merchant.lowercase().contains(s.needle) || it.description.lowercase().contains(s.needle)) &&
                (s.accountId == null || s.accountId == it.accountId) }
                .take(occ).forEach { used += it.id; out[it.id] = s.name }
        }
        return out
    }

    fun budget(month: YearMonth): BudgetDto {
        val matches = billMatches(month)
        val txById = l.transactions.associateBy { it.id }
        val lines = l.scheduled.map { s ->
            val acc = s.accountId?.let { l.accById[it]?.name }
            val next = s.repeat.nextOnOrAfter(if (month == YearMonth.from(today)) today else month.atDay(1))
            when (s.group) {
                "pot" -> {
                    val used = -l.transactions.filter { YearMonth.from(it.date) == month }.flatMap(::lines)
                        .filter { it.first == s.categoryId }.sumOf { it.second }
                    val allowance = s.repeat.monthlyEquivalent(s.amount).takeIf { it > 0 } ?: s.amount
                    BudgetLine(s.id, s.name, s.group, "Monthly allowance", null, acc ?: "Any", allowance, "pot",
                        Money.format(used) + " of " + Money.format(allowance), used.coerceAtLeast(0))
                }
                "yearly" -> {
                    val monthly = s.repeat.monthlyEquivalent(s.amount)
                    val lastRenewal = s.repeat.occurrences(month.atEndOfMonth()).lastOrNull()
                    val monthsSince = lastRenewal?.let { java.time.temporal.ChronoUnit.MONTHS.between(YearMonth.from(it), month).toInt() } ?: 0
                    val putBy = (monthly * monthsSince).coerceAtMost(s.amount)
                    val renews = s.repeat.nextOnOrAfter(month.atDay(1))
                    BudgetLine(s.id, s.name, s.group, "Yearly → ${Money.format(monthly)} a month", renews?.toString(), acc, monthly,
                        "set_aside", "${Money.format(putBy)} of ${Money.format(s.amount)} put by", 0, putBy, s.amount)
                }
                else -> {
                    val occ = s.repeat.inMonth(month)
                    val paid = matches.filterValues { it == s.name }.keys.mapNotNull { txById[it] }
                    val due = occ.size * s.amount
                    val (status, text) = when {
                        occ.isEmpty() -> "not_due" to (next?.let { "Next due ${short(it)}" } ?: "Finished")
                        paid.size >= occ.size -> "paid" to "Paid ${short(paid.maxOf { it.date })}"
                        else -> {
                            val nextUnpaid = occ.drop(paid.size).first()
                            val d = daysBetween(today, nextUnpaid)
                            when {
                                d < 0 -> "overdue" to "Not seen yet · due ${short(nextUnpaid)}"
                                d == 0L -> "due" to "Due today"
                                d == 1L -> "due" to "Due tomorrow"
                                else -> "due" to "Due in $d days"
                            }
                        }
                    }
                    BudgetLine(s.id, s.name, s.group, s.repeat.label(), next?.toString(), acc, if (occ.isEmpty()) s.amount else due,
                        status, text, paid.sumOf { -it.amount }.coerceAtMost(due))
                }
            }
        }
        val plannedLines = lines.filter { it.status != "not_due" }
        val planned = plannedLines.sumOf { it.amount }
        val used = lines.filter { it.group != "yearly" }.sumOf { it.used }
        val income = if (month == YearMonth.from(today)) payCycleIncome() else incomeIn(month)
        return BudgetDto(
            month.toString(), planned, used, (planned - used).coerceAtLeast(0),
            if (income > 0) Math.round(planned * 100.0 / income).toInt() else null,
            lines.count { it.status == "due" || it.status == "overdue" },
            lines.sortedWith(compareBy({ listOf("bill", "yearly", "pot").indexOf(it.group) })),
        )
    }

    /** Income for the current pay cycle: everything received in the last 31 days (salary often lands just before the month starts). */
    fun payCycleIncome(): Long = l.transactions.filter {
        it.amount > 0 && kindOf(it.categoryId) == "income" && it.date.isAfter(today.minusDays(31)) && !it.date.isAfter(today)
    }.sumOf { it.amount }

    fun incomeIn(month: YearMonth) = l.transactions.filter { YearMonth.from(it.date) == month && it.amount > 0 && kindOf(it.categoryId) == "income" }.sumOf { it.amount }

    // ---------- outliers ----------

    /**
     * An outlier is money out that the ideal budget doesn't explain: not a scheduled bill, not in a
     * spending-pot category, not savings/transfers, and not waiting for a receipt split.
     */
    fun outlierTxs(month: YearMonth): List<Tx> {
        val bills = billMatches(month).keys
        val potCats = l.scheduled.filter { it.group == "pot" }.mapNotNull { it.categoryId }.toSet()
        return l.transactions.filter { t ->
            YearMonth.from(t.date) == month && t.amount < 0 && t.id !in bills && !t.awaitingReceipt &&
                l.splitsByTx[t.id].isNullOrEmpty() && kindOf(t.categoryId) == "spending" && t.categoryId !in potCats
        }
    }

    fun seenCount(t: Tx): Int {
        val m = t.merchant.lowercase()
        return l.transactions.count { it.amount < 0 && it.merchant.lowercase() == m && !it.date.isBefore(t.date.minusMonths(6)) && !it.date.isAfter(t.date) }
    }

    fun outliers(monthsBack: Int = 3): OutliersDto {
        val cur = YearMonth.from(today)
        val months = (0..monthsBack).map { cur.minusMonths(it.toLong()) }
        val list = months.map { m ->
            val items = outlierTxs(m).map { t ->
                val seen = seenCount(t)
                OutlierDto(txDto(t, setOf(t.id)), t.categoryId?.let { l.catById[it]?.name },
                    if (t.outlierDecision == null && seen >= 3) "needs_decision" else "one_off", seen)
            }
            OutlierMonth(m.toString(), items.sumOf { -it.transaction.amount }, items)
        }
        val prev = list.drop(1).take(3)
        val avg = if (prev.isEmpty()) 0 else prev.sumOf { it.total } / prev.size
        return OutliersDto(list, avg, list.first().items.count { it.state == "needs_decision" })
    }

    // ---------- savings goal ----------

    /** Money saved in a month: net change of accounts marked "counts towards savings"; failing that, transfers categorised as Savings. */
    fun savedIn(month: YearMonth): Long {
        val savingsAccounts = l.accounts.filter { it.countsTowardsSavings }.map { it.id }.toSet()
        val inMonth = l.transactions.filter { YearMonth.from(it.date) == month }
        return if (savingsAccounts.isNotEmpty()) inMonth.filter { it.accountId in savingsAccounts }.sumOf { it.amount }
        else -inMonth.filter { kindOf(it.categoryId) == "savings" }.sumOf { it.amount }
    }

    fun goal(): GoalDto? {
        val g = l.goal ?: return null
        val start = YearMonth.from(g.startDate)
        val cur = YearMonth.from(today)
        val targetDate = g.targetDate ?: LocalDate.of(today.year, 12, 31).let { if (it < g.startDate) it.plusYears(1) else it }
        val months = generateSequence(start) { it.plusMonths(1) }.takeWhile { it <= cur }.map { m ->
            val s = savedIn(m)
            GoalMonth(m.toString(), s, s >= g.monthlyAmount, m == cur)
        }.toList()
        val saved = months.sumOf { it.saved }
        val fullMonths = months.count { !it.inProgress }
        val fraction = if (cur >= start) today.dayOfMonth.toDouble() / cur.lengthOfMonth() else 0.0
        val expected = Math.round(g.monthlyAmount * (fullMonths + fraction))
        val totalMonths = java.time.temporal.ChronoUnit.MONTHS.between(start, YearMonth.from(targetDate)).toInt() + 1
        val target = g.monthlyAmount * totalMonths
        val behind = (expected - saved).coerceAtLeast(0)
        val monthsLeft = (java.time.temporal.ChronoUnit.MONTHS.between(cur, YearMonth.from(targetDate)).toInt() + 1).coerceAtLeast(1)
        val pct = if (expected > 0) saved * 100.0 / expected else 100.0
        val status = when { pct >= 100 -> "ahead"; pct >= 97 -> "on_track"; else -> "behind" }
        return GoalDto(
            g.monthlyAmount, g.startDate.toString(), targetDate.toString(), target, saved, expected,
            Math.round(pct * 10) / 10.0, status, behind,
            // Round the catch-up up to whole pounds so the advice is easy to act on.
            (ceil(behind.toDouble() / monthsLeft / 100.0) * 100).toLong(), months,
        )
    }

    // ---------- overview ----------

    fun overview(): OverviewDto {
        val cur = YearMonth.from(today)
        val budget = budget(cur)
        val out = outlierTxs(cur)
        val outAll = outliers()
        val accs = accounts()
        val goal = goal()
        val income = payCycleIncome()
        val outTotal = out.sumOf { -it.amount }
        val upcoming = l.scheduled.filter { it.group == "bill" }.flatMap { s ->
            s.repeat.occurrences(today.plusDays(7)).filter { !it.isBefore(today) }.map { d -> s to d }
        }.filter { (s, d) ->
            // Drop occurrences already paid this month.
            !(YearMonth.from(d) == cur && budget.lines.firstOrNull { it.scheduledId == s.id }?.status == "paid")
        }.sortedBy { it.second }.map { (s, d) -> ComingUp(s.name, d.toString(), s.accountId?.let { l.accById[it]?.name }, s.amount) }
        return OverviewDto(
            today.toString(), goal, income,
            l.transactions.firstOrNull { it.amount > 0 && kindOf(it.categoryId) == "income" }?.date?.toString(),
            budget.planned, budget.used, budget.billsToCome,
            outTotal, out.size, outAll.threeMonthAverage,
            income - budget.planned - (goal?.monthlyAmount ?: 0) - outTotal,
            accs, accs.sumOf { it.balance }, upcoming,
            out.take(3).map { txDto(it, setOf(it.id)) },
        )
    }

    // ---------- rules ----------

    fun preview(conds: List<app.longview.domain.Condition>): MatchPreview {
        val hits = l.transactions.filter { RuleEngine.matches(conds, l.facts(it)) }
        return MatchPreview(hits.size, hits.sumOf { abs(it.amount) }, hits.firstOrNull()?.let { txDto(it) })
    }

    fun rule(r: Rule) = RuleDto(r.id, r.name, r.active, r.categoryId, r.splitByReceipt, r.applyPast, r.conditions,
        RuleEngine.describe(r.conditions), preview(r.conditions))

    fun forwardingAddress(token: String) = "$token@$receiptsDomain"
}
