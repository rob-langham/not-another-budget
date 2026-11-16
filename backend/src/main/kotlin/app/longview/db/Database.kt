package app.longview.db

import org.jetbrains.exposed.sql.Database
import org.jetbrains.exposed.sql.SchemaUtils
import org.jetbrains.exposed.sql.Transaction
import org.jetbrains.exposed.sql.batchInsert
import org.jetbrains.exposed.sql.transactions.TransactionManager
import org.jetbrains.exposed.sql.transactions.transaction
import java.io.File
import java.sql.Connection

object Db {
    lateinit var database: Database
        private set

    fun init(path: String) {
        if (path != ":memory:") File(path).absoluteFile.parentFile?.mkdirs()
        // Shared-cache in-memory DB for tests; the keep-alive connection stops it vanishing between transactions.
        val url = if (path == ":memory:") "jdbc:sqlite:file:longview_test?mode=memory&cache=shared" else "jdbc:sqlite:$path"
        if (path == ":memory:") keepAlive = java.sql.DriverManager.getConnection(url)
        database = Database.connect(url, driver = "org.sqlite.JDBC", setupConnection = { conn ->
            conn.createStatement().use { st ->
                st.execute("PRAGMA foreign_keys = ON")
                st.execute("PRAGMA busy_timeout = 5000")
                if (path != ":memory:") st.execute("PRAGMA journal_mode = WAL")
            }
        })
        TransactionManager.manager.defaultIsolationLevel = Connection.TRANSACTION_SERIALIZABLE
        transaction(database) {
            SchemaUtils.create(
                Users, Accounts, Categories, Rules, Transactions, TransactionSplits,
                ScheduledExpenses, BalanceOverrides, SavingsGoals, ImportLayouts, Receipts,
            )
        }
    }

    private var keepAlive: Connection? = null
}

fun <T> tx(block: Transaction.() -> T): T = transaction(Db.database) { block() }

/** Categories every new user starts with. They can rename, recolour or delete them. */
val DEFAULT_CATEGORIES = listOf(
    Triple("Bills", "#7A4FB0", "spending"),
    Triple("Groceries", "#2F5BB7", "spending"),
    Triple("Lunch", "#1E6B4F", "spending"),
    Triple("Transport", "#B4530A", "spending"),
    Triple("Health & fitness", "#2A8A8A", "spending"),
    Triple("Household", "#6B6F76", "spending"),
    Triple("Pets", "#8C5A2B", "spending"),
    Triple("Travel", "#5A6ACF", "spending"),
    Triple("Gifts", "#C23B5A", "spending"),
    Triple("Tech", "#9C4FA8", "spending"),
    Triple("Savings", "#16181D", "savings"),
    Triple("Income", "#A07A1E", "income"),
    Triple("Card repayment", "#4A4E55", "transfer"),
)

fun seedCategories(userId: Long) {
    Categories.batchInsert(DEFAULT_CATEGORIES.withIndex()) { (i, c) ->
        this[Categories.userId] = userId
        this[Categories.name] = c.first
        this[Categories.color] = c.second
        this[Categories.kind] = c.third
        this[Categories.sortOrder] = i
    }
}
