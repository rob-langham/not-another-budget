package app.longview.auth

import app.longview.AppConfig
import app.longview.db.Users
import app.longview.db.seedCategories
import app.longview.db.tx
import com.auth0.jwk.JwkProviderBuilder
import io.ktor.http.auth.parseAuthorizationHeader
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.auth.principal
import org.jetbrains.exposed.sql.insertAndGetId
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.update
import java.security.SecureRandom
import java.time.Instant
import java.util.concurrent.TimeUnit

const val AUTH = "auth0"
private const val DEV_PREFIX = "dev:"

/**
 * Validates Auth0 access tokens (RS256, checked against the tenant's JWKS).
 * Social logins (Google, Apple, GitHub...) are configured as Auth0 connections, so the API
 * sees one kind of token whichever provider the person used.
 */
fun Application.configureAuth(cfg: AppConfig) {
    install(Authentication) {
        jwt(AUTH) {
            // In dev mode, "Bearer dev:<name>" tokens are hidden from the JWT check (treated as no
            // credentials); routes are then authenticated as optional and currentUser() accepts them.
            authHeader { call ->
                val raw = call.request.headers["Authorization"] ?: return@authHeader null
                if (cfg.devAuth && raw.removePrefix("Bearer ").trim().startsWith(DEV_PREFIX)) return@authHeader null
                try { parseAuthorizationHeader(raw) } catch (_: Exception) { null }
            }
            val domain = cfg.auth0Domain
            if (domain != null) {
                val issuer = "https://$domain/"
                val jwks = JwkProviderBuilder(issuer)
                    .cached(10, 24, TimeUnit.HOURS)
                    .rateLimited(10, 1, TimeUnit.MINUTES)
                    .build()
                verifier(jwks, issuer) {
                    withAudience(cfg.auth0Audience)
                    acceptLeeway(10)
                }
            } else {
                // Dev-only: a verifier that rejects every real JWT.
                verifier(com.auth0.jwt.JWT.require(com.auth0.jwt.algorithms.Algorithm.HMAC256(randomToken())).build())
            }
            validate { cred ->
                if (cred.payload.subject.isNullOrBlank()) null else JWTPrincipal(cred.payload)
            }
        }
    }
}

data class CurrentUser(val id: Long, val sub: String)

/** Resolves (and on first sight creates) the local user for the request. */
fun ApplicationCall.currentUser(cfg: AppConfig): CurrentUser? {
    val principal = principal<JWTPrincipal>()
    val sub: String
    val email: String?
    val name: String?
    if (principal != null) {
        sub = principal.payload.subject
        // Auth0 puts profile details in the ID token; add them to the access token with an Action if you want them here.
        email = principal.payload.getClaim("email").asString()
        name = principal.payload.getClaim("name").asString()
    } else if (cfg.devAuth) {
        val h = request.headers["Authorization"] ?: return null
        val token = h.removePrefix("Bearer ").trim()
        if (!token.startsWith(DEV_PREFIX)) return null
        sub = "dev|" + token.removePrefix(DEV_PREFIX)
        email = null
        name = token.removePrefix(DEV_PREFIX)
    } else return null
    return CurrentUser(findOrCreateUser(sub, email, name), sub)
}

fun findOrCreateUser(sub: String, email: String?, name: String?): Long = tx {
    val row = Users.selectAll().where { Users.auth0Sub eq sub }.singleOrNull()
    if (row != null) {
        val id = row[Users.id].value
        if ((email != null && row[Users.email] != email) || (name != null && row[Users.name] != name)) {
            Users.update({ Users.id eq id }) {
                if (email != null) it[Users.email] = email
                if (name != null) it[Users.name] = name
            }
        }
        id
    } else {
        val id = Users.insertAndGetId {
            it[auth0Sub] = sub
            it[Users.email] = email
            it[Users.name] = name
            it[receiptToken] = randomToken(10)
            it[createdAt] = Instant.now().toString()
        }.value
        seedCategories(id)
        id
    }
}

private val rng = SecureRandom()
fun randomToken(len: Int = 32): String {
    val alphabet = "abcdefghijkmnpqrstuvwxyz23456789"
    return (1..len).map { alphabet[rng.nextInt(alphabet.length)] }.joinToString("")
}
