package app.longview

/** Everything is read from environment variables. */
data class AppConfig(
    val port: Int,
    /** Address to listen on. Defaults to this computer only, because there is no sign-in yet. */
    val host: String,
    val dbPath: String,
    val corsHosts: List<String>,
    /** Domain shown in the Amazon forwarding address, e.g. "receipts.longview.app" */
    val receiptsEmailDomain: String,
    /** Shared secret your inbound-email provider must send in the X-Webhook-Secret header. */
    val inboundEmailSecret: String?,
) {
    companion object {
        fun fromEnv(env: Map<String, String> = System.getenv()) = AppConfig(
            port = env["PORT"]?.toIntOrNull() ?: 8080,
            host = env["HOST"] ?: "127.0.0.1",
            dbPath = env["DB_PATH"] ?: "data/longview.db",
            corsHosts = env["CORS_HOSTS"]?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList(),
            receiptsEmailDomain = env["RECEIPTS_EMAIL_DOMAIN"] ?: "receipts.longview.app",
            inboundEmailSecret = env["INBOUND_EMAIL_SECRET"]?.takeIf { it.isNotBlank() },
        )
    }
}
