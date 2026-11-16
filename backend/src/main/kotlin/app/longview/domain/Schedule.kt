package app.longview.domain

import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit

/** Repeat maths for scheduled expenses. */
data class Repeat(
    val repeat: String, // weekly | four_weekly | monthly | yearly | one_off
    val firstDate: LocalDate,
    val endType: String = "never", // never | on_date | after_count
    val endDate: LocalDate? = null,
    val endCount: Int? = null,
) {
    /** Every payment date, in order, up to and including [until]. */
    fun occurrences(until: LocalDate): Sequence<LocalDate> = sequence {
        var n = 0
        while (true) {
            val d = nth(n) ?: break
            if (d.isAfter(until)) break
            if (endType == "on_date" && endDate != null && d.isAfter(endDate)) break
            if (endType == "after_count" && endCount != null && n >= endCount) break
            yield(d)
            n++
            if (repeat == "one_off") break
        }
    }

    private fun nth(n: Int): LocalDate? = when (repeat) {
        "weekly" -> firstDate.plusWeeks(n.toLong())
        "four_weekly" -> firstDate.plusWeeks(4L * n)
        "monthly" -> firstDate.plusMonths(n.toLong()) // plusMonths clamps 31st to month end
        "yearly" -> firstDate.plusYears(n.toLong())
        "one_off" -> if (n == 0) firstDate else null
        else -> null
    }

    fun inMonth(month: YearMonth): List<LocalDate> =
        occurrences(month.atEndOfMonth()).filter { YearMonth.from(it) == month }.toList()

    fun nextOnOrAfter(day: LocalDate): LocalDate? =
        occurrences(day.plusYears(2)).firstOrNull { !it.isBefore(day) }

    /** Average cost per month, in pence, for a payment of [amount]. */
    fun monthlyEquivalent(amount: Long): Long = when (repeat) {
        "weekly" -> Math.round(amount * 52.0 / 12.0)
        "four_weekly" -> Math.round(amount * 13.0 / 12.0)
        "monthly" -> amount
        "yearly" -> Math.round(amount / 12.0)
        else -> 0
    }

    fun label(): String = when (repeat) {
        "weekly" -> "Weekly, on ${firstDate.dayOfWeek.name.lowercase().replaceFirstChar(Char::uppercase)}s"
        "four_weekly" -> "Every 4 weeks"
        "monthly" -> "Monthly, on the ${ordinal(firstDate.dayOfMonth)}"
        "yearly" -> "Yearly"
        "one_off" -> "One-off"
        else -> repeat
    }

    companion object {
        fun ordinal(d: Int): String = d.toString() + when {
            d in 11..13 -> "th"
            d % 10 == 1 -> "st"
            d % 10 == 2 -> "nd"
            d % 10 == 3 -> "rd"
            else -> "th"
        }
    }
}

fun daysBetween(a: LocalDate, b: LocalDate): Long = ChronoUnit.DAYS.between(a, b)
