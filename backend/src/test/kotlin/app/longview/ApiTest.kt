package app.longview

import app.longview.db.Db
import app.longview.domain.Condition
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.*
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Recreates the numbers shown in the Longview design and checks the API agrees. Date: Mon 16 Nov 2026. */
class ApiTest {
    private val cfg = AppConfig(0, "127.0.0.1", ":memory:", emptyList(), "receipts.test", "s3cret")
    private val clock = Clock.fixed(LocalDate.of(2026, 11, 16).atTime(12, 0).toInstant(ZoneOffset.UTC), ZoneOffset.UTC)

    private fun run(block: suspend ApplicationTestBuilder.(HttpClient) -> Unit) = testApplication {
        Db.init(":memory:")
        LocalUser.reset()
        application { module(cfg, clock) }
        val c = createClient {
            install(ContentNegotiation) { json(json) }
            defaultRequest { contentType(ContentType.Application.Json) }
        }
        block(c)
    }

    private suspend inline fun <reified T> HttpClient.postJ(url: String, body: Any): T {
        val r = post(url) { setBody(body) }
        assertTrue(r.status.value in 200..299, "$url -> ${r.status} ${r.bodyAsText()}")
        return r.body()
    }

    @Test fun designScenario() = run { c ->
        val cats = c.get("/api/categories").body<List<CategoryDto>>().associateBy { it.name }
        fun cat(n: String) = cats.getValue(n).id

        val monzo = c.postJ<AccountDto>("/api/accounts", AccountInput("Monzo Current", "current", "file_import", 0, "2026-02-28"))
        val starling = c.postJ<AccountDto>("/api/accounts", AccountInput("Starling Savings", "savings", "file_import", 0, "2026-02-28", countsTowardsSavings = true))
        val amex = c.postJ<AccountDto>("/api/accounts", AccountInput("Amex card", "credit_card", "file_import", 0, "2026-10-31"))

        // Savings each month, Mar..Nov, as in the design's bar chart.
        val saved = listOf(52000, 48000, 61000, 35000, 50000, 29000, 54000, 42000, 16000)
        saved.forEachIndexed { i, a ->
            c.postJ<TransactionDto>("/api/transactions", TransactionInput(starling.id, LocalDate.of(2026, 3 + i, 2).toString(), null, "From Monzo", amount = a.toLong()))
        }
        c.put("/api/goal") { setBody(GoalInput(50000, "2026-03-01")) }

        val goal = c.get("/api/goal").body<GoalDto>()
        assertEquals(387000, goal.saved)
        assertEquals(426667, goal.expected)
        assertEquals(500000, goal.target)
        assertEquals("behind", goal.status)
        assertEquals(39667, goal.behindBy)
        assertEquals(19900, goal.catchUpPerMonth) // "Save an extra £199 in November and December"
        assertEquals(90.7, goal.percentOfPace)

        // Rules
        val lunchRule = c.postJ<RuleDto>("/api/rules", RuleInput("Weekday lunch at Tesco", categoryId = cat("Lunch"), conditions = listOf(
            Condition("merchant", "contains", "Tesco"), Condition("amount", "less_than", "20.00"),
            Condition("day_of_week", days = listOf("Mon", "Tue", "Wed", "Thu", "Fri")), Condition("time", from = "11:00", to = "15:00"))))
        c.postJ<RuleDto>("/api/rules", RuleInput("Amazon orders", splitByReceipt = true, conditions = listOf(Condition("merchant", "contains", "Amazon"))))
        c.postJ<RuleDto>("/api/rules", RuleInput("Salary", categoryId = cat("Income"), conditions = listOf(Condition("description", "contains", "ACME LTD"))))

        // Import a Monzo-style file with separate in/out columns and times.
        val monzoCsv = """
            Date,Time,Name,Paid out,Paid in
            31/10/2026,06:00,ACME LTD,,3250.00
            01/11/2026,08:00,Rent,1150.00,
            13/11/2026,14:02,Tesco Express,7.40,
            13/11/2026,08:10,Train to Leeds,80.60,
            09/11/2026,09:40,Vet bill,186.40,
            14/11/2026,18:44,Tesco Superstore,58.30,
        """.trimIndent()
        val parsed = c.postJ<ImportParseResult>("/api/import/parse", ImportParseInput(monzo.id, "monzo.csv", monzoCsv))
        assertEquals(listOf("date", "time", "merchant", "money_out", "money_in"), parsed.mapping.map { it.use })
        assertEquals(6, parsed.newRows)
        val committed = c.postJ<ImportCommitResult>("/api/import/commit", ImportCommitInput(monzo.id, monzoCsv, parsed.mapping, parsed.dateFormat, parsed.signConvention))
        assertEquals(6, committed.imported)
        // Re-importing the same file adds nothing.
        assertEquals(0, c.postJ<ImportCommitResult>("/api/import/commit", ImportCommitInput(monzo.id, monzoCsv, parsed.mapping, parsed.dateFormat, parsed.signConvention)).imported)

        val txs = c.get("/api/transactions?from=2026-10-01&to=2026-11-30").body<TransactionPage>().transactions
        val tesco = txs.first { it.merchant == "Tesco Express" }
        assertEquals(cat("Lunch"), tesco.categoryId)
        assertEquals("Weekday lunch at Tesco", tesco.ruleName)
        assertEquals(null, txs.first { it.merchant == "Tesco Superstore" }.categoryId) // 18:44 is outside lunch hours
        assertEquals(cat("Income"), txs.first { it.merchant == "Acme Ltd" }.categoryId)
        assertTrue(c.get("/api/rules").body<List<RuleDto>>().first { it.id == lunchRule.id }.match.count == 1)

        // Ideal budget
        c.postJ<ScheduledDto>("/api/scheduled", ScheduledInput("Rent", 115000, cat("Bills"), "bill", "monthly", "2026-01-01", accountId = monzo.id))
        c.postJ<ScheduledDto>("/api/scheduled", ScheduledInput("Gym", 3500, cat("Health & fitness"), "bill", "monthly", "2026-01-18", accountId = monzo.id))
        c.postJ<ScheduledDto>("/api/scheduled", ScheduledInput("Groceries", 32000, cat("Groceries"), "pot", "monthly", "2026-01-01"))
        c.postJ<ScheduledDto>("/api/scheduled", ScheduledInput("Car insurance", 54000, null, "yearly", "yearly", "2026-04-03", accountId = starling.id))
        c.patch("/api/transactions/${txs.first { it.merchant == "Tesco Superstore" }.id}") { setBody(TransactionPatch(categoryId = cat("Groceries"))) }

        val budget = c.get("/api/budget").body<BudgetDto>()
        val rent = budget.lines.first { it.name == "Rent" }
        assertEquals("paid", rent.status); assertEquals("Paid 1 Nov", rent.statusText)
        assertEquals("Due in 2 days", budget.lines.first { it.name == "Gym" }.statusText)
        assertEquals(5830, budget.lines.first { it.name == "Groceries" }.used)
        assertEquals("£315.00 of £540.00 put by", budget.lines.first { it.name == "Car insurance" }.statusText)
        assertEquals(115000 + 3500 + 32000 + 4500L, budget.planned)

        // Outliers: vet bill + train (Lunch is not a pot here, so the Tesco lunch counts too).
        val out = c.get("/api/outliers").body<OutliersDto>()
        val nov = out.months.first()
        assertTrue(nov.items.any { it.transaction.merchant == "Vet bill" })
        assertTrue(nov.items.none { it.transaction.merchant == "Rent" })
        assertTrue(nov.items.none { it.transaction.merchant == "Tesco Superstore" }) // groceries pot

        // Amazon: card import, then the forwarded email splits it.
        val amexCsv = "Date,Description,Amount,Reference\n12/11/2026,AMAZON.CO.UK*AB12C,64.97,AT1\n05/11/2026,PAYMENT RECEIVED - THANK YOU,-500.00,AT2"
        val ap = c.postJ<ImportParseResult>("/api/import/parse", ImportParseInput(amex.id, "amex.csv", amexCsv))
        assertEquals("Split by receipt", ap.preview.first().categoryName)
        c.postJ<ImportCommitResult>("/api/import/commit", ImportCommitInput(amex.id, amexCsv, ap.mapping, ap.dateFormat, ap.signConvention))
        val me = c.get("/api/me").body<MeDto>()
        val hook = c.post("/webhooks/inbound-email") {
            header("X-Webhook-Secret", "s3cret")
            setBody(InboundEmail(me.forwardingAddress, "Order placed 12 November 2026\nUSB-C cable £8.99\nPicture book £6.99\nWashing-up liquid £4.49\nRunning shoes £44.50\nOrder Total: £64.97"))
        }
        assertEquals(HttpStatusCode.Accepted, hook.status)
        val receipt = c.get("/api/receipts").body<List<ReceiptDto>>().single()
        assertEquals("ready", receipt.status)
        assertEquals(-6497, receipt.transaction!!.amount)
        val items = receipt.items.mapIndexed { i, it -> it.copy(categoryId = listOf(cat("Tech"), cat("Gifts"), cat("Household"), cat("Health & fitness"))[i]) }
        val savedR = c.postJ<ReceiptDto>("/api/receipts/${receipt.id}/save", SaveSplitInput(items))
        assertEquals("saved", savedR.status)
        assertEquals(4, savedR.transaction!!.splits.size)
        assertEquals(false, savedR.transaction!!.awaitingReceipt)

        // Unbalanced splits are refused.
        val bad = c.put("/api/transactions/${savedR.transaction!!.id}/splits") { setBody(listOf(SplitDto(null, "x", 100, null))) }
        assertEquals(HttpStatusCode.BadRequest, bad.status)

        // Balance override
        c.put("/api/accounts/${monzo.id}/overrides") { setBody(OverrideInput("2026-11-10", 200000, "Pending refund")) }
        val bal = c.get("/api/accounts/${monzo.id}/balances?days=7").body<List<DayBalanceDto>>()
        val d10 = bal.first { it.date == "2026-11-10" }
        assertTrue(d10.overridden); assertEquals(200000, d10.balance)
        assertEquals(200000 - 740 - 8060 - 5830L, bal.first().balance) // 16 Nov: recalculated from the override

        val ov = c.get("/api/overview").body<OverviewDto>()
        assertEquals(325000, ov.incomeThisMonth) // salary landed 31 Oct: counts for this pay cycle
        assertEquals(3, ov.accounts.size)
        assertEquals(ov.accounts.sumOf { it.balance }, ov.netPosition)
        assertTrue(ov.comingUp.any { it.name == "Gym" && it.date == "2026-11-18" })
    }

}
