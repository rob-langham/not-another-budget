package app.longview

import app.longview.domain.ColumnMatch
import app.longview.domain.Condition
import app.longview.domain.ReceiptItem
import kotlinx.serialization.Serializable

// All amounts are pence (Long). Negative = money out. Dates are "yyyy-MM-dd".

@Serializable data class MeDto(val id: Long, val name: String?, val email: String?, val forwardingAddress: String)

@Serializable data class CategoryDto(val id: Long, val name: String, val color: String, val kind: String)
@Serializable data class CategoryInput(val name: String, val color: String = "#6B6F76", val kind: String = "spending")

@Serializable data class AccountDto(
    val id: Long, val name: String, val type: String, val source: String,
    val balance: Long, val countsTowardsSavings: Boolean, val lastSyncedAt: String?,
    val openingBalance: Long, val openingDate: String,
    val logo: LogoDto, val lastTransactionDate: String?,
)
@Serializable data class LogoDto(
    val mode: String, val resolved: String, val url: String?, val letter: String, val color: String,
    val website: String?, val social: String?,
)
@Serializable data class AccountInput(
    val name: String, val type: String = "current", val source: String = "manual",
    val openingBalance: Long = 0, val openingDate: String? = null,
    val countsTowardsSavings: Boolean = false, val logoWebsite: String? = null,
)
@Serializable data class AccountPatch(
    val name: String? = null, val type: String? = null, val countsTowardsSavings: Boolean? = null,
    val logoMode: String? = null, val logoWebsite: String? = null, val logoSocial: String? = null, val logoColor: String? = null,
    val openingBalance: Long? = null, val openingDate: String? = null,
)
@Serializable data class DayBalanceDto(val date: String, val calculated: Long, val balance: Long, val overridden: Boolean, val note: String?)
@Serializable data class OverrideInput(val date: String, val balance: Long, val note: String? = null)

@Serializable data class SplitDto(val id: Long? = null, val name: String, val amount: Long, val categoryId: Long?)
@Serializable data class TransactionDto(
    val id: Long, val accountId: Long, val accountName: String, val date: String, val time: String?,
    val merchant: String, val description: String, val amount: Long,
    val categoryId: Long?, val ruleName: String?, val manualCategory: Boolean, val awaitingReceipt: Boolean,
    val notes: String?, val splits: List<SplitDto>, val isOutlier: Boolean, val plannedAs: String?,
)
@Serializable data class TransactionInput(
    val accountId: Long, val date: String, val time: String? = null, val merchant: String,
    val description: String? = null, val amount: Long, val categoryId: Long? = null, val notes: String? = null,
)
@Serializable data class TransactionPatch(val categoryId: Long? = null, val clearCategory: Boolean = false, val notes: String? = null)
@Serializable data class CategoryTotal(val categoryId: Long?, val name: String, val color: String, val total: Long, val count: Int, val budget: Long?)
@Serializable data class TransactionPage(
    val from: String, val to: String, val spent: Long, val moneyIn: Long, val movedToSavings: Long,
    val count: Int, val transactions: List<TransactionDto>, val byCategory: List<CategoryTotal>,
)

@Serializable data class RuleDto(
    val id: Long, val name: String, val active: Boolean, val categoryId: Long?, val splitByReceipt: Boolean,
    val applyPast: Boolean, val conditions: List<Condition>, val summary: String, val match: MatchPreview,
)
@Serializable data class RuleInput(
    val name: String, val active: Boolean = true, val categoryId: Long? = null, val splitByReceipt: Boolean = false,
    val applyPast: Boolean = true, val conditions: List<Condition>,
)
@Serializable data class MatchPreview(val count: Int, val total: Long, val latest: TransactionDto?)
@Serializable data class PreviewInput(val conditions: List<Condition>)

