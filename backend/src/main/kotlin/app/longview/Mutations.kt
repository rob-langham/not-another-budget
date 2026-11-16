package app.longview

import app.longview.db.ImportLayouts
import app.longview.db.Receipts
import app.longview.db.TransactionSplits
import app.longview.db.Transactions
import app.longview.domain.ColumnMatch
import app.longview.domain.CsvImport
import app.longview.domain.ParsedRow
import app.longview.domain.ReceiptItem
import app.longview.domain.RuleEngine
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.batchInsert
import org.jetbrains.exposed.sql.deleteWhere
import org.jetbrains.exposed.sql.insertAndGetId
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.update
import org.jetbrains.exposed.sql.upsert
import java.time.LocalDate
import kotlin.math.abs

class BadRequest(message: String) : RuntimeException(message)
class NotFound(message: String = "Not found") : RuntimeException(message)

/** All writes. Each function must run inside a DB transaction. */
object Mutations {

    /**
     * Runs the rules over transactions. Hand-picked categories are never touched.
     * [onlyIds] limits it to some transactions (e.g. a fresh import); null means everything.
     */
    fun applyRules(userId: Long, onlyIds: Set<Long>? = null): Int {
        val l = Ledger.load(userId)
        val active = l.rules.filter { it.active }
        val pastRules = active.filter { it.applyPast }
        var changed = 0
        for (t in l.transactions) {
            if (t.manualCategory) continue
            val isNew = onlyIds != null && t.id in onlyIds
            if (onlyIds != null && !isNew) continue
            val candidates = if (isNew) active else pastRules
            val hit = candidates.firstOrNull { RuleEngine.matches(it.conditions, l.facts(t)) }
            if (hit == null) {
                // Keep a category set earlier by a rule that still applies (e.g. one not run over past payments);
                // let go of it if that rule was deleted, switched off or no longer matches.
                val prev = t.ruleId?.let { l.ruleById[it] }
                val stillHolds = prev != null && prev.active && RuleEngine.matches(prev.conditions, l.facts(t))
                if (onlyIds == null && t.ruleId != null && !stillHolds) {
                    Transactions.update({ Transactions.id eq t.id }) { it[categoryId] = null; it[ruleId] = null; it[awaitingReceipt] = false }
                    changed++
                }
                continue
            }
            val hasSplit = !l.splitsByTx[t.id].isNullOrEmpty()
            val wantCat = if (hit.splitByReceipt) null else hit.categoryId
            val wantAwait = hit.splitByReceipt && !hasSplit
            if (t.ruleId != hit.id || t.categoryId != wantCat || t.awaitingReceipt != wantAwait) {
                Transactions.update({ Transactions.id eq t.id }) {
                    it[ruleId] = hit.id; it[categoryId] = wantCat; it[awaitingReceipt] = wantAwait
                }
                changed++
            }
        }
        return changed
    }

    private fun dedupeKey(accountId: Long, date: LocalDate, amount: Long, description: String) =
        "$accountId|$date|$amount|${description.lowercase().trim()}"

    data class Classified(val row: ParsedRow, val duplicate: Boolean)

    fun classify(userId: Long, accountId: Long, rows: List<ParsedRow>): List<Classified> {
        val existing = Transactions.selectAll().where { (Transactions.userId eq userId) and (Transactions.accountId eq accountId) }.toList()
        val refs = existing.mapNotNull { it[Transactions.reference] }.toHashSet()
        val keys = existing.map { dedupeKey(accountId, LocalDate.parse(it[Transactions.date]), it[Transactions.amount], it[Transactions.description]) }.toHashSet()
        val seenInFile = HashSet<String>()
        return rows.map { r ->
            val key = r.reference?.let { "ref:$it" } ?: dedupeKey(accountId, r.date, r.amount, r.description)
            val dup = (r.reference != null && r.reference in refs) || (r.reference == null && key in keys) || !seenInFile.add(key)
            Classified(r, dup)
        }
    }

    fun commitImport(userId: Long, accountId: Long, rows: List<ParsedRow>): Pair<Int, Int> {
        val classified = classify(userId, accountId, rows)
        val fresh = classified.filter { !it.duplicate }.map { it.row }
        val ids = fresh.map { r ->
            Transactions.insertAndGetId {
                it[Transactions.userId] = userId
                it[Transactions.accountId] = accountId
                it[date] = r.date.toString()
                it[time] = r.time?.toString()
                it[merchant] = r.merchant.take(300)
                it[description] = r.description.take(500)
                it[amount] = r.amount
                it[reference] = r.reference?.take(200)
                it[notes] = r.notes?.take(1000)
                it[bankCategory] = r.bankCategory?.take(200)
            }.value
        }.toSet()
        if (ids.isNotEmpty()) applyRules(userId, ids)
        return fresh.size to (classified.size - fresh.size)
    }

