package app.longview.domain

import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime

/**
 * One condition of a rule. Fields: merchant | description | amount | day_of_week | time | account.
 * Text ops: contains | is | starts_with | is_one_of (comma separated).
 * Amount ops: less_than | more_than | equals (compared on the size of the payment, ignoring sign).
 */
@Serializable
data class Condition(
    val field: String,
    val op: String? = null,
    val value: String? = null,
    val days: List<String>? = null,
    val from: String? = null,
    val to: String? = null,
)

/** What a rule needs to see of a transaction. */
data class TxFacts(
    val merchant: String,
    val description: String,
    val amount: Long,
    val date: LocalDate,
    val time: LocalTime?,
    val accountName: String,
)

object RuleEngine {
    private val DAY_CODES = mapOf(
        "mon" to DayOfWeek.MONDAY, "tue" to DayOfWeek.TUESDAY, "wed" to DayOfWeek.WEDNESDAY,
        "thu" to DayOfWeek.THURSDAY, "fri" to DayOfWeek.FRIDAY, "sat" to DayOfWeek.SATURDAY, "sun" to DayOfWeek.SUNDAY,
    )

    /** A rule matches when ALL of its conditions match. A rule with no conditions matches nothing. */
    fun matches(conditions: List<Condition>, t: TxFacts): Boolean =
        conditions.isNotEmpty() && conditions.all { matches(it, t) }

    fun matches(c: Condition, t: TxFacts): Boolean = when (c.field) {
        "merchant" -> text(c, t.merchant)
        "description" -> text(c, t.description)
        "account" -> text(c, t.accountName)
        "amount" -> {
            val v = Money.parse(c.value)?.let { kotlin.math.abs(it) }
            val a = kotlin.math.abs(t.amount)
            when {
                v == null -> false
                c.op == "less_than" -> a < v
                c.op == "more_than" -> a > v
                c.op == "equals" -> a == v
                else -> false
            }
        }
        "day_of_week" -> {
            val wanted = c.days.orEmpty().mapNotNull { DAY_CODES[it.take(3).lowercase()] }.toSet()
            wanted.isNotEmpty() && t.date.dayOfWeek in wanted
        }
        "time" -> {
            val from = c.from?.let { runCatching { LocalTime.parse(it) }.getOrNull() }
            val to = c.to?.let { runCatching { LocalTime.parse(it) }.getOrNull() }
            val tm = t.time
            if (tm == null || from == null || to == null) false
            else if (!from.isAfter(to)) !tm.isBefore(from) && !tm.isAfter(to)
            else !tm.isBefore(from) || !tm.isAfter(to) // window crosses midnight
        }
        else -> false
    }

    private fun text(c: Condition, subject: String): Boolean {
        val s = subject.lowercase().trim()
        val v = c.value?.lowercase()?.trim().orEmpty()
        if (v.isEmpty()) return false
        return when (c.op ?: "contains") {
            "contains" -> s.contains(v)
            "is" -> s == v
            "starts_with" -> s.startsWith(v)
            "is_one_of" -> v.split(",").map { it.trim() }.filter { it.isNotEmpty() }.any { s.contains(it) }
            else -> false
        }
    }

    /** Human summary like the one shown under each rule in the list. */
    fun describe(conditions: List<Condition>): String {
        if (conditions.isEmpty()) return "No conditions yet"
        val s = conditions.joinToString(" and ") { c ->
            when (c.field) {
                "day_of_week" -> {
                    val d = c.days.orEmpty().map { it.take(3).replaceFirstChar(Char::uppercase) }
                    when (d) {
                        listOf("Mon", "Tue", "Wed", "Thu", "Fri") -> "on weekdays"
                        listOf("Sat", "Sun") -> "at weekends"
                        emptyList<String>() -> "on any day"
                        else -> "on " + d.joinToString(", ")
                    }
                }
                "time" -> "between ${c.from} and ${c.to}"
                "amount" -> "amount ${c.op?.replace('_', ' ')} ${c.value ?: "…"}"
                else -> "${c.field} ${c.op?.replace('_', ' ') ?: "contains"} “${c.value ?: "…"}”"
            }
        }
        return s.replaceFirstChar(Char::uppercase)
    }
}
