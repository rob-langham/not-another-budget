package app.longview

/** Everything is read from environment variables so the same jar runs locally and in production. */
data class AppConfig(
    val port: Int,
    val dbPath: String,
    /** e.g. "your-tenant.eu.auth0.com" */
    val auth0Domain: String?,
    /** The API identifier you created in Auth0, e.g. "https://api.longview.app" */
    val auth0Audience: String?,
    /** When true, accepts "Authorization: Bearer dev:<user-id>" instead of an Auth0 token. Never enable in production. */
    val devAuth: Boolean,
    val corsHosts: List<String>,
    /** Domain shown in the Amazon forwarding address, e.g. "receipts.longview.app" */
    val receiptsEmailDomain: String,
    /** Shared secret your inbound-email provider must send in the X-Webhook-Secret header. */
    val inboundEmailSecret: String?,
) {
    companion object {
        fun fromEnv(env: Map<String, String> = System.getenv()): AppConfig {
            val cfg = AppConfig(
                port = env["PORT"]?.toIntOrNull() ?: 8080,
                dbPath = env["DB_PATH"] ?: "data/longview.db",
                auth0Domain = env["AUTH0_DOMAIN"]?.takeIf { it.isNotBlank() },
                auth0Audience = env["AUTH0_AUDIENCE"]?.takeIf { it.isNotBlank() },
                devAuth = env["DEV_AUTH"]?.toBoolean() ?: false,
                corsHosts = env["CORS_HOSTS"]?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList(),
                receiptsEmailDomain = env["RECEIPTS_EMAIL_DOMAIN"] ?: "receipts.longview.app",
                inboundEmailSecret = env["INBOUND_EMAIL_SECRET"]?.takeIf { it.isNotBlank() },
            )
            require(cfg.devAuth || (cfg.auth0Domain != null && cfg.auth0Audience != null)) {
                "Set AUTH0_DOMAIN and AUTH0_AUDIENCE (or DEV_AUTH=true for local development)."
            }
            return cfg
        }
    }
}
