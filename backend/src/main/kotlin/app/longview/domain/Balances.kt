package app.longview.domain

import java.time.LocalDate

data class DayBalance(
    val date: LocalDate,
    /** What the balance would be from transactions alone. */
    val calculated: Long,
    /** The balance we show: the override if there is one, else calculated. */
    val balance: Long,
    val overridden: Boolean,
    val note: String?,
)

data class Override(val date: LocalDate, val balance: Long, val note: String?)

object Balances {
    /**
     * End-of-day balances from [from] to [to]. The opening balance is the balance at the end of [openingDate].
     * An override replaces that day's balance; every later day is recalculated from it.
     */
    fun daily(
        openingBalance: Long,
        openingDate: LocalDate,
        txByDate: Map<LocalDate, Long>,
        overrides: List<Override>,
        from: LocalDate,
        to: LocalDate,
    ): List<DayBalance> {
        // Overrides before the opening date can't affect anything we show, so they are ignored.
        val ov = overrides.filter { !it.date.isBefore(openingDate) }.associateBy { it.date }
        val out = ArrayList<DayBalance>()
        // Opening day: transactions on it are already inside the opening balance.
        val o0 = ov[openingDate]
        var running = o0?.balance ?: openingBalance
        if (!openingDate.isBefore(from) && !openingDate.isAfter(to)) {
            out += DayBalance(openingDate, openingBalance, running, o0 != null, o0?.note ?: "Opening balance")
        }
        var d = openingDate.plusDays(1)
        while (!d.isAfter(to)) {
            val calc = running + (txByDate[d] ?: 0)
            val o = ov[d]
            val shown = o?.balance ?: calc
            if (!d.isBefore(from)) out += DayBalance(d, calc, shown, o != null, o?.note)
            running = shown
            d = d.plusDays(1)
        }
        return out
    }

    fun current(
        openingBalance: Long,
        openingDate: LocalDate,
        txByDate: Map<LocalDate, Long>,
        overrides: List<Override>,
        today: LocalDate,
    ): Long {
        val lastTx = txByDate.keys.maxOrNull()
        val end = listOfNotNull(today, lastTx).max()
        if (end <= openingDate) return openingBalance
        return daily(openingBalance, openingDate, txByDate, overrides, end, end).lastOrNull()?.balance ?: openingBalance
    }
}
