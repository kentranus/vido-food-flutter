package com.vido.food

import android.app.Presentation
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Customer-facing second screen (order summary + total) on an attached display.
/// Mirrors the React CustomerDisplayPlugin.java (Android Presentation + WebView).
class CustomerDisplayChannel(messenger: BinaryMessenger, private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private var presentation: CustomerPresentation? = null
    private var lastJson = "{\"state\":\"idle\"}"

    init {
        MethodChannel(messenger, "vido/customerdisplay").setMethodCallHandler { call, result ->
            when (call.method) {
                "listDisplays" -> result.success(mapOf("displays" to listDisplays()))
                "isShowing" -> result.success(mapOf("showing" to (presentation?.isShowing == true)))
                "show" -> main.post {
                    try {
                        val target = findTarget(call.argument("displayId"))
                            ?: return@post result.error("display", "No secondary display available", null)
                        presentation?.dismiss()
                        presentation = CustomerPresentation(context, target).also { it.show(); it.pushState(lastJson) }
                        result.success(mapOf("ok" to true, "displayId" to target.displayId))
                    } catch (e: Exception) { result.error("display", e.message, null) }
                }
                "hide" -> main.post {
                    presentation?.dismiss(); presentation = null
                    result.success(mapOf("ok" to true))
                }
                "update" -> {
                    val json = call.argument<String>("json") ?: "{}"
                    lastJson = json
                    main.post {
                        presentation?.pushState(json)
                        result.success(mapOf("ok" to true, "delivered" to (presentation != null)))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun dm() = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    private fun findTarget(requestedId: Int?): Display? {
        val displays = dm().displays
        if (requestedId != null) {
            displays.firstOrNull { it.displayId == requestedId && it.displayId != Display.DEFAULT_DISPLAY }?.let { return it }
        }
        dm().getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION).firstOrNull()?.let { return it }
        return displays.firstOrNull { it.displayId != Display.DEFAULT_DISPLAY }
    }

    private fun listDisplays(): List<Map<String, Any?>> {
        val presentationIds = dm().getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION).map { it.displayId }.toSet()
        return dm().displays.map { d ->
            mapOf("id" to d.displayId, "name" to (d.name ?: "Display ${d.displayId}"),
                "isPrimary" to (d.displayId == Display.DEFAULT_DISPLAY),
                "isPresentation" to presentationIds.contains(d.displayId))
        }
    }

    private class CustomerPresentation(context: Context, display: Display) : Presentation(context, display) {
        private var webView: WebView? = null
        private var ready = false
        private var queued: String? = null

        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            window?.apply {
                setBackgroundDrawable(ColorDrawable(Color.parseColor("#101318")))
                addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setDecorFitsSystemWindows(false)
                } else {
                    @Suppress("DEPRECATION")
                    decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_FULLSCREEN
                            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY)
                }
            }
            webView = WebView(context).apply {
                setBackgroundColor(Color.parseColor("#101318"))
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, url: String?) {
                        ready = true
                        queued?.let { pushState(it); queued = null }
                    }
                }
                loadDataWithBaseURL(null, html(), "text/html", "utf-8", null)
            }
            setContentView(webView!!)
        }

        fun pushState(json: String) {
            if (!ready) { queued = json; return }
            val literal = json.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\r", "")
            webView?.post { webView?.evaluateJavascript("window.updateDisplay('$literal')", null) }
        }

        override fun dismiss() {
            try { webView?.destroy() } catch (_: Exception) {}
            super.dismiss()
        }

        private fun html(): String =
            "<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'/>" +
            "<style>body{margin:0;background:#101318;color:#f8fafc;font-family:Arial,sans-serif;height:100vh;overflow:hidden}" +
            ".wrap{height:100vh;padding:42px;box-sizing:border-box;display:flex;flex-direction:column}.brand{font-size:34px;font-weight:900;color:#facc15}" +
            ".state{font-size:18px;color:#9ca3af;text-transform:uppercase;font-weight:800;margin-top:4px}.items{flex:1;margin-top:30px;overflow:hidden}" +
            ".item{display:grid;grid-template-columns:1fr 72px 120px;gap:18px;padding:18px 0;border-bottom:1px solid #2b313a;font-size:28px;font-weight:800}" +
            ".detail{font-size:16px;color:#9ca3af;margin-top:5px}.total{border-top:3px solid #facc15;padding-top:24px;font-size:56px;font-weight:900;display:flex;justify-content:space-between}" +
            ".sub{font-size:22px;color:#d1d5db;display:flex;justify-content:space-between;margin:8px 0}.center{flex:1;display:flex;align-items:center;justify-content:center;text-align:center;font-size:42px;font-weight:900}" +
            "</style></head><body><div class='wrap'><div><div class='brand' id='shop'>Vido Food</div><div class='state' id='state'>Welcome</div></div><div id='content' class='center'>Welcome</div></div>" +
            "<script>function money(n){return '\$'+Number(n||0).toFixed(2)};" +
            "window.updateDisplay=function(raw){var d=JSON.parse(raw||'{}');document.getElementById('shop').textContent=(d.shop&&d.shop.name)||'Vido Food';" +
            "var state=document.getElementById('state'),c=document.getElementById('content');" +
            "if(d.state==='payment'){state.textContent='Payment';c.className='center';c.innerHTML='<div>Total Due<br><span style=\"color:#facc15;font-size:72px\">'+money(d.total)+'</span><br><span style=\"font-size:24px;color:#9ca3af\">'+(d.method||'Payment')+'</span></div>';return;}" +
            "if(d.state==='done'){state.textContent='Paid';c.className='center';c.innerHTML='<div style=\"color:#22c55e\">Thank you!</div><div style=\"font-size:34px;margin-top:18px\">'+money(d.total)+'</div>';return;}" +
            "if(!d.items||!d.items.length){state.textContent='Welcome';c.className='center';c.textContent='Welcome';return;}" +
            "state.textContent='Order #'+(d.orderNumber||'');c.className='items';c.innerHTML=d.items.map(function(i){return '<div class=\"item\"><div>'+(i.emoji||'')+' '+i.name+'<div class=\"detail\">'+(i.details||'')+'</div></div><div>x'+i.qty+'</div><div>'+money(i.total)+'</div></div>'}).join('')" +
            "+'<div style=\"margin-top:22px\"><div class=\"sub\"><span>Subtotal</span><span>'+money(d.subtotal)+'</span></div><div class=\"sub\"><span>Tax</span><span>'+money(d.tax)+'</span></div><div class=\"total\"><span>Total</span><span>'+money(d.total)+'</span></div></div>';};" +
            "window.updateDisplay('{\"state\":\"idle\"}');</script></body></html>"
    }
}
