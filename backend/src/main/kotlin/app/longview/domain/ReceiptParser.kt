package app.longview.domain

import kotlinx.serialization.Serializable
import java.time.LocalDate

@Serializable
data class ReceiptItem(
    val name: String,
    val qty: Int = 1,
    /** pence */
    val amount: Long,
    val categoryId: Long? = null,
)

data class ParsedReceipt(val orderDate: LocalDate?, val total: Long?, val items: List<ReceiptItem>)

/**
 * Pulls items and the order total out of the plain text of an Amazon order-confirmation email.
 * Amazon changes its email layout often, so this is deliberately forgiving: any line ending in a
 * price is an item unless it looks like a subtotal/total/delivery line.
 */
object ReceiptParser {
    private val price = Regex("""£\s?(\d{1,3}(?:,\d{3})*(?:\.\d{2}))""")
    private val qtyRe = Regex("""(?i)\b(?:qty|quantity)[:\s]*(\d+)""")
    private val totalWords = listOf("order total", "grand total", "total for this order", "total:", "total ")
    private val skipWords = listOf("subtotal", "sub-total", "vat", "promotion", "discount", "item(s) subtotal", "total before")
    private val deliveryWords = listOf("delivery", "postage", "shipping")

    fun parse(text: String, fallbackDate: LocalDate): ParsedReceipt {
        val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
        var total: Long? = null
        val items = ArrayList<ReceiptItem>()
        var pendingName: String? = null
        var pendingQty = 1
        for (line in lines) {
            val lower = line.lowercase()
            val m = price.findAll(line).lastOrNull()
            if (m == null) {
                qtyRe.find(line)?.let { pendingQty = it.groupValues[1].toInt() }
                if (line.length in 3..140 && !lower.startsWith("order") && !lower.contains("@") && !lower.startsWith("qty")) {
                    pendingName = line
                }
                continue
            }
            val amt = Money.parse(m.groupValues[1]) ?: continue
            when {
                skipWords.any { lower.contains(it) } -> {}
                totalWords.any { lower.contains(it) } -> total = amt
                deliveryWords.any { lower.contains(it) } -> if (amt > 0) items += ReceiptItem("Delivery", 1, amt)
                else -> {
                    val before = line.substring(0, m.range.first).replace(qtyRe, "").trim().trimEnd(':', '-', '–').trim()
                    val name = before.ifBlank { pendingName ?: "Item" }
                    val q = qtyRe.find(line)?.groupValues?.get(1)?.toInt() ?: pendingQty
                    items += ReceiptItem(name, q, amt)
                    pendingName = null; pendingQty = 1
                }
            }
        }
        val date = findDate(text) ?: fallbackDate
        return ParsedReceipt(date, total ?: items.sumOf { it.amount }.takeIf { items.isNotEmpty() }, items)
    }

    private val longDate = Regex("""(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})""", RegexOption.IGNORE_CASE)

    private fun findDate(text: String): LocalDate? {
        val m = longDate.find(text) ?: return null
        val month = java.time.Month.valueOf(m.groupValues[2].uppercase())
        return runCatching { LocalDate.of(m.groupValues[3].toInt(), month, m.groupValues[1].toInt()) }.getOrNull()
    }
}
