package com.pstream.android.pstream_android

import android.content.Context
import android.net.Uri
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.mozilla.geckoview.AllowOrDeny
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.GeckoView
import org.mozilla.geckoview.WebRequestError

class GeckoEmbedPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    creationParams: Map<String, Any?>,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val geckoView = GeckoView(context)
    private val channel = MethodChannel(messenger, "veil/gecko_embed/$viewId")
    private val initialUrl = creationParams["url"] as? String ?: "about:blank"
    private var allowedHost = Uri.parse(initialUrl).host.orEmpty().lowercase()
    private val session: GeckoSession
    private var disposed = false

    init {
        val userAgent = creationParams["userAgent"] as? String
        val settingsBuilder = GeckoSessionSettings.Builder()
            .usePrivateMode(true)
        if (!userAgent.isNullOrBlank()) {
            settingsBuilder.userAgentOverride(userAgent)
        }

        session = GeckoSession(settingsBuilder.build())
        configureDelegates()
        session.open(GeckoRuntimeManager.get(context))
        geckoView.setSession(session)
        channel.setMethodCallHandler(this)
        GeckoRuntimeManager.whenExtensionsReady {
            if (!disposed) {
                session.loadUri(initialUrl)
            }
        }
    }

    override fun getView(): View = geckoView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("disposed", "Gecko session is closed", null)
            return
        }
        when (call.method) {
            "loadUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("bad_url", "url is required", null)
                } else {
                    allowedHost = Uri.parse(url).host.orEmpty().lowercase()
                    session.loadUri(url)
                    result.success(null)
                }
            }
            "reload" -> {
                session.reload()
                result.success(null)
            }
            "evaluateJavascript" -> {
                // GeckoView intentionally exposes page scripting through
                // WebExtensions, not a WebView-style evaluateJavascript API.
                result.error(
                    "unsupported",
                    "Use a bundled Gecko WebExtension content script",
                    null,
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun configureDelegates() {
        session.navigationDelegate = object : GeckoSession.NavigationDelegate {
            override fun onNewSession(
                session: GeckoSession,
                uri: String,
            ): GeckoResult<GeckoSession>? {
                channel.invokeMethod("createWindowRefused", mapOf("url" to uri))
                return null
            }

            override fun onLoadRequest(
                session: GeckoSession,
                request: GeckoSession.NavigationDelegate.LoadRequest,
            ): GeckoResult<AllowOrDeny> {
                val requestUri = Uri.parse(request.uri)
                val host = requestUri.host.orEmpty().lowercase()
                val allowed = request.uri == "about:blank" ||
                    host == allowedHost ||
                    host.endsWith(".$allowedHost") ||
                    allowedHost.endsWith(".$host")
                if (!allowed) {
                    channel.invokeMethod(
                        "navigationBlocked",
                        mapOf("url" to request.uri),
                    )
                }
                return GeckoResult.fromValue(
                    if (allowed) AllowOrDeny.ALLOW else AllowOrDeny.DENY,
                )
            }

            override fun onLoadError(
                session: GeckoSession,
                uri: String?,
                error: WebRequestError,
            ): GeckoResult<String>? {
                channel.invokeMethod(
                    "loadError",
                    mapOf(
                        "url" to uri,
                        "category" to error.category,
                        "code" to error.code,
                    ),
                )
                return null
            }
        }

        session.permissionDelegate = object : GeckoSession.PermissionDelegate {
            override fun onContentPermissionRequest(
                session: GeckoSession,
                perm: GeckoSession.PermissionDelegate.ContentPermission,
            ): GeckoResult<Int> {
                val autoplay = perm.permission ==
                    GeckoSession.PermissionDelegate.PERMISSION_AUTOPLAY_AUDIBLE ||
                    perm.permission ==
                    GeckoSession.PermissionDelegate.PERMISSION_AUTOPLAY_INAUDIBLE
                return GeckoResult.fromValue(
                    if (autoplay) {
                        GeckoSession.PermissionDelegate.ContentPermission.VALUE_ALLOW
                    } else {
                        GeckoSession.PermissionDelegate.ContentPermission.VALUE_DENY
                    },
                )
            }
        }

        session.contentDelegate = object : GeckoSession.ContentDelegate {
            override fun onFullScreen(session: GeckoSession, fullScreen: Boolean) {
                channel.invokeMethod(
                    "fullScreenChanged",
                    mapOf("fullScreen" to fullScreen),
                )
            }
        }

        session.progressDelegate = object : GeckoSession.ProgressDelegate {
            override fun onPageStart(session: GeckoSession, url: String) {
                channel.invokeMethod("loadStart", mapOf("url" to url))
            }

            override fun onPageStop(session: GeckoSession, success: Boolean) {
                channel.invokeMethod("loadStop", mapOf("success" to success))
            }
        }
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        geckoView.releaseSession()
        session.close()
    }
}
