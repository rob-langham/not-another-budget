package app.longview

import app.longview.db.Users
import app.longview.db.seedCategories
import app.longview.db.tx
import org.jetbrains.exposed.sql.insertAndGetId
import org.jetbrains.exposed.sql.selectAll
import java.security.SecureRandom
import java.time.Instant

/**
 * There is no sign-in yet: every request acts as one built-in local user.
 * The users table is kept so that adding sign-in later only means choosing which user a request belongs to.
 */
object LocalUser {
    private const val SUB = "local"
    @Volatile private var cached: Long? = null

    fun id(): Long = cached ?: findOrCreate(SUB).also { cached = it }

    /** Forget the cached id (tests recreate the database). */
    fun reset() { cached = null }

    fun findOrCreate(sub: String): Long = tx {
        Users.selectAll().where { Users.auth0Sub eq sub }.singleOrNull()?.get(Users.id)?.value
            ?: Users.insertAndGetId {
                it[auth0Sub] = sub
                it[name] = "You"
                it[receiptToken] = randomToken(10)
                it[createdAt] = Instant.now().toString()
            }.value.also(::seedCategories)
    }
}

private val rng = SecureRandom()
fun randomToken(len: Int = 32): String {
    val alphabet = "abcdefghijkmnpqrstuvwxyz23456789"
    return (1..len).map { alphabet[rng.nextInt(alphabet.length)] }.joinToString("")
}
