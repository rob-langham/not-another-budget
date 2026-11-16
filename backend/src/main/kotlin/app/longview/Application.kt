package app.longview

import app.longview.auth.configureAuth
import app.longview.db.Db
import app.longview.routes.apiRoutes
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.cors.routing.CORS
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import kotlinx.serialization.SerializationException
import java.time.Clock
import java.time.LocalDate

fun main() {
    val cfg = AppConfig.fromEnv()
    Db.init(cfg.dbPath)
    embeddedServer(Netty, port = cfg.port, host = "0.0.0.0") { module(cfg) }.start(wait = true)
}

fun Application.module(cfg: AppConfig, clock: Clock = Clock.systemDefaultZone()) {
    install(ContentNegotiation) { json(json) }
    install(CallLogging)
    install(CORS) {
        if (cfg.corsHosts.isEmpty()) anyHost() else cfg.corsHosts.forEach { allowHost(it.substringAfter("://"), schemes = listOf(it.substringBefore("://", "https"))) }
        allowHeader(HttpHeaders.Authorization)
        allowHeader(HttpHeaders.ContentType)
        allowMethod(HttpMethod.Put); allowMethod(HttpMethod.Patch); allowMethod(HttpMethod.Delete)
    }
    install(StatusPages) {
        exception<BadRequest> { call, e -> call.respond(HttpStatusCode.BadRequest, ErrorDto(e.message ?: "Bad request")) }
        exception<Unauthorized> { call, e -> call.respond(HttpStatusCode.Unauthorized, ErrorDto(e.message!!)) }
        exception<NotFound> { call, e -> call.respond(HttpStatusCode.NotFound, ErrorDto(e.message ?: "Not found")) }
        exception<SerializationException> { call, e -> call.respond(HttpStatusCode.BadRequest, ErrorDto("Invalid body: ${e.message}")) }
        exception<io.ktor.server.plugins.BadRequestException> { call, e -> call.respond(HttpStatusCode.BadRequest, ErrorDto(e.cause?.message ?: e.message ?: "Bad request")) }
        exception<java.time.format.DateTimeParseException> { call, e -> call.respond(HttpStatusCode.BadRequest, ErrorDto("Bad date: ${e.parsedString}")) }
        exception<Throwable> { call, e ->
            call.application.environment.log.error("Unhandled", e)
            call.respond(HttpStatusCode.InternalServerError, ErrorDto("Something went wrong"))
        }
    }
    configureAuth(cfg)
    routing {
        get("/health") { call.respondText("ok") }
        apiRoutes(cfg) { LocalDate.now(clock) }
    }
}
