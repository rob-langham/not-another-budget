package app.longview.routes

import app.longview.*
import app.longview.auth.AUTH
import app.longview.auth.currentUser
import app.longview.db.*
import app.longview.domain.CsvImport
import app.longview.domain.Money
import app.longview.domain.ReceiptParser
import app.longview.domain.Repeat
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.auth.authenticate
import io.ktor.server.request.contentType
import io.ktor.server.request.receive
import io.ktor.server.request.receiveChannel
import io.ktor.server.response.respond
import io.ktor.server.response.respondBytes
import io.ktor.server.routing.*
import io.ktor.utils.io.toByteArray
import org.jetbrains.exposed.sql.statements.api.ExposedBlob
import org.jetbrains.exposed.sql.SqlExpressionBuilder.inList
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.deleteWhere
import org.jetbrains.exposed.sql.insertAndGetId
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.update
import org.jetbrains.exposed.sql.upsert
import java.time.LocalDate
import java.time.YearMonth

private val KINDS = setOf("spending", "income", "savings", "transfer")
private val ACCOUNT_TYPES = setOf("current", "savings", "credit_card", "cash", "loan", "investment")
private val SOURCES = setOf("bank_link", "file_import", "manual")
private val LOGO_MODES = setOf("automatic", "website", "social", "upload", "letter")
private val REPEATS = setOf("weekly", "four_weekly", "monthly", "yearly", "one_off")
private val GROUPS = setOf("bill", "yearly", "pot")
private val FIELDS = setOf("merchant", "description", "amount", "day_of_week", "time", "account")

