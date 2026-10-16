package debug.swift.android

import android.os.SystemClock
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import java.io.IOException
import java.io.InterruptedIOException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLHandshakeException

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

        val delay = AndroidDebugTools.requestDelay(url, request.method)
        if (delay > 0) Thread.sleep(delay)

        if (AndroidDebugTools.shouldBlock(url)) {
            val responseBody = "Blocked by DebugSwift network rules."
            val response = syntheticResponse(chain, 403, responseBody)
            record(request, 403, start, requestBytes, responseBody, requestBody, "Request blocked by an active network rule")
            return response
        }
        val injectedFailure = AndroidDebugTools.consumeNetworkFailure(url, request.method)
        if (injectedFailure?.failureType == "httpError") {
            val injectedStatus = injectedFailure.statusCode ?: 500
            val body = """{"error":"Injected HTTP Error","statusCode":$injectedStatus,"message":"This is a simulated HTTP $injectedStatus error for testing purposes.","injected":true}"""
            val response = syntheticResponse(chain, injectedStatus, body)
            record(request, injectedStatus, start, requestBytes, body, requestBody)
            return response
        }
        if (injectedFailure != null) {
            val failure = networkIOException(injectedFailure)
            AndroidDebugTools.recordNetwork(request.method, url, 0, SystemClock.elapsedRealtime() - start, requestBytes, 0, requestBody, "", failure.message ?: "network error", request.headers.toMultimap())
            throw failure
        }

        val rewriteRule = AndroidDebugTools.matchingNetworkRewriteRule(url, request.method)
        if (rewriteRule != null && AndroidDebugTools.shouldShortCircuitResponseRewrite()) {
            val status = rewriteRule.responseStatusCode ?: 200
            val body = rewriteRule.responseBody
            val response = syntheticResponse(chain, status, body)
            record(request, status, start, requestBytes, body, requestBody)
            return response
        }

        val response = try {
            chain.proceed(request)
        } catch (error: IOException) {
            AndroidDebugTools.recordNetwork(request.method, url, 0, SystemClock.elapsedRealtime() - start, requestBytes, 0, requestBody, "", error.message ?: "network error", request.headers.toMultimap())
            throw error
        }
        val originalText = runCatching { response.peekBody(1_000_000).string() }.getOrDefault("")
        val rewrittenText = rewriteRule?.responseBody ?: originalText
        val finalResponse = if (rewriteRule != null) {
            val builder = response.newBuilder()
                .header("Content-Length", rewrittenText.toByteArray().size.toString())
                .body(rewrittenText.toResponseBody(response.body?.contentType() ?: "application/json".toMediaTypeOrNull()))
            rewriteRule.responseStatusCode?.let { status -> builder.code(status).message("Rewritten by DebugSwift") }
            builder.build()
        } else response
        AndroidDebugTools.recordNetwork(
            request.method,
            url,
            finalResponse.code,
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
        .header("Content-Type", "application/json")
        .body(body.toResponseBody("application/json".toMediaTypeOrNull()))
        .build()

    private fun networkIOException(failure: AndroidDebugTools.NetworkFailure): IOException = when (failure.failureType) {
        "timeout" -> SocketTimeoutException("The request timed out.")
        "connectionLost" -> SocketException("The network connection was lost.")
        "notConnectedToInternet" -> UnknownHostException("The Internet connection appears to be offline.")
        "cannotFindHost" -> UnknownHostException("A server with the specified hostname could not be found.")
        "dnsLookupFailed" -> UnknownHostException("The DNS lookup failed.")
        "sslError" -> SSLHandshakeException("A secure connection could not be established.")
        "cancelled" -> InterruptedIOException("The request was cancelled.")
        "custom" -> IOException("${failure.customDomain} (${failure.customCode}): ${failure.customDescription}")
        else -> IOException("Failure injected by DebugSwift.")
    }
}