    fun saveLayout(accountId: Long, mapping: List<ColumnMatch>, dateFormat: String, sign: String) {
        val m = json.encodeToString(MapSerializer(String.serializer(), String.serializer()), mapping.associate { it.column to it.use })
        ImportLayouts.upsert(ImportLayouts.accountId) {
            it[ImportLayouts.accountId] = accountId
            it[ImportLayouts.mapping] = m
            it[ImportLayouts.dateFormat] = dateFormat
            it[signConvention] = sign
        }
    }

    data class Layout(val mapping: Map<String, String>, val dateFormat: String, val sign: String)

    fun layout(accountId: Long): Layout? = ImportLayouts.selectAll().where { ImportLayouts.accountId eq accountId }.singleOrNull()?.let {
        Layout(json.decodeFromString(MapSerializer(String.serializer(), String.serializer()), it[ImportLayouts.mapping]), it[ImportLayouts.dateFormat], it[ImportLayouts.signConvention])
    }

    /** Replaces a transaction's split lines. Lines must add up to the payment exactly. */
    fun setSplits(userId: Long, txId: Long, lines: List<SplitDto>) {
        val t = Transactions.selectAll().where { (Transactions.id eq txId) and (Transactions.userId eq userId) }.singleOrNull() ?: throw NotFound()
        val total = abs(t[Transactions.amount])
        if (lines.isNotEmpty() && lines.sumOf { abs(it.amount) } != total) {
            throw BadRequest("Split lines add up to ${lines.sumOf { abs(it.amount) }}p but the payment is ${total}p.")
        }
        TransactionSplits.deleteWhere { transactionId eq txId }
        TransactionSplits.batchInsert(lines) { s ->
            this[TransactionSplits.transactionId] = txId
            this[TransactionSplits.name] = s.name.take(300)
            this[TransactionSplits.amount] = abs(s.amount)
            this[TransactionSplits.categoryId] = s.categoryId
        }
        Transactions.update({ Transactions.id eq txId }) { it[awaitingReceipt] = false }
    }

    private val itemsSer = ListSerializer(ReceiptItem.serializer())
    fun encodeItems(items: List<ReceiptItem>) = json.encodeToString(itemsSer, items)
    fun decodeItems(s: String) = json.decodeFromString(itemsSer, s)

    /** Finds the card payment for each unmatched receipt: an Amazon payment of the same total, 0–14 days after the order. */
    fun matchReceipts(userId: Long): Int {
        val l = Ledger.load(userId)
        val taken = Receipts.selectAll().where { Receipts.userId eq userId }.mapNotNull { it[Receipts.transactionId]?.value }.toMutableSet()
        var matched = 0
        Receipts.selectAll().where { (Receipts.userId eq userId) and (Receipts.status eq "waiting") }.toList().forEach { r ->
            val order = LocalDate.parse(r[Receipts.orderDate])
            val total = r[Receipts.total]
            val tx = l.transactions.filter { t ->
                t.amount == -total && t.id !in taken && !t.date.isBefore(order.minusDays(1)) && !t.date.isAfter(order.plusDays(14)) &&
                    (t.merchant + " " + t.description).lowercase().contains("amazon") && l.splitsByTx[t.id].isNullOrEmpty()
            }.minByOrNull { abs(java.time.temporal.ChronoUnit.DAYS.between(order, it.date)) }
            if (tx != null) {
                Receipts.update({ Receipts.id eq r[Receipts.id] }) { it[transactionId] = tx.id; it[status] = "ready" }
                taken += tx.id
                matched++
            }
        }
        return matched
    }

    fun addReceipt(userId: Long, orderDate: LocalDate, total: Long, items: List<ReceiptItem>): Long {
        val id = Receipts.insertAndGetId {
            it[Receipts.userId] = userId
            it[receivedAt] = java.time.Instant.now().toString()
            it[Receipts.orderDate] = orderDate.toString()
            it[Receipts.total] = total
            it[Receipts.items] = encodeItems(items)
            it[status] = "waiting"
        }.value
        matchReceipts(userId)
        return id
    }
}
