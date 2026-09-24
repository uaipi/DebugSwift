package debug.swift.android

import android.os.SystemClock
import okhttp3.Interceptor
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import java.io.IOException

/** Add this interceptor to the host app's OkHttpClient.Builder to capture HTTP traffic. */
class DebugSwiftOkHttpInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val url = request.url.toString()
        val start = SystemClock.elapsedRealtime()
        val requestBody = runCatching {
            val buffer = Buffer()
            request.body?.writeTo(buffer)
            buffer.readUtf8(32_000)
        }.getOrDefault("")
        val requestBytes = request.body?.contentLength()?.takeIf { it >= 0 } ?: 0L

        val delay = AndroidDebugTools.requestDelay()
        if (delay > 0) Thread.sleep(delay)

        if (AndroidDebugTools.shouldBlock(url)) {
            val responseBody = "Blocked by DebugSwift network rules."
            val response = syntheticResponse(chain, 403, responseBody)
            record(request, 403, start, requestBytes, responseBody, requestBody, "Request blocked by an active network rule")
            return response
        }
        if (AndroidDebugTools.consumeFailure()) {
            val error = "Failure injected by DebugSwift."
            AndroidDebugTools.recordNetwork(request.method, url, 0, SystemClock.elapsedRealtime() - start, requestBytes, 0, requestBody, "", error)
            throw IOException(error)
        }
        val injectedStatus = AndroidDebugTools.injectedHTTPError()
        if (injectedStatus != 0) {
            val body = "HTTP $injectedStatus injected by DebugSwift."
            val response = syntheticResponse(chain, injectedStatus, body)
            record(request, injectedStatus, start, requestBytes, body, requestBody)
            return response
        }

        val response = try {
            chain.proceed(request)
        } catch (error: IOException) {
            AndroidDebugTools.recordNetwork(request.method, url, 0, SystemClock.elapsedRealtime() - start, requestBytes, 0, requestBody, "", error.message ?: "network error", request.headers.toMultimap())
            throw error
        }
        val originalText = runCatching { response.peekBody(1_000_000).string() }.getOrDefault("")
        val rewrittenText = AndroidDebugTools.rewriteResponse(url, originalText)
        val finalResponse = if (rewrittenText != originalText) {
            response.newBuilder()
                .header("Content-Length", rewrittenText.toByteArray().size.toString())
                .body(rewrittenText.toResponseBody(response.body?.contentType()))
                .build()
        } else response
        AndroidDebugTools.recordNetwork(
            request.method,
            url,
            response.code,
            SystemClock.elapsedRealtime() - start,
            requestBytes,
            rewrittenText.toByteArray().size.toLong(),
            requestBody,
            rewrittenText,
            requestHeaders = request.headers.toMultimap(),
            responseHeaders = finalResponse.headers.toMultimap()
        )
        return finalResponse
    }

    private fun record(request: okhttp3.Request, status: Int, start: Long, requestBytes: Long, body: String, requestBody: String, error: String = "") {
        AndroidDebugTools.recordNetwork(
            request.method,
            request.url.toString(),
            status,
            SystemClock.elapsedRealtime() - start,
            requestBytes,
            body.toByteArray().size.toLong(),
            requestBody,
            body,
            error,
            requestHeaders = request.headers.toMultimap()
        )
    }

    private fun syntheticResponse(chain: Interceptor.Chain, code: Int, body: String): Response = Response.Builder()
        .request(chain.request())
        .protocol(Protocol.HTTP_1_1)
        .code(code)
        .message("Injected by DebugSwift")
        .body(body.toResponseBody(null))
        .build()
}
