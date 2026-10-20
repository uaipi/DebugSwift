package debug.swift.android

import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.ConcurrentHashMap

/** Wrap an existing OkHttp listener to record WebSocket lifecycle and frames. */
class DebugSwiftWebSocketListener(
    private val url: String,
    private val delegate: WebSocketListener = object : WebSocketListener() {}
) : WebSocketListener() {
    private val observedSockets = ConcurrentHashMap<WebSocket, DebugSwiftObservedWebSocket>()

    private fun observed(webSocket: WebSocket): DebugSwiftObservedWebSocket =
        observedSockets.computeIfAbsent(webSocket) { DebugSwiftObservedWebSocket(url, it) }

    fun sendText(webSocket: WebSocket, text: String): Boolean {
        if (webSocket is DebugSwiftObservedWebSocket) return webSocket.send(text)
        val sent = webSocket.send(text)
        if (sent) AndroidDebugTools.recordWebSocketFrame(webSocket, url, "Sent", "Text", text.toByteArray(Charsets.UTF_8))
        return sent
    }

    fun sendBinary(webSocket: WebSocket, bytes: okio.ByteString): Boolean {
        if (webSocket is DebugSwiftObservedWebSocket) return webSocket.send(bytes)
        val sent = webSocket.send(bytes)
        if (sent) AndroidDebugTools.recordWebSocketFrame(webSocket, url, "Sent", "Binary", bytes.toByteArray())
        return sent
    }

    override fun onOpen(webSocket: WebSocket, response: Response) {
        AndroidDebugTools.webSocketOpened(webSocket, url, response.code)
        delegate.onOpen(observed(webSocket), response)
    }

    override fun onMessage(webSocket: WebSocket, text: String) {
        AndroidDebugTools.recordWebSocketFrame(webSocket, url, "Received", "Text", text.toByteArray(Charsets.UTF_8))
        delegate.onMessage(observed(webSocket), text)
    }

    override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) {
        AndroidDebugTools.recordWebSocketFrame(webSocket, url, "Received", "Binary", bytes.toByteArray())
        delegate.onMessage(observed(webSocket), bytes)
    }

    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        AndroidDebugTools.webSocketClosing(webSocket, url, code, reason)
        delegate.onClosing(observed(webSocket), code, reason)
    }

    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        AndroidDebugTools.webSocketClosed(webSocket, url, code, reason)
        delegate.onClosed(observed(webSocket), code, reason)
        observedSockets.remove(webSocket)
    }

    override fun onFailure(webSocket: WebSocket, error: Throwable, response: Response?) {
        AndroidDebugTools.webSocketFailed(webSocket, url, error.message ?: error.javaClass.simpleName, response?.code)
        delegate.onFailure(observed(webSocket), error, response)
        observedSockets.remove(webSocket)
    }
}

/** Pass this WebSocket from DebugSwiftWebSocketListener callbacks and outgoing calls are captured automatically. */
class DebugSwiftObservedWebSocket internal constructor(
    private val url: String,
    private val delegate: WebSocket
) : WebSocket {
    override fun request(): Request = delegate.request()

    override fun queueSize(): Long = delegate.queueSize()

    override fun send(text: String): Boolean {
        val sent = delegate.send(text)
        if (sent) AndroidDebugTools.recordWebSocketFrame(delegate, url, "Sent", "Text", text.toByteArray(Charsets.UTF_8))
        return sent
    }

    override fun send(bytes: okio.ByteString): Boolean {
        val sent = delegate.send(bytes)
        if (sent) AndroidDebugTools.recordWebSocketFrame(delegate, url, "Sent", "Binary", bytes.toByteArray())
        return sent
    }

    override fun close(code: Int, reason: String?): Boolean = delegate.close(code, reason)

    override fun cancel() = delegate.cancel()
}
