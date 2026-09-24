package debug.swift.android

import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

/** Wrap an existing OkHttp listener to record WebSocket lifecycle and frames. */
class DebugSwiftWebSocketListener(
    private val url: String,
    private val delegate: WebSocketListener = object : WebSocketListener() {}
) : WebSocketListener() {
    fun sendText(webSocket: WebSocket, text: String): Boolean {
        AndroidDebugTools.recordWebSocket(url, "sent", text)
        return webSocket.send(text)
    }

    fun sendBinary(webSocket: WebSocket, bytes: okio.ByteString): Boolean {
        AndroidDebugTools.recordWebSocket(url, "sent binary", "${bytes.size} bytes")
        return webSocket.send(bytes)
    }

    override fun onOpen(webSocket: WebSocket, response: Response) {
        AndroidDebugTools.recordWebSocket(url, "connected", "HTTP ${response.code}")
        delegate.onOpen(webSocket, response)
    }

    override fun onMessage(webSocket: WebSocket, text: String) {
        AndroidDebugTools.recordWebSocket(url, "received", text)
        delegate.onMessage(webSocket, text)
    }

    override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) {
        AndroidDebugTools.recordWebSocket(url, "received binary", "${bytes.size} bytes")
        delegate.onMessage(webSocket, bytes)
    }

    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        AndroidDebugTools.recordWebSocket(url, "closing", "$code $reason")
        delegate.onClosing(webSocket, code, reason)
    }

    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        AndroidDebugTools.recordWebSocket(url, "closed", "$code $reason")
        delegate.onClosed(webSocket, code, reason)
    }

    override fun onFailure(webSocket: WebSocket, error: Throwable, response: Response?) {
        AndroidDebugTools.recordWebSocket(url, "failed", error.message ?: error.javaClass.simpleName)
        delegate.onFailure(webSocket, error, response)
    }
}
