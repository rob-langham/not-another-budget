package app.longview.domain

import java.math.BigDecimal
import java.math.RoundingMode

object Money {
    /** Parses "£1,234.56", "-12.3", "(45.00)", "1.234,56"-free UK style text to pence. */
    fun parse(text: String?): Long? {
        if (text == null) return null
        var s = text.trim()
        if (s.isEmpty() || s == "—" || s == "-") return null
        var negative = false
        if (s.startsWith("(") && s.endsWith(")")) { negative = true; s = s.substring(1, s.length - 1) }
        s = s.replace("£", "").replace("$", "").replace("€", "").replace(",", "").replace(" ", "")
        s = s.replace('−', '-') // unicode minus
        if (s.endsWith("CR", ignoreCase = true)) { s = s.dropLast(2) }
        if (s.endsWith("DR", ignoreCase = true)) { s = s.dropLast(2); negative = !negative }
        if (s.startsWith("+")) s = s.drop(1)
        if (s.startsWith("-")) { negative = !negative; s = s.drop(1) }
        val bd = s.toBigDecimalOrNull() ?: return null
        val pence = bd.setScale(2, RoundingMode.HALF_UP).movePointRight(2).longValueExact()
        return if (negative) -pence else pence
    }

    fun format(pence: Long): String {
        val sign = if (pence < 0) "−" else ""
        val bd = BigDecimal.valueOf(kotlin.math.abs(pence), 2)
        return sign + "£" + String.format("%,.2f", bd)
    }
}
