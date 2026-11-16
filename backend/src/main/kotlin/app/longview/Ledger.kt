package app.longview

import app.longview.db.Accounts
import app.longview.db.BalanceOverrides
import app.longview.db.Categories
import app.longview.db.Rules
import app.longview.db.SavingsGoals
import app.longview.db.ScheduledExpenses
import app.longview.db.TransactionSplits
import app.longview.db.Transactions
import app.longview.domain.Condition
import app.longview.domain.Override
import app.longview.domain.Repeat
import app.longview.domain.TxFacts
import kotlinx.serialization.json.Json
import org.jetbrains.exposed.sql.selectAll
import java.time.LocalDate
import java.time.LocalTime

val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = true }

data class Cat(val id: Long, val name: String, val color: String, val kind: String)
data class Acc(
    val id: Long, val name: String, val type: String, val source: String,
    val openingBalance: Long, val openingDate: LocalDate, val countsTowardsSavings: Boolean,
    val logoMode: String, val logoWebsite: String?, val logoSocial: String?, val hasUpload: Boolean,
    val logoColor: String, val lastSyncedAt: String?,
)
data class Split(val id: Long, val txId: Long, val name: String, val amount: Long, val categoryId: Long?)
data class Tx(
    val id: Long, val accountId: Long, val date: LocalDate, val time: LocalTime?, val merchant: String,
    val description: String, val amount: Long, val categoryId: Long?, val ruleId: Long?, val manualCategory: Boolean,
    val awaitingReceipt: Boolean, val reference: String?, val notes: String?, val outlierDecision: String?,
)
data class Rule(
    val id: Long, val name: String, val active: Boolean, val categoryId: Long?, val splitByReceipt: Boolean,
    val applyPast: Boolean, val conditions: List<Condition>, val priority: Int,
)
data class Sched(
    val id: Long, val name: String, val amount: Long, val categoryId: Long?, val group: String,
    val repeat: Repeat, val accountId: Long?, val matchText: String?,
) {
    val needle: String get() = (matchText?.takeIf { it.isNotBlank() } ?: name).lowercase()
}
data class Goal(val monthlyAmount: Long, val startDate: LocalDate, val targetDate: LocalDate?)

/** Everything one user owns, loaded in one go. Personal-finance volumes are small enough that this is fast and keeps the maths pure. */
class Ledger(
    val categories: List<Cat>,
    val accounts: List<Acc>,
    val transactions: List<Tx>,
    val splits: List<Split>,
    val rules: List<Rule>,
    val scheduled: List<Sched>,
    val overrides: Map<Long, List<Override>>,
    val goal: Goal?,
) {
    val catById = categories.associateBy { it.id }
    val accById = accounts.associateBy { it.id }
    val splitsByTx = splits.groupBy { it.txId }
    val ruleById = rules.associateBy { it.id }

    fun facts(t: Tx) = TxFacts(t.merchant, t.description, t.amount, t.date, t.time, accById[t.accountId]?.name ?: "")

    companion object {
        /** Must be called inside a DB transaction. */
        fun load(userId: Long): Ledger {
            val cats = Categories.selectAll().where { Categories.userId eq userId }
                .orderBy(Categories.sortOrder to org.jetbrains.exposed.sql.SortOrder.ASC, Categories.id to org.jetbrains.exposed.sql.SortOrder.ASC)
                .map { Cat(it[Categories.id].value, it[Categories.name], it[Categories.color], it[Categories.kind]) }
            val accs = Accounts.selectAll().where { Accounts.userId eq userId }.orderBy(Accounts.id).map {
                Acc(
                    it[Accounts.id].value, it[Accounts.name], it[Accounts.type], it[Accounts.sourceKind],
                    it[Accounts.openingBalance], LocalDate.parse(it[Accounts.openingDate]), it[Accounts.countsTowardsSavings],
                    it[Accounts.logoMode], it[Accounts.logoWebsite], it[Accounts.logoSocial], it[Accounts.logoContentType] != null,
                    it[Accounts.logoColor], it[Accounts.lastSyncedAt],
                )
            }
            val txs = Transactions.selectAll().where { Transactions.userId eq userId }.map {
                Tx(
                    it[Transactions.id].value, it[Transactions.accountId].value, LocalDate.parse(it[Transactions.date]),
                    it[Transactions.time]?.let { t -> LocalTime.parse(t) }, it[Transactions.merchant], it[Transactions.description],
                    it[Transactions.amount], it[Transactions.categoryId]?.value, it[Transactions.ruleId]?.value,
                    it[Transactions.manualCategory], it[Transactions.awaitingReceipt], it[Transactions.reference],
                    it[Transactions.notes], it[Transactions.outlierDecision],
                )
            }.sortedWith(compareByDescending<Tx> { it.date }.thenByDescending { it.time }.thenByDescending { it.id })
            val txIds = txs.map { it.id }.toSet()
            val splits = if (txIds.isEmpty()) emptyList() else
                (TransactionSplits innerJoin Transactions).selectAll().where { Transactions.userId eq userId }.map {
                    Split(it[TransactionSplits.id].value, it[TransactionSplits.transactionId].value, it[TransactionSplits.name], it[TransactionSplits.amount], it[TransactionSplits.categoryId]?.value)
                }
            val rules = Rules.selectAll().where { Rules.userId eq userId }.map {
                Rule(
                    it[Rules.id].value, it[Rules.name], it[Rules.active], it[Rules.categoryId]?.value, it[Rules.splitByReceipt],
                    it[Rules.applyPast], json.decodeFromString(it[Rules.conditions]), it[Rules.priority],
                )
            }.sortedWith(compareBy<Rule> { it.priority }.thenBy { it.id })
            val sched = ScheduledExpenses.selectAll().where { ScheduledExpenses.userId eq userId }.orderBy(ScheduledExpenses.id).map {
                Sched(
                    it[ScheduledExpenses.id].value, it[ScheduledExpenses.name], it[ScheduledExpenses.amount],
                    it[ScheduledExpenses.categoryId]?.value, it[ScheduledExpenses.group],
                    Repeat(
                        it[ScheduledExpenses.repeat], LocalDate.parse(it[ScheduledExpenses.firstDate]), it[ScheduledExpenses.endType],
                        it[ScheduledExpenses.endDate]?.let(LocalDate::parse), it[ScheduledExpenses.endCount],
                    ),
                    it[ScheduledExpenses.accountId]?.value, it[ScheduledExpenses.matchText],
                )
            }
            val accIds = accs.map { it.id }
            val ov = if (accIds.isEmpty()) emptyMap() else
                BalanceOverrides.selectAll().where { BalanceOverrides.accountId inList accIds }.map {
                    it[BalanceOverrides.accountId].value to Override(LocalDate.parse(it[BalanceOverrides.date]), it[BalanceOverrides.balance], it[BalanceOverrides.note])
                }.groupBy({ it.first }, { it.second })
            val goal = SavingsGoals.selectAll().where { SavingsGoals.userId eq userId }.singleOrNull()?.let {
                Goal(it[SavingsGoals.monthlyAmount], LocalDate.parse(it[SavingsGoals.startDate]), it[SavingsGoals.targetDate]?.let(LocalDate::parse))
            }
            return Ledger(cats, accs, txs, splits, rules, sched, ov, goal)
        }
    }
}
