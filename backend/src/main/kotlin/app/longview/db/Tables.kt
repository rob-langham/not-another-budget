package app.longview.db

import org.jetbrains.exposed.dao.id.LongIdTable

/** All money is stored as a signed Long in pence. Negative = money out. Dates are ISO-8601 text (yyyy-MM-dd). */

object Users : LongIdTable("users") {
    /** Who the user is. "local" while there is no sign-in. */
    val auth0Sub = varchar("auth0_sub", 200).uniqueIndex()
    val email = varchar("email", 320).nullable()
    val name = varchar("name", 200).nullable()
    val receiptToken = varchar("receipt_token", 64).uniqueIndex()
    val createdAt = varchar("created_at", 40)
}

object Accounts : LongIdTable("accounts") {
    val userId = reference("user_id", Users)
    val name = varchar("name", 200)
    /** current | savings | credit_card | cash | loan | investment */
    val type = varchar("type", 30)
    /** bank_link | file_import | manual */
    val sourceKind = varchar("source", 30)
    /** automatic | website | social | upload | letter */
    val logoMode = varchar("logo_mode", 20).default("automatic")
    val logoWebsite = varchar("logo_website", 300).nullable()
    val logoSocial = varchar("logo_social", 300).nullable()
    val logoContentType = varchar("logo_content_type", 100).nullable()
    val logoImage = blob("logo_image").nullable()
    val logoColor = varchar("logo_color", 10).default("#4A4E55")
    val openingBalance = long("opening_balance").default(0)
    val openingDate = varchar("opening_date", 10)
    val countsTowardsSavings = bool("counts_towards_savings").default(false)
    val lastSyncedAt = varchar("last_synced_at", 40).nullable()
}

object Categories : LongIdTable("categories") {
    val userId = reference("user_id", Users)
    val name = varchar("name", 100)
    val color = varchar("color", 10)
    /** spending | income | savings | transfer */
    val kind = varchar("kind", 20).default("spending")
    val sortOrder = integer("sort_order").default(0)
}

object Rules : LongIdTable("rules") {
    val userId = reference("user_id", Users)
    val name = varchar("name", 200)
    val active = bool("active").default(true)
    val categoryId = reference("category_id", Categories).nullable()
    val splitByReceipt = bool("split_by_receipt").default(false)
    val applyPast = bool("apply_past").default(true)
    /** JSON array of [app.longview.domain.Condition] */
    val conditions = text("conditions")
    val priority = integer("priority").default(0)
}

object Transactions : LongIdTable("transactions") {
    val userId = reference("user_id", Users)
    val accountId = reference("account_id", Accounts)
    val date = varchar("date", 10).index()
    val time = varchar("time", 5).nullable()
    val merchant = varchar("merchant", 300)
    val description = varchar("description", 500)
    val amount = long("amount")
    val categoryId = reference("category_id", Categories).nullable()
    val ruleId = reference("rule_id", Rules).nullable()
    /** true when the user chose the category by hand; rules never overwrite it */
    val manualCategory = bool("manual_category").default(false)
    val awaitingReceipt = bool("awaiting_receipt").default(false)
    val reference = varchar("reference", 200).nullable()
    val notes = varchar("notes", 1000).nullable()
    val bankCategory = varchar("bank_category", 200).nullable()
    /** null = undecided, "one_off" = user kept it as a one-off */
    val outlierDecision = varchar("outlier_decision", 20).nullable()
}

object TransactionSplits : LongIdTable("transaction_splits") {
    val transactionId = reference("transaction_id", Transactions)
    val name = varchar("name", 300)
    val amount = long("amount")
    val categoryId = reference("category_id", Categories).nullable()
}

object ScheduledExpenses : LongIdTable("scheduled_expenses") {
    val userId = reference("user_id", Users)
    val name = varchar("name", 200)
    /** Always positive pence */
    val amount = long("amount")
    val categoryId = reference("category_id", Categories).nullable()
    /** bill | yearly | pot */
    val group = varchar("group_kind", 20)
    /** weekly | four_weekly | monthly | yearly | one_off */
    val repeat = varchar("repeat", 20)
    val firstDate = varchar("first_date", 10)
    /** never | on_date | after_count */
    val endType = varchar("end_type", 20).default("never")
    val endDate = varchar("end_date", 10).nullable()
    val endCount = integer("end_count").nullable()
    val accountId = reference("account_id", Accounts).nullable()
    /** Text that a payment's merchant/description must contain to tick this off. Defaults to name. */
    val matchText = varchar("match_text", 200).nullable()
}

object BalanceOverrides : LongIdTable("balance_overrides") {
    val accountId = reference("account_id", Accounts)
    val date = varchar("date", 10)
    val balance = long("balance")
    val note = varchar("note", 500).nullable()
    init { uniqueIndex(accountId, date) }
}

object SavingsGoals : LongIdTable("savings_goals") {
    val userId = reference("user_id", Users).uniqueIndex()
    val monthlyAmount = long("monthly_amount")
    val startDate = varchar("start_date", 10)
    val targetDate = varchar("target_date", 10).nullable()
}

object ImportLayouts : LongIdTable("import_layouts") {
    val accountId = reference("account_id", Accounts).uniqueIndex()
    /** JSON: header -> use */
    val mapping = text("mapping")
    val dateFormat = varchar("date_format", 20)
    val signConvention = varchar("sign_convention", 20)
}

object Receipts : LongIdTable("receipts") {
    val userId = reference("user_id", Users)
    val receivedAt = varchar("received_at", 40)
    val orderDate = varchar("order_date", 10)
    val total = long("total")
    /** JSON array of ReceiptItem */
    val items = text("items")
    val transactionId = reference("transaction_id", Transactions).nullable()
    /** waiting | ready | saved */
    val status = varchar("status", 20)
}
