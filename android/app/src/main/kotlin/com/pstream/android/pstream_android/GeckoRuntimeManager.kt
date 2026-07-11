package com.pstream.android.pstream_android

import android.content.Context
import android.util.Log
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings

/**
 * Process-wide Gecko runtime. GeckoRuntime is intentionally never tied to an
 * Activity; individual platform views own and close their GeckoSession.
 */
object GeckoRuntimeManager {
    private const val TAG = "VeilGecko"
    private const val UBO_LOCATION =
        "resource://android/assets/addons/ublock_origin/"
    private const val UBO_ID = "uBlock0@raymondhill.net"
    private const val EMBED_GUARD_LOCATION =
        "resource://android/assets/addons/veil_embed_guard/"
    private const val EMBED_GUARD_ID = "veil-embed-guard@pstream.android"

    @Volatile
    private var runtime: GeckoRuntime? = null
    private var pendingExtensions = 0
    private var extensionsReady = false
    private val readyCallbacks = mutableListOf<() -> Unit>()

    fun get(context: Context): GeckoRuntime {
        return runtime ?: synchronized(this) {
            runtime ?: create(context.applicationContext).also { runtime = it }
        }
    }

    @Synchronized
    fun whenExtensionsReady(callback: () -> Unit) {
        if (extensionsReady) {
            callback()
        } else {
            readyCallbacks += callback
        }
    }

    private fun create(context: Context): GeckoRuntime {
        val settings = GeckoRuntimeSettings.Builder()
            .build()
        val geckoRuntime = GeckoRuntime.create(context, settings)

        pendingExtensions = 2
        ensureBuiltIn(geckoRuntime, UBO_LOCATION, UBO_ID, "uBlock Origin")
        ensureBuiltIn(
            geckoRuntime,
            EMBED_GUARD_LOCATION,
            EMBED_GUARD_ID,
            "Veil embed guard",
        )
        return geckoRuntime
    }

    private fun ensureBuiltIn(
        runtime: GeckoRuntime,
        location: String,
        id: String,
        label: String,
    ) {
        // Built-ins are app-owned privileged extensions and do not trigger the
        // install prompt used by arbitrary downloaded extensions.
        runtime.webExtensionController.ensureBuiltIn(location, id).accept(
            { extension ->
                Log.i(
                    TAG,
                    "$label ready: ${extension?.metaData?.version ?: "unknown"}",
                )
                markExtensionReady()
            },
            { error ->
                Log.e(TAG, "Failed to install $label", error)
                markExtensionReady()
            },
        )
    }

    @Synchronized
    private fun markExtensionReady() {
        pendingExtensions -= 1
        if (pendingExtensions > 0) return
        extensionsReady = true
        val callbacks = readyCallbacks.toList()
        readyCallbacks.clear()
        callbacks.forEach { it() }
    }
}