@Serializable data class ScheduledDto(
    val id: Long, val name: String, val amount: Long, val categoryId: Long?, val group: String, val repeat: String,
    val repeatLabel: String, val firstDate: String, val endType: String, val endDate: String?, val endCount: Int?,
    val accountId: Long?, val matchText: String?, val monthlyEquivalent: Long,
)
@Serializable data class ScheduledInput(
    val name: String, val amount: Long, val categoryId: Long? = null, val group: String = "bill",
    val repeat: String = "monthly", val firstDate: String, val endType: String = "never",
    val endDate: String? = null, val endCount: Int? = null, val accountId: Long? = null, val matchText: String? = null,
)
@Serializable data class RepeatSuggestion(val name: String, val amount: Long, val repeat: String, val firstDate: String, val seen: Int, val accountId: Long?)

@Serializable data class BudgetLine(
    val scheduledId: Long, val name: String, val group: String, val repeatLabel: String,
    val nextDue: String?, val accountName: String?, val amount: Long,
    /** paid | due | not_due | overdue | pot | set_aside */
    val status: String, val statusText: String, val used: Long, val putBy: Long? = null, val yearlyAmount: Long? = null,
)
@Serializable data class BudgetDto(
    val month: String, val planned: Long, val used: Long, val stillToCome: Long, val shareOfIncome: Int?,
    val billsToCome: Int, val lines: List<BudgetLine>,
)

@Serializable data class OutlierDto(
    val transaction: TransactionDto, val categoryName: String?,
    /** one_off | needs_decision */
    val state: String, val seenCount: Int,
)
@Serializable data class OutlierMonth(val month: String, val total: Long, val items: List<OutlierDto>)
@Serializable data class OutliersDto(val months: List<OutlierMonth>, val threeMonthAverage: Long, val needsDecision: Int)
@Serializable data class MakeRecurringInput(val repeat: String = "monthly", val group: String = "bill")

@Serializable data class GoalDto(
    val monthlyAmount: Long, val startDate: String, val targetDate: String, val target: Long,
    val saved: Long, val expected: Long, val percentOfPace: Double, val status: String,
    val behindBy: Long, val catchUpPerMonth: Long, val months: List<GoalMonth>,
)
@Serializable data class GoalMonth(val month: String, val saved: Long, val metGoal: Boolean, val inProgress: Boolean)
@Serializable data class GoalInput(val monthlyAmount: Long, val startDate: String, val targetDate: String? = null)
@Serializable data class ComingUp(val name: String, val date: String, val accountName: String?, val amount: Long)
@Serializable data class OverviewDto(
    val today: String, val goal: GoalDto?, val incomeThisMonth: Long, val lastIncomeDate: String?,
    val budgetPlanned: Long, val budgetUsed: Long, val billsToCome: Int,
    val outliersTotal: Long, val outliersCount: Int, val outliersAverage: Long,
    val leftAfterPlanAndSavings: Long, val accounts: List<AccountDto>, val netPosition: Long,
    val comingUp: List<ComingUp>, val latestOutliers: List<TransactionDto>,
)

@Serializable data class ImportParseInput(val accountId: Long, val fileName: String, val content: String)
@Serializable data class ImportPreviewRow(val date: String, val merchant: String, val categoryName: String?, val amount: Long, val duplicate: Boolean)
@Serializable data class ImportParseResult(
    val fileName: String, val headers: List<String>, val sampleRows: List<List<String>>, val totalRows: Int,
    val mapping: List<ColumnMatch>, val dateFormat: String, val dateExample: String?, val signConvention: String,
    val usedSavedLayout: Boolean, val preview: List<ImportPreviewRow>, val newRows: Int, val duplicates: Int, val errors: List<String>,
)
@Serializable data class ImportCommitInput(
    val accountId: Long, val content: String, val mapping: List<ColumnMatch>, val dateFormat: String,
    val signConvention: String, val rememberLayout: Boolean = true,
)
@Serializable data class ImportCommitResult(val imported: Int, val duplicates: Int, val errors: List<String>, val receiptsMatched: Int)

@Serializable data class ReceiptDto(
    val id: Long, val receivedAt: String, val orderDate: String, val total: Long, val items: List<ReceiptItem>,
    val status: String, val transaction: TransactionDto?,
)
@Serializable data class ReceiptInput(val text: String)
@Serializable data class SaveSplitInput(val items: List<ReceiptItem>)
@Serializable data class InboundEmail(val to: String, val text: String)

@Serializable data class ErrorDto(val error: String)