fun Route.apiRoutes(cfg: AppConfig, today: () -> LocalDate) {

    fun ApplicationCall.uid(): Long = currentUser(cfg)?.id ?: throw Unauthorized()
    fun views(uid: Long) = Views(Ledger.load(uid), today(), cfg.receiptsEmailDomain)
    fun ApplicationCall.idParam(name: String = "id") = parameters[name]?.toLongOrNull() ?: throw BadRequest("Bad id")

    fun ownsAccount(uid: Long, id: Long) =
        Accounts.selectAll().where { (Accounts.id eq id) and (Accounts.userId eq uid) }.empty().not() || throw NotFound("Account not found")
    fun ownsCategory(uid: Long, id: Long?) =
        id == null || Categories.selectAll().where { (Categories.id eq id) and (Categories.userId eq uid) }.empty().not() || throw NotFound("Category not found")

    /** Inbound email webhook (e.g. Postmark/Mailgun/SendGrid inbound parse, adapted to {to, text}). */
    post("/webhooks/inbound-email") {
        val secret = cfg.inboundEmailSecret
        if (secret == null || call.request.headers["X-Webhook-Secret"] != secret) {
            call.respond(HttpStatusCode.Unauthorized, ErrorDto("Bad secret")); return@post
        }
        val mail = call.receive<InboundEmail>()
        val token = mail.to.substringBefore('@').trim().lowercase()
        val ok = tx {
            val uid = Users.selectAll().where { Users.receiptToken eq token }.singleOrNull()?.get(Users.id)?.value ?: return@tx false
            val p = ReceiptParser.parse(mail.text, today())
            if (p.total == null || p.items.isEmpty()) return@tx false
            Mutations.addReceipt(uid, p.orderDate ?: today(), p.total, p.items); true
        }
        call.respond(if (ok) HttpStatusCode.Accepted else HttpStatusCode.UnprocessableEntity, mapOf("accepted" to ok))
    }

    authenticate(AUTH, optional = cfg.devAuth) {
        route("/api") {
            get("/me") {
                val uid = call.uid()
                call.respond(tx {
                    val u = Users.selectAll().where { Users.id eq uid }.single()
                    MeDto(uid, u[Users.name], u[Users.email], "${u[Users.receiptToken]}@${cfg.receiptsEmailDomain}")
                })
            }

            get("/overview") { val uid = call.uid(); call.respond(tx { views(uid).overview() }) }

            // ---------------- categories ----------------
            route("/categories") {
                get { val uid = call.uid(); call.respond(tx { Ledger.load(uid).categories.map { CategoryDto(it.id, it.name, it.color, it.kind) } }) }
                post {
                    val uid = call.uid(); val b = call.receive<CategoryInput>()
                    if (b.name.isBlank() || b.kind !in KINDS) throw BadRequest("Name and a valid kind are required")
                    val id = tx {
                        Categories.insertAndGetId {
                            it[userId] = uid; it[name] = b.name.trim(); it[color] = b.color; it[kind] = b.kind; it[sortOrder] = 1000
                        }.value
                    }
                    call.respond(HttpStatusCode.Created, CategoryDto(id, b.name.trim(), b.color, b.kind))
                }
                put("/{id}") {
                    val uid = call.uid(); val id = call.idParam(); val b = call.receive<CategoryInput>()
                    if (b.kind !in KINDS) throw BadRequest("Bad kind")
                    tx { ownsCategory(uid, id); Categories.update({ Categories.id eq id }) { it[name] = b.name.trim(); it[color] = b.color; it[kind] = b.kind } }
                    call.respond(CategoryDto(id, b.name.trim(), b.color, b.kind))
                }
                delete("/{id}") {
                    val uid = call.uid(); val id = call.idParam()
                    tx {
                        ownsCategory(uid, id)
                        Transactions.update({ Transactions.categoryId eq id }) { it[categoryId] = null; it[manualCategory] = false }
                        TransactionSplits.update({ TransactionSplits.categoryId eq id }) { it[categoryId] = null }
                        Rules.update({ Rules.categoryId eq id }) { it[categoryId] = null; it[active] = false }
                        ScheduledExpenses.update({ ScheduledExpenses.categoryId eq id }) { it[categoryId] = null }
                        Categories.deleteWhere { Categories.id eq id }
                    }
                    call.respond(HttpStatusCode.NoContent)
                }
            }

            // ---------------- accounts ----------------
            route("/accounts") {
                get { val uid = call.uid(); call.respond(tx { views(uid).accounts() }) }
                post {
                    val uid = call.uid(); val b = call.receive<AccountInput>()
                    if (b.name.isBlank() || b.type !in ACCOUNT_TYPES || b.source !in SOURCES) throw BadRequest("Name, type and source are required")
                    val opening = b.openingDate?.let(LocalDate::parse) ?: today()
                    val dto = tx {
                        val id = Accounts.insertAndGetId {
                            it[userId] = uid; it[name] = b.name.trim(); it[type] = b.type; it[sourceKind] = b.source
                            it[openingBalance] = b.openingBalance; it[openingDate] = opening.toString()
                            it[countsTowardsSavings] = b.countsTowardsSavings; it[logoWebsite] = b.logoWebsite?.takeIf { w -> w.isNotBlank() }
                        }.value
                        val v = views(uid); v.account(Ledger.load(uid).accById.getValue(id))
                    }
                    call.respond(HttpStatusCode.Created, dto)
                }
                patch("/{id}") {
                    val uid = call.uid(); val id = call.idParam(); val b = call.receive<AccountPatch>()
                    if (b.logoMode != null && b.logoMode !in LOGO_MODES) throw BadRequest("Bad logo mode")
                    if (b.type != null && b.type !in ACCOUNT_TYPES) throw BadRequest("Bad type")
                    val dto = tx {
                        ownsAccount(uid, id)
                        Accounts.update({ Accounts.id eq id }) {
                            b.name?.let { v -> it[name] = v.trim() }
                            b.type?.let { v -> it[type] = v }
                            b.countsTowardsSavings?.let { v -> it[countsTowardsSavings] = v }
                            b.logoMode?.let { v -> it[logoMode] = v }
                            b.logoWebsite?.let { v -> it[logoWebsite] = v.ifBlank { null } }
                            b.logoSocial?.let { v -> it[logoSocial] = v.ifBlank { null } }
                            b.logoColor?.let { v -> it[logoColor] = v }
                            b.openingBalance?.let { v -> it[openingBalance] = v }
                            b.openingDate?.let { v -> it[openingDate] = LocalDate.parse(v).toString() }
                        }
                        views(uid).account(Ledger.load(uid).accById.getValue(id))
                    }
                    call.respond(dto)
                }
                delete("/{id}") {
                    val uid = call.uid(); val id = call.idParam()
                    tx {
                        ownsAccount(uid, id)
                        val txIds = Transactions.selectAll().where { Transactions.accountId eq id }.map { it[Transactions.id].value }
                        if (txIds.isNotEmpty()) {
                            Receipts.update({ Receipts.transactionId inList txIds }) { it[transactionId] = null; it[status] = "waiting" }
                            TransactionSplits.deleteWhere { transactionId inList txIds }
                        }
                        Transactions.deleteWhere { accountId eq id }
                        BalanceOverrides.deleteWhere { accountId eq id }
                        ImportLayouts.deleteWhere { accountId eq id }
                        ScheduledExpenses.update({ ScheduledExpenses.accountId eq id }) { it[accountId] = null }
                        Accounts.deleteWhere { Accounts.id eq id }
                    }
                    call.respond(HttpStatusCode.NoContent)
                }
                get("/{id}/balances") {
                    val uid = call.uid(); val id = call.idParam()
                    val days = (call.parameters["days"]?.toIntOrNull() ?: 14).coerceIn(1, 366)
                    call.respond(tx { ownsAccount(uid, id); val l = Ledger.load(uid); Views(l, today()).dailyBalances(l.accById.getValue(id), days) })
                }
                put("/{id}/overrides") {
                    val uid = call.uid(); val id = call.idParam(); val b = call.receive<OverrideInput>()
                    val d = LocalDate.parse(b.date)
                    tx {
                        ownsAccount(uid, id)
                        BalanceOverrides.upsert(BalanceOverrides.accountId, BalanceOverrides.date) {
                            it[accountId] = id; it[date] = d.toString(); it[balance] = b.balance; it[note] = b.note
                        }
                    }
                    call.respond(HttpStatusCode.NoContent)
                }
                delete("/{id}/overrides/{date}") {
                    val uid = call.uid(); val id = call.idParam(); val d = LocalDate.parse(call.parameters["date"]!!).toString()
                    tx { ownsAccount(uid, id); BalanceOverrides.deleteWhere { (accountId eq id) and (date eq d) } }
                    call.respond(HttpStatusCode.NoContent)
                }
                put("/{id}/logo") {
                    val uid = call.uid(); val id = call.idParam()
                    val type = call.request.contentType()
                    if (type.contentType != "image") throw BadRequest("Send a PNG, JPG or SVG image")
                    val bytes = call.receiveChannel().toByteArray()
                    if (bytes.size > 2 * 1024 * 1024) throw BadRequest("Logo must be under 2 MB")
                    tx {
                        ownsAccount(uid, id)
                        Accounts.update({ Accounts.id eq id }) {
                            it[logoContentType] = type.toString(); it[logoImage] = ExposedBlob(bytes); it[logoMode] = "upload"
                        }
                    }
                    call.respond(HttpStatusCode.NoContent)
                }
                get("/{id}/logo") {
                    val uid = call.uid(); val id = call.idParam()
                    val row = tx { ownsAccount(uid, id); Accounts.selectAll().where { Accounts.id eq id }.single() }
                    val img = row[Accounts.logoImage] ?: throw NotFound("No uploaded logo")
                    call.respondBytes(img.bytes, ContentType.parse(row[Accounts.logoContentType] ?: "image/png"))
                }
                post("/{id}/sync") {
                    // Bank links need an open-banking provider (e.g. TrueLayer, GoCardless). Not wired up yet.
                    call.uid()
                    call.respond(HttpStatusCode.NotImplemented, ErrorDto("Bank sync isn't connected yet. Import a CSV file instead."))
                }
            }

            // ---------------- transactions ----------------
            route("/transactions") {
                get {
                    val uid = call.uid()
                    val month = call.parameters["month"]?.let(YearMonth::parse) ?: YearMonth.from(today())
                    val from = call.parameters["from"]?.let(LocalDate::parse) ?: month.atDay(1)
                    val to = call.parameters["to"]?.let(LocalDate::parse) ?: month.atEndOfMonth()
                    call.respond(tx {
                        views(uid).transactionPage(from, to, call.parameters["q"], call.parameters["categoryId"]?.toLongOrNull(), call.parameters["accountId"]?.toLongOrNull())
                    })
                }
                post {
                    val uid = call.uid(); val b = call.receive<TransactionInput>()
                    val d = LocalDate.parse(b.date)
                    val dto = tx {
                        ownsAccount(uid, b.accountId); ownsCategory(uid, b.categoryId)
                        val id = Transactions.insertAndGetId {
                            it[userId] = uid; it[accountId] = b.accountId; it[date] = d.toString()
                            it[time] = b.time?.let { t -> java.time.LocalTime.parse(t).toString() }
                            it[merchant] = b.merchant.trim(); it[description] = (b.description ?: b.merchant).trim(); it[amount] = b.amount
                            it[categoryId] = b.categoryId; it[manualCategory] = b.categoryId != null; it[notes] = b.notes
                        }.value
                        if (b.categoryId == null) Mutations.applyRules(uid, setOf(id))
                        Mutations.matchReceipts(uid)
                        val l = Ledger.load(uid); Views(l, today()).txDto(l.transactions.first { it.id == id })
                    }
                    call.respond(HttpStatusCode.Created, dto)
                }
                patch("/{id}") {
                    val uid = call.uid(); val id = call.idParam(); val b = call.receive<TransactionPatch>()
                    val dto = tx {
                        val owned = Transactions.selectAll().where { (Transactions.id eq id) and (Transactions.userId eq uid) }.empty().not()
                        if (!owned) throw NotFound()
                        ownsCategory(uid, b.categoryId)
                        Transactions.update({ Transactions.id eq id }) {
                            if (b.categoryId != null || b.clearCategory) {
                                it[categoryId] = b.categoryId; it[manualCategory] = !b.clearCategory; it[ruleId] = null; it[awaitingReceipt] = false
                            }
                            b.notes?.let { n -> it[notes] = n }
                        }
                        if (b.clearCategory) Mutations.applyRules(uid, setOf(id))
                        val l = Ledger.load(uid); Views(l, today()).txDto(l.transactions.first { it.id == id })
                    }
                    call.respond(dto)
                }
                delete("/{id}") {
                    val uid = call.uid(); val id = call.idParam()
                    tx {
                        if (Transactions.selectAll().where { (Transactions.id eq id) and (Transactions.userId eq uid) }.empty()) throw NotFound()
                        Receipts.update({ Receipts.transactionId eq id }) { it[transactionId] = null; it[status] = "waiting" }
                        TransactionSplits.deleteWhere { transactionId eq id }
                        Transactions.deleteWhere { Transactions.id eq id }
                    }
                    call.respond(HttpStatusCode.NoContent)
                }
                put("/{id}/splits") {
                    val uid = call.uid(); val id = call.idParam(); val lines = call.receive<List<SplitDto>>()
                    val dto = tx {
                        lines.forEach { ownsCategory(uid, it.categoryId) }
                        Mutations.setSplits(uid, id, lines)
                        val l = Ledger.load(uid); Views(l, today()).txDto(l.transactions.first { it.id == id })
                    }
                    call.respond(dto)
                }
            }

            // ---------------- rules ----------------
            route("/rules") {
                fun validate(b: RuleInput) {
                    if (b.name.isBlank()) throw BadRequest("Give the rule a name")
                    if (b.conditions.isEmpty()) throw BadRequest("Add at least one condition")
                    if (b.conditions.any { it.field !in FIELDS }) throw BadRequest("Unknown condition field")
                    if (b.categoryId == null && !b.splitByReceipt) throw BadRequest("Choose a category")
                }
                get { val uid = call.uid(); call.respond(tx { val l = Ledger.load(uid); val v = Views(l, today()); l.rules.map(v::rule) }) }
                post("/preview") {
                    val uid = call.uid(); val b = call.receive<PreviewInput>()
                    call.respond(tx { views(uid).preview(b.conditions) })
                }
                post {
                    val uid = call.uid(); val b = call.receive<RuleInput>(); validate(b)
                    val dto = tx {
                        ownsCategory(uid, b.categoryId)
                        val id = Rules.insertAndGetId {
                            it[userId] = uid; it[name] = b.name.trim(); it[active] = b.active; it[categoryId] = b.categoryId
                            it[splitByReceipt] = b.splitByReceipt; it[applyPast] = b.applyPast
                            it[conditions] = json.encodeToString(kotlinx.serialization.builtins.ListSerializer(app.longview.domain.Condition.serializer()), b.conditions)
                        }.value
                        if (b.applyPast) Mutations.applyRules(uid)
                        val l = Ledger.load(uid); Views(l, today()).rule(l.ruleById.getValue(id))
                    }
                    call.respond(HttpStatusCode.Created, dto)
                }
                put("/{id}") {
                    val uid = call.uid(); val id = call.idParam(); val b = call.receive<RuleInput>(); validate(b)
                    val dto = tx {
                        if (Rules.selectAll().where { (Rules.id eq id) and (Rules.userId eq uid) }.empty()) throw NotFound()
                        ownsCategory(uid, b.categoryId)
                        Rules.update({ Rules.id eq id }) {
                            it[name] = b.name.trim(); it[active] = b.active; it[categoryId] = b.categoryId
                            it[splitByReceipt] = b.splitByReceipt; it[applyPast] = b.applyPast
                            it[conditions] = json.encodeToString(kotlinx.serialization.builtins.ListSerializer(app.longview.domain.Condition.serializer()), b.conditions)
                        }
                        Mutations.applyRules(uid)
                        val l = Ledger.load(uid); Views(l, today()).rule(l.ruleById.getValue(id))
                    }
                    call.respond(dto)
                }
                delete("/{id}") {
                    val uid = call.uid(); val id = call.idParam()
                    tx {
                        if (Rules.selectAll().where { (Rules.id eq id) and (Rules.userId eq uid) }.empty()) throw NotFound()
                        Transactions.update({ (Transactions.ruleId eq id) and (Transactions.manualCategory eq false) }) {
                            it[ruleId] = null; it[categoryId] = null; it[awaitingReceipt] = false
                        }
                        Rules.deleteWhere { Rules.id eq id }
                        Mutations.applyRules(uid)
                    }
                    call.respond(HttpStatusCode.NoContent)
                }
            }

            // ---------------- ideal budget ----------------
            route("/scheduled") {
                fun dto(s: Sched) = ScheduledDto(
                    s.id, s.name, s.amount, s.categoryId, s.group, s.repeat.repeat, s.repeat.label(), s.repeat.firstDate.toString(),
                    s.repeat.endType, s.repeat.endDate?.toString(), s.repeat.endCount, s.accountId, s.matchText,
                    s.repeat.monthlyEquivalent(s.amount).takeIf { s.group != "pot" || it > 0 } ?: s.amount,
                )
                fun validate(b: ScheduledInput) {
                    if (b.name.isBlank() || b.amount <= 0) throw BadRequest("Name and an amount above zero are required")
                    if (b.repeat !in REPEATS || b.group !in GROUPS) throw BadRequest("Bad repeat or group")
                    LocalDate.parse(b.firstDate)
                }
                fun write(uid: Long, b: ScheduledInput, st: org.jetbrains.exposed.sql.statements.UpdateBuilder<*>) {
                    st[ScheduledExpenses.userId] = uid; st[ScheduledExpenses.name] = b.name.trim(); st[ScheduledExpenses.amount] = b.amount
                    st[ScheduledExpenses.categoryId] = b.categoryId; st[ScheduledExpenses.group] = b.group; st[ScheduledExpenses.repeat] = b.repeat
                    st[ScheduledExpenses.firstDate] = b.firstDate; st[ScheduledExpenses.endType] = b.endType
                    st[ScheduledExpenses.endDate] = b.endDate; st[ScheduledExpenses.endCount] = b.endCount
                    st[ScheduledExpenses.accountId] = b.accountId; st[ScheduledExpenses.matchText] = b.matchText?.takeIf { it.isNotBlank() }
                }
                get { val uid = call.uid(); call.respond(tx { Ledger.load(uid).scheduled.map(::dto) }) }
                post {
                    val uid = call.uid(); val b = call.receive<ScheduledInput>(); validate(b)
                    val res = tx {
                        b.accountId?.let { ownsAccount(uid, it) }; ownsCategory(uid, b.categoryId)
                        val id = ScheduledExpenses.insertAndGetId { write(uid, b, it) }.value
                        dto(Ledger.load(uid).scheduled.first { it.id == id })
                    }
                    call.respond(HttpStatusCode.Created, res)
                }
                put("/{id}") {
                    val uid = call.uid(); val id = call.idParam(); val b = call.receive<ScheduledInput>(); validate(b)
                    val res = tx {
                        if (ScheduledExpenses.selectAll().where { (ScheduledExpenses.id eq id) and (ScheduledExpenses.userId eq uid) }.empty()) throw NotFound()
                        b.accountId?.let { ownsAccount(uid, it) }; ownsCategory(uid, b.categoryId)
                        ScheduledExpenses.update({ ScheduledExpenses.id eq id }) { write(uid, b, it) }
                        dto(Ledger.load(uid).scheduled.first { it.id == id })
                    }
                    call.respond(res)
                }
                delete("/{id}") {
                    val uid = call.uid(); val id = call.idParam()
                    tx { ScheduledExpenses.deleteWhere { (ScheduledExpenses.id eq id) and (userId eq uid) } }
                    call.respond(HttpStatusCode.NoContent)
                }
                /** "Find repeats from history": the same merchant and a similar amount in 3 of the last 4 months. */
                get("/suggestions") {
                    val uid = call.uid()
                    call.respond(tx {
                        val l = Ledger.load(uid)
                        val now = YearMonth.from(today())
                        val window = (1..4).map { now.minusMonths(it.toLong()) }.toSet()
                        val known = l.scheduled.map { it.needle }
                        l.transactions.filter { it.amount < 0 && YearMonth.from(it.date) in window }
                            .groupBy { it.merchant.lowercase() }
                            .filter { (m, _) -> known.none { m.contains(it) || it.contains(m) } }
                            .mapNotNull { (_, list) ->
                                val months = list.groupBy { YearMonth.from(it.date) }
                                if (months.size < 3) return@mapNotNull null
                                val amounts = months.values.map { ms -> ms.sumOf { -it.amount } }.sorted()
                                val median = amounts[amounts.size / 2]
                                if (amounts.any { kotlin.math.abs(it - median) > median / 10 }) return@mapNotNull null
                                if (months.values.any { it.size > 1 }) return@mapNotNull null
                                val last = list.maxBy { it.date }
                                RepeatSuggestion(last.merchant, median, "monthly", last.date.plusMonths(1).toString(), months.size, last.accountId)
                            }.sortedByDescending { it.amount }
                    })
                }
            }

            get("/budget") {
                val uid = call.uid()
                val month = call.parameters["month"]?.let(YearMonth::parse) ?: YearMonth.from(today())
                call.respond(tx { views(uid).budget(month) })
            }

            // ---------------- outliers ----------------
            route("/outliers") {
                get { val uid = call.uid(); call.respond(tx { views(uid).outliers() }) }
                post("/{id}/keep") {
                    val uid = call.uid(); val id = call.idParam()
                    tx { Transactions.update({ (Transactions.id eq id) and (Transactions.userId eq uid) }) { it[outlierDecision] = "one_off" } }
                    call.respond(HttpStatusCode.NoContent)
                }
                post("/{id}/recurring") {
                    val uid = call.uid(); val id = call.idParam(); val b = call.receive<MakeRecurringInput>()
                    if (b.repeat !in REPEATS || b.group !in GROUPS) throw BadRequest("Bad repeat")
                    tx {
                        val l = Ledger.load(uid)
                        val t = l.transactions.firstOrNull { it.id == id } ?: throw NotFound()
                        val similar = l.transactions.filter { it.amount < 0 && it.merchant.equals(t.merchant, ignoreCase = true) && !it.date.isBefore(t.date.minusMonths(6)) }
                        val avg = similar.sumOf { -it.amount } / similar.size
                        val next = Repeat(b.repeat, t.date).nextOnOrAfter(today()) ?: t.date
                        ScheduledExpenses.insertAndGetId {
                            it[userId] = uid; it[name] = t.merchant; it[amount] = avg; it[categoryId] = t.categoryId; it[group] = b.group
                            it[repeat] = b.repeat; it[firstDate] = t.date.toString(); it[accountId] = t.accountId; it[matchText] = t.merchant
                        }
                        Transactions.update({ Transactions.id eq id }) { it[outlierDecision] = "recurring" }
                        next
                    }
                    call.respond(HttpStatusCode.NoContent)
                }
            }

            // ---------------- savings goal ----------------
            route("/goal") {
                get { val uid = call.uid(); val g = tx { views(uid).goal() }; if (g == null) call.respond(HttpStatusCode.NoContent) else call.respond(g) }
                put {
                    val uid = call.uid(); val b = call.receive<GoalInput>()
                    if (b.monthlyAmount <= 0) throw BadRequest("Monthly goal must be above zero")
                    val start = LocalDate.parse(b.startDate); val target = b.targetDate?.let(LocalDate::parse)
                    if (target != null && target < start) throw BadRequest("Target date is before the start date")
                    val g = tx {
                        SavingsGoals.upsert(SavingsGoals.userId) {
                            it[userId] = uid; it[monthlyAmount] = b.monthlyAmount; it[startDate] = start.toString(); it[targetDate] = target?.toString()
                        }
                        views(uid).goal()!!
                    }
                    call.respond(g)
                }
            }

            // ---------------- file import ----------------
            route("/import") {
                post("/parse") {
                    val uid = call.uid(); val b = call.receive<ImportParseInput>()
                    val res = tx {
                        ownsAccount(uid, b.accountId)
                        val rows = CsvImport.parse(b.content)
                        if (rows.size < 2) throw BadRequest("That file has no rows we can read.")
                        val headers = rows.first(); val body = rows.drop(1)
                        val saved = Mutations.layout(b.accountId)
                        val usedSaved = saved != null && saved.mapping.keys == headers.toSet()
                        val mapping = CsvImport.suggest(headers, body, if (usedSaved) saved!!.mapping else null)
                        val dateCol = mapping.indexOfFirst { it.use == "date" }
                        val dateSamples = if (dateCol >= 0) body.mapNotNull { it.getOrNull(dateCol) } else emptyList()
                        val dateFormat = if (usedSaved) saved!!.dateFormat else CsvImport.detectDateFormat(dateSamples)
                        val amountCol = mapping.indexOfFirst { it.use == "amount" }
                        val descCol = mapping.indexOfFirst { it.use == "description" }
                        val sign = when {
                            usedSaved -> saved!!.sign
                            amountCol >= 0 -> CsvImport.detectSign(body.mapNotNull { Money.parse(it.getOrNull(amountCol)) }, body.map { it.getOrNull(descCol).orEmpty() })
                            else -> "positive_in"
                        }
                        val (parsed, errors) = CsvImport.toRows(body, mapping, dateFormat, sign)
                        val classified = Mutations.classify(uid, b.accountId, parsed)
                        val l = Ledger.load(uid)
                        val preview = classified.take(10).map { c ->
                            val facts = app.longview.domain.TxFacts(c.row.merchant, c.row.description, c.row.amount, c.row.date, c.row.time, l.accById[b.accountId]?.name ?: "")
                            val rule = l.rules.firstOrNull { it.active && app.longview.domain.RuleEngine.matches(it.conditions, facts) }
                            val catName = rule?.let { if (it.splitByReceipt) "Split by receipt" else l.catById[it.categoryId]?.name }
                            ImportPreviewRow(c.row.date.toString(), c.row.merchant, catName, c.row.amount, c.duplicate)
                        }
                        ImportParseResult(
                            b.fileName, headers, body.take(4), body.size, mapping, dateFormat, dateSamples.firstOrNull(), sign, usedSaved,
                            preview, classified.count { !it.duplicate }, classified.count { it.duplicate }, errors.take(20),
                        )
                    }
                    call.respond(res)
                }
                post("/commit") {
                    val uid = call.uid(); val b = call.receive<ImportCommitInput>()
                    if (b.mapping.none { it.use == "date" }) throw BadRequest("Choose which column holds the date")
                    if (b.mapping.none { it.use in setOf("amount", "money_in", "money_out") }) throw BadRequest("Choose which column holds the amount")
                    val res = tx {
                        ownsAccount(uid, b.accountId)
                        val rows = CsvImport.parse(b.content)
                        val (parsed, errors) = CsvImport.toRows(rows.drop(1), b.mapping, b.dateFormat, b.signConvention)
                        val (imported, dups) = Mutations.commitImport(uid, b.accountId, parsed)
                        if (b.rememberLayout) Mutations.saveLayout(b.accountId, b.mapping, b.dateFormat, b.signConvention)
                        Accounts.update({ Accounts.id eq b.accountId }) { it[lastSyncedAt] = java.time.Instant.now().toString() }
                        ImportCommitResult(imported, dups, errors.take(20), Mutations.matchReceipts(uid))
                    }
                    call.respond(res)
                }
            }

            // ---------------- Amazon receipts ----------------
            route("/receipts") {
                fun list(uid: Long): List<ReceiptDto> {
                    val l = Ledger.load(uid); val v = Views(l, today())
                    val txById = l.transactions.associateBy { it.id }
                    return Receipts.selectAll().where { Receipts.userId eq uid }.orderBy(Receipts.id, org.jetbrains.exposed.sql.SortOrder.DESC).map {
                        ReceiptDto(
                            it[Receipts.id].value, it[Receipts.receivedAt], it[Receipts.orderDate], it[Receipts.total],
                            Mutations.decodeItems(it[Receipts.items]), it[Receipts.status],
                            it[Receipts.transactionId]?.value?.let { id -> txById[id] }?.let(v::txDto),
                        )
                    }
                }
                get { val uid = call.uid(); call.respond(tx { list(uid) }) }
                post {
                    val uid = call.uid(); val b = call.receive<ReceiptInput>()
                    val p = ReceiptParser.parse(b.text, today())
                    if (p.total == null || p.items.isEmpty()) throw BadRequest("We couldn't find items and prices in that email.")
                    val res = tx { val id = Mutations.addReceipt(uid, p.orderDate ?: today(), p.total, p.items); list(uid).first { it.id == id } }
                    call.respond(HttpStatusCode.Created, res)
                }
                post("/{id}/save") {
                    val uid = call.uid(); val id = call.idParam(); val b = call.receive<SaveSplitInput>()
                    val res = tx {
                        val r = Receipts.selectAll().where { (Receipts.id eq id) and (Receipts.userId eq uid) }.singleOrNull() ?: throw NotFound()
                        val txId = r[Receipts.transactionId]?.value ?: throw BadRequest("This receipt isn't matched to a payment yet.")
                        b.items.forEach { ownsCategory(uid, it.categoryId) }
                        Mutations.setSplits(uid, txId, b.items.map { SplitDto(null, it.name, it.amount, it.categoryId) })
                        Receipts.update({ Receipts.id eq id }) { it[items] = Mutations.encodeItems(b.items); it[status] = "saved" }
                        list(uid).first { it.id == id }
                    }
                    call.respond(res)
                }
                delete("/{id}") {
                    val uid = call.uid(); val id = call.idParam()
                    tx { Receipts.deleteWhere { (Receipts.id eq id) and (userId eq uid) } }
                    call.respond(HttpStatusCode.NoContent)
                }
            }
        }
    }
}
