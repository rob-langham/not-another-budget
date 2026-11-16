package app.longview.domain

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter

/** What a file column is used as. */
object Use {
    const val DATE = "date"
    const val TIME = "time"
    const val DESCRIPTION = "description"
    const val MERCHANT = "merchant"
    const val AMOUNT = "amount"
    const val MONEY_OUT = "money_out"
    const val MONEY_IN = "money_in"
    const val BALANCE = "balance"
    const val REFERENCE = "reference"
    const val NOTES = "notes"
    const val BANK_CATEGORY = "bank_category"
    const val SKIP = "skip"
    val ALL = listOf(DATE, TIME, DESCRIPTION, MERCHANT, AMOUNT, MONEY_OUT, MONEY_IN, BALANCE, REFERENCE, NOTES, BANK_CATEGORY, SKIP)
}

@Serializable
data class ColumnMatch(
    val column: String,
    val use: String,
    /** name | saved_layout | unique_values | unsure */
    val reason: String,
    val confident: Boolean,
)

data class ParsedRow(
    val date: LocalDate,
    val time: LocalTime?,
    val merchant: String,
    val description: String,
    val amount: Long,
    val reference: String?,
    val notes: String?,
    val bankCategory: String?,
)

object CsvImport {
    /** RFC-4180-ish parser: quotes, escaped quotes, commas/semicolons/tabs, CRLF. */
    fun parse(text: String): List<List<String>> {
        val clean = text.removePrefix("﻿")
        val firstLine = clean.lineSequence().firstOrNull().orEmpty()
        val sep = listOf(',', ';', '\t').maxBy { c -> firstLine.count { it == c } }
        val rows = ArrayList<List<String>>()
        var row = ArrayList<String>()
        val cell = StringBuilder()
        var inQuotes = false
        var i = 0
        while (i < clean.length) {
            val ch = clean[i]
            if (inQuotes) {
                if (ch == '"') {
                    if (i + 1 < clean.length && clean[i + 1] == '"') { cell.append('"'); i++ } else inQuotes = false
                } else cell.append(ch)
            } else when (ch) {
                '"' -> inQuotes = true
                sep -> { row += cell.toString().trim(); cell.clear() }
                '\r' -> {}
                '\n' -> { row += cell.toString().trim(); cell.clear(); if (row.any { it.isNotEmpty() }) rows += row; row = ArrayList() }
                else -> cell.append(ch)
            }
            i++
        }
        if (cell.isNotEmpty() || row.isNotEmpty()) { row += cell.toString().trim(); if (row.any { it.isNotEmpty() }) rows += row }
        return rows
    }

    private val SYNONYMS: List<Pair<String, List<String>>> = listOf(
        Use.DATE to listOf("date", "transaction date", "posted date", "posting date", "booking date", "value date", "completed date"),
        Use.TIME to listOf("time", "transaction time"),
        Use.MONEY_OUT to listOf("paid out", "money out", "debit", "debits", "withdrawals", "out", "debit amount"),
        Use.MONEY_IN to listOf("paid in", "money in", "credit", "credits", "deposits", "in", "credit amount"),
        Use.AMOUNT to listOf("amount", "value", "transaction amount", "amount (gbp)", "amount gbp", "sum"),
        Use.BALANCE to listOf("balance", "running balance", "balance (gbp)"),
        Use.MERCHANT to listOf("merchant", "name", "payee", "counterparty", "appears on your statement as", "merchant name"),
        Use.DESCRIPTION to listOf("description", "details", "narrative", "transaction description", "memo", "transaction details"),
        Use.REFERENCE to listOf("reference", "transaction id", "id", "ref", "fitid"),
        Use.BANK_CATEGORY to listOf("category", "type", "transaction type"),
        Use.NOTES to listOf("notes", "extended details", "note"),
    )

    /**
     * Matches each header to a use. A saved layout wins; then exact names; then "contains" names.
     * Columns we can't place are suggested as [Use.SKIP] and flagged unsure.
     */
    fun suggest(headers: List<String>, rows: List<List<String>>, saved: Map<String, String>?): List<ColumnMatch> {
        val taken = HashSet<String>()
        val result = arrayOfNulls<ColumnMatch>(headers.size)
        val singleUse = setOf(Use.DATE, Use.TIME, Use.AMOUNT, Use.MONEY_IN, Use.MONEY_OUT, Use.BALANCE, Use.MERCHANT, Use.DESCRIPTION, Use.REFERENCE)
        fun take(i: Int, use: String, reason: String, confident: Boolean = true) {
            result[i] = ColumnMatch(headers[i], use, reason, confident)
            if (use in singleUse) taken += use
        }
        headers.forEachIndexed { i, h -> saved?.get(h)?.let { take(i, it, "saved_layout") } }
        for (pass in 0..1) headers.forEachIndexed { i, h ->
            if (result[i] != null) return@forEachIndexed
            val n = h.lowercase().trim()
            for ((use, names) in SYNONYMS) {
                if (use in taken) continue
                val hit = if (pass == 0) n in names else names.any { it.length > 3 && n.contains(it) }
                if (hit) { take(i, use, "name"); break }
            }
        }
        headers.forEachIndexed { i, h ->
            if (result[i] != null) return@forEachIndexed
            val values = rows.mapNotNull { it.getOrNull(i) }.filter { it.isNotBlank() }
            if (Use.REFERENCE !in taken && values.size >= 2 && values.toSet().size == values.size && values.all { v -> v.any(Char::isDigit) && Money.parse(v) == null }) {
                take(i, Use.REFERENCE, "unique_values")
            } else {
                take(i, Use.SKIP, "unsure", confident = false)
            }
        }
        return result.map { it!! }
    }

