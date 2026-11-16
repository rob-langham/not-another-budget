package app.longview

import app.longview.domain.*
import java.time.LocalDate
import java.time.LocalTime
import java.time.YearMonth
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DomainTest {
    @Test fun moneyParsing() {
        assertEquals(123456, Money.parse("£1,234.56"))
        assertEquals(-50000, Money.parse("-500.00"))
        assertEquals(-4500, Money.parse("(45.00)"))
        assertEquals(-1099, Money.parse("−£10.99"))
        assertEquals("−£642.18", Money.format(-64218))
    }

    private val lunch = listOf(
        Condition("merchant", "contains", "Tesco"),
        Condition("amount", "less_than", "£20.00"),
        Condition("day_of_week", days = listOf("Mon", "Tue", "Wed", "Thu", "Fri")),
        Condition("time", from = "11:00", to = "15:00"),
    )

    @Test fun weekdayLunchRule() {
        val fri = LocalDate.of(2026, 11, 13)
        val t = TxFacts("Tesco Express", "TESCO EXPRESS", -740, fri, LocalTime.of(14, 2), "Monzo")
        assertTrue(RuleEngine.matches(lunch, t))
        assertFalse(RuleEngine.matches(lunch, t.copy(time = LocalTime.of(18, 44))))
        assertFalse(RuleEngine.matches(lunch, t.copy(date = fri.plusDays(1))))
        assertFalse(RuleEngine.matches(lunch, t.copy(amount = -5830)))
        assertEquals("Merchant contains “Tesco” and amount less than £20.00 and on weekdays and between 11:00 and 15:00", RuleEngine.describe(lunch))
    }

    @Test fun repeats() {
        val monthly = Repeat("monthly", LocalDate.of(2026, 1, 31))
        assertEquals(listOf(LocalDate.of(2026, 2, 28)), monthly.inMonth(YearMonth.of(2026, 2)))
        assertEquals(1950, Repeat("four_weekly", LocalDate.of(2026, 11, 27)).monthlyEquivalent(1800)) // design: £18 → £19.50/month
        assertEquals(4500, Repeat("yearly", LocalDate.of(2026, 4, 3)).monthlyEquivalent(54000))
        assertEquals("Monthly, on the 22nd", Repeat("monthly", LocalDate.of(2026, 1, 22)).label())
        val limited = Repeat("weekly", LocalDate.of(2026, 1, 1), "after_count", endCount = 3)
        assertEquals(3, limited.occurrences(LocalDate.of(2027, 1, 1)).count())
    }

    @Test fun balanceOverrideRecalculatesLaterDays() {
        val open = LocalDate.of(2026, 11, 9)
        val tx = mapOf(LocalDate.of(2026, 11, 10) to -1000L, LocalDate.of(2026, 11, 11) to -500L)
        val days = Balances.daily(10000, open, tx, listOf(Override(LocalDate.of(2026, 11, 10), 9500, "refund")), open, LocalDate.of(2026, 11, 11))
        assertEquals(listOf(10000L, 9500L, 9000L), days.map { it.balance })
        assertEquals(9000L, days[1].calculated)
        assertTrue(days[1].overridden)
    }

    private val amex = """
        Date,Description,Amount,Appears On Your Statement As,Extended Details,Address,Reference
        12/11/2026,AMAZON.CO.UK*AB12C,64.97,AMAZON.CO.UK,Online retail,LUXEMBOURG,AT243160034
        11/11/2026,TESCO STORES 3021,4.85,TESCO EXPRESS,Groceries,LONDON,AT243150118
        09/11/2026,SHELL 4471,52.10,SHELL,Fuel,READING,AT243130072
        05/11/2026,PAYMENT RECEIVED - THANK YOU,-500.00,PAYMENT RECEIVED,,,AT243090001
    """.trimIndent()

    @Test fun amexCsvIsMatched() {
        val rows = CsvImport.parse(amex)
        val m = CsvImport.suggest(rows[0], rows.drop(1), null)
        assertEquals(listOf("date", "description", "amount", "merchant", "notes", "skip", "reference"), m.map { it.use })
        assertFalse(m[5].confident)
        assertEquals("dmy", CsvImport.detectDateFormat(rows.drop(1).map { it[0] }))
        val sign = CsvImport.detectSign(rows.drop(1).map { Money.parse(it[2])!! }, rows.drop(1).map { it[1] })
        assertEquals("positive_out", sign)
        val (parsed, errors) = CsvImport.toRows(rows.drop(1), m, "dmy", sign)
        assertTrue(errors.isEmpty())
        assertEquals(-6497, parsed[0].amount)
        assertEquals("Amazon", parsed[0].merchant)
        assertEquals(50000, parsed[3].amount)
    }

    @Test fun separateInOutColumns() {
        val csv = "Transaction Date,Details,Paid out,Paid in,Balance\n01/11/2026,RENT,1150.00,,100.00\n31/10/2026,ACME LTD,,3250.00,1250.00"
        val rows = CsvImport.parse(csv)
        val m = CsvImport.suggest(rows[0], rows.drop(1), null)
        assertEquals(listOf("date", "description", "money_out", "money_in", "balance"), m.map { it.use })
        val (parsed, _) = CsvImport.toRows(rows.drop(1), m, "dmy", "positive_in")
        assertEquals(listOf(-115000L, 325000L), parsed.map { it.amount })
    }

    @Test fun amazonEmail() {
        val email = """
            Order Confirmation
            Order placed 12 November 2026
            USB-C charging cable, 2 m  Qty: 1  £8.99
            Children's picture book £6.99
            Washing-up liquid, 3 pack £4.49
            Running shoes £44.50
            Delivery: £0.00
            Order Total: £64.97
        """.trimIndent()
        val r = ReceiptParser.parse(email, LocalDate.of(2026, 11, 16))
        assertEquals(6497, r.total)
        assertEquals(LocalDate.of(2026, 11, 12), r.orderDate)
        assertEquals(listOf("USB-C charging cable, 2 m", "Children's picture book", "Washing-up liquid, 3 pack", "Running shoes"), r.items.map { it.name })
        assertEquals(6497, r.items.sumOf { it.amount })
    }
}
