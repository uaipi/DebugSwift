package debug.swift.android

import android.graphics.Bitmap
import android.net.http.SslError
import android.webkit.SslErrorHandler
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient

/** WebViewClient decorator that records navigation while forwarding to the host client. */
class DebugSwiftWebViewClient(
    private val delegate: WebViewClient? = null
) : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        record(request.url.toString())
        return delegate?.shouldOverrideUrlLoading(view, request) ?: false
    }

    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
        record(request.url.toString())
        return delegate?.shouldInterceptRequest(view, request)
    }

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
        record(url)
        delegate?.onPageStarted(view, url, favicon)
    }

    override fun onPageFinished(view: WebView, url: String) {
        record(url)
        delegate?.onPageFinished(view, url)
    }

    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
        AndroidDebugTools.log("WebView TLS error at ${error.url}: ${error.primaryError}", android.util.Log.WARN)
        delegate?.onReceivedSslError(view, handler, error) ?: handler.cancel()
    }

    private fun record(url: String) {
        val host = runCatching { android.net.Uri.parse(url).host }.getOrNull().orEmpty()
        AndroidDebugTools.recordWebViewHost(host)
        AndroidDebugTools.recordNetwork(
            "WEBVIEW", url, 0, 0L, 0L, 0L, "", "",
            "WebView resource timing is not exposed by WebViewClient",
            requestHeaders = emptyMap(), source = "webview"
        )
    }
}
