package app.longview.domain

import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

/**
 * Fetches account logos server-side: a website's icon or a social profile picture.
 * Results (including misses) are cached for a day so we don't hammer the sources.
 */
object LogoFetcher {
    data class Image(val bytes: ByteArray, val contentType: String)
    private data class Entry(val image: Image?, val at: Instant)

    private val cache = ConcurrentHashMap<String, Entry>()
    private val client = HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NORMAL).connectTimeout(Duration.ofSeconds(5)).build()

    fun websiteUrl(site: String): String {
        val host = site.trim().removePrefix("https://").removePrefix("http://").substringBefore('/').lowercase()
        return "https://www.google.com/s2/favicons?sz=128&domain=$host"
    }

    fun socialUrl(handle: String) = "https://unavatar.io/" + handle.trim().removePrefix("@")

    fun fetch(url: String): Image? {
        cache[url]?.let { if (it.at.isAfter(Instant.now().minusSeconds(86_400))) return it.image }
        val img = try {
            val res = client.send(HttpRequest.newBuilder(URI(url)).timeout(Duration.ofSeconds(8)).header("User-Agent", "Longview/1.0").GET().build(), HttpResponse.BodyHandlers.ofByteArray())
            val type = res.headers().firstValue("content-type").orElse("image/png").substringBefore(';')
            if (res.statusCode() == 200 && type.startsWith("image/") && res.body().size in 1..1_000_000) Image(res.body(), type) else null
        } catch (_: Exception) { null }
        cache[url] = Entry(img, Instant.now())
        return img
    }
}