    private val DATE_FORMATS = mapOf(
        "dmy" to listOf("d/M/yyyy", "d-M-yyyy", "d.M.yyyy", "d/M/yy", "d MMM yyyy", "d-MMM-yyyy", "d MMM yy"),
        "mdy" to listOf("M/d/yyyy", "M-d-yyyy", "M/d/yy"),
        "ymd" to listOf("yyyy-M-d", "yyyy/M/d", "yyyyMMdd"),
    )

    /** Picks the date order that parses every sample; prefers day-first (UK) when ambiguous. */
    fun detectDateFormat(samples: List<String>): String {
        val s = samples.map { it.take(10).trim() }.filter { it.isNotEmpty() }
        for (fmt in listOf("ymd", "dmy", "mdy")) {
            if (s.isNotEmpty() && s.all { parseDate(it, fmt) != null }) return fmt
        }
        return "dmy"
    }

    fun parseDate(text: String, format: String): LocalDate? {
        val t = text.trim().substringBefore('T').substringBefore(' ').let { if (it.length < 6) text.trim() else it }
        val candidates = listOf(t, text.trim())
        for (c in candidates) for (p in DATE_FORMATS[format].orEmpty()) {
            try { return LocalDate.parse(c, DateTimeFormatter.ofPattern(p, java.util.Locale.UK)) } catch (_: Exception) {}
        }
        return null
    }

    /**
     * For a single amount column, decides whether positive means money out (credit cards, e.g. Amex) or money in.
     * A card repayment ("PAYMENT RECEIVED") shown as negative means positive = out; otherwise we go by the account type.
     */
    fun detectSign(amounts: List<Long>, descriptions: List<String>, accountType: String? = null): String {
        val paymentWords = listOf("payment received", "thank you", "refund", "salary")
        val paymentIdx = descriptions.indices.filter { i -> paymentWords.any { descriptions[i].lowercase().contains(it) } }
        if (paymentIdx.isNotEmpty()) {
            val neg = paymentIdx.count { amounts.getOrNull(it)?.let { a -> a < 0 } == true }
            if (neg * 2 > paymentIdx.size) return "positive_out"
            return "positive_in"
        }
        // No payment lines to go on: card statements list purchases as positive, bank accounts list deposits as positive.
        return if (accountType == "credit_card") "positive_out" else "positive_in"
    }

    fun toRows(rows: List<List<String>>, mapping: List<ColumnMatch>, dateFormat: String, sign: String): Pair<List<ParsedRow>, List<String>> {
        val idx = mapping.withIndex().associate { (i, m) -> i to m.use }
        fun col(row: List<String>, use: String) = idx.entries.firstOrNull { it.value == use }?.let { row.getOrNull(it.key) }?.takeIf { it.isNotBlank() }
        val errors = ArrayList<String>()
        val parsed = rows.mapIndexedNotNull { n, r ->
            val rawDate = col(r, Use.DATE)
            val date = rawDate?.let { parseDate(it, dateFormat) }
            if (date == null) { errors += "Row ${n + 1}: can't read the date “${rawDate ?: ""}”"; return@mapIndexedNotNull null }
            val amount: Long? = col(r, Use.AMOUNT)?.let { Money.parse(it) }?.let { if (sign == "positive_out") -it else it }
                ?: run {
                    val out = Money.parse(col(r, Use.MONEY_OUT))
                    val inn = Money.parse(col(r, Use.MONEY_IN))
                    if (out == null && inn == null) null else (inn?.let { kotlin.math.abs(it) } ?: 0) - (out?.let { kotlin.math.abs(it) } ?: 0)
                }
            if (amount == null) { errors += "Row ${n + 1}: no amount"; return@mapIndexedNotNull null }
            val time = col(r, Use.TIME)?.let { runCatching { LocalTime.parse(it.take(5).padStart(5, '0')) }.getOrNull() }
                ?: rawDate.substringAfter(' ', "").takeIf { it.length >= 4 }?.let { runCatching { LocalTime.parse(it.take(5).padStart(5, '0')) }.getOrNull() }
            val description = col(r, Use.DESCRIPTION) ?: col(r, Use.MERCHANT) ?: ""
            val merchant = col(r, Use.MERCHANT)?.let(::tidyMerchant) ?: tidyMerchant(description)
            ParsedRow(date, time, merchant, description, amount, col(r, Use.REFERENCE), col(r, Use.NOTES), col(r, Use.BANK_CATEGORY))
        }
        return parsed to errors
    }

    /** "AMAZON.CO.UK*AB12C" -> "Amazon", "TESCO STORES 3021" -> "Tesco Stores". */
    fun tidyMerchant(raw: String): String {
        var s = raw.substringBefore('*').trim()
        s = s.replace(Regex("""\s+\d{3,}.*$"""), "")
        s = s.replace(Regex("""\.(co\.uk|com|uk)$""", RegexOption.IGNORE_CASE), "")
        if (s.isBlank()) s = raw.trim()
        // Only reformat SHOUTY bank text; leave names that already have mixed case alone.
        if (s.any { it.isLowerCase() }) return s
        return s.lowercase().split(Regex("\\s+")).joinToString(" ") { it.replaceFirstChar(Char::uppercase) }
    }
}
