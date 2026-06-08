package com.vido.food

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.pax.poslink.CommSetting
import com.pax.poslink.LogSetting
import com.pax.poslink.PaymentRequest
import com.pax.poslink.PosLink
import com.pax.poslink.POSLinkAndroid
import com.pax.poslink.ProcessTransResult

/// Bridges the PAX PosLink Android SDK to Flutter over a MethodChannel.
/// Mirrors the React Capacitor PosLinkPaymentPlugin (init + sale).
class MainActivity : FlutterActivity() {
    private val channelName = "vido/pax"
    @Volatile private var initialized = false
    private val ui = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> Thread {
                    try {
                        ensureInitialized()
                        reply(result, mapOf("ok" to true, "sdk" to "POSLink Java Android"))
                    } catch (e: Exception) { error(result, e) }
                }.start()
                "sale" -> sale(call.argument("amount"), call.argument("connectionMode"),
                    call.argument("host"), call.argument("port"), call.argument("timeout"),
                    call.argument("refNum"), call.argument("tipAmount"), call.argument("extData"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun sale(amount: Double?, connectionMode: String?, host: String?, port: Int?,
                     timeout: Int?, refNum: String?, tipAmount: String?, extData: String?,
                     result: MethodChannel.Result) {
        val mode = connectionMode ?: "tcp"
        if (amount == null || amount <= 0) { result.error("bad_args", "amount required", null); return }
        if (mode.equals("tcp", true) && host.isNullOrBlank()) { result.error("bad_args", "payment terminal IP required", null); return }
        Thread {
            try {
                ensureInitialized()
                val posLink = PosLink(context)
                posLink.SetCommSetting(buildCommSetting(mode, host, port ?: 10009, timeout ?: 60000))
                val request = PaymentRequest()
                request.TenderType = request.ParseTenderType("CREDIT")
                request.TransType = request.ParseTransType("SALE")
                request.ECRRefNum = refNum ?: System.currentTimeMillis().toString()
                request.Amount = Math.round(amount * 100.0).toString()
                if (!tipAmount.isNullOrBlank()) request.TipAmt = tipAmount
                if (!extData.isNullOrBlank()) request.ExtData = extData
                posLink.PaymentRequest = request

                val res = posLink.ProcessTrans()
                val ok = res.Code == ProcessTransResult.ProcessTransResultCode.OK
                val map = HashMap<String, Any?>()
                map["ok"] = ok
                map["processCode"] = res.Code.toString()
                map["processMessage"] = res.Msg
                if (ok) {
                    val r = posLink.PaymentResponse
                    map["approved"] = r.ResultCode == "000000" || r.ResultCode == "000"
                    map["resultCode"] = r.ResultCode
                    map["resultText"] = r.ResultTxt
                    map["message"] = r.Message
                    map["authCode"] = r.AuthCode
                    map["refNum"] = r.RefNum
                    map["requestedAmount"] = r.RequestedAmount
                    map["approvedAmount"] = r.ApprovedAmount
                    map["cardType"] = r.CardType
                    map["maskedCard"] = r.BogusAccountNum
                    map["hostCode"] = r.HostCode
                    map["hostResponse"] = r.HostResponse
                    map["timestamp"] = r.Timestamp
                    map["extData"] = r.ExtData
                }
                reply(result, map)
            } catch (e: Exception) { error(result, e) }
        }.start()
    }

    @Synchronized
    private fun ensureInitialized() {
        if (initialized) return
        val dir = context.getExternalFilesDir(null)?.absolutePath ?: context.filesDir.absolutePath
        LogSetting.setLogMode(true)
        LogSetting.setLevel(LogSetting.LOGLEVEL.DEBUG)
        LogSetting.setLogFileName("POSLinkLog")
        LogSetting.setOutputPath(dir)
        LogSetting.setLogDays("30")
        POSLinkAndroid.init(context.applicationContext)
        initialized = true
    }

    private fun buildCommSetting(mode: String, host: String?, port: Int, timeout: Int): CommSetting {
        val setting = CommSetting()
        setting.setTimeOut(timeout.toString())
        if (mode.equals("usb", true)) { setting.setType(CommSetting.USB); return setting }
        setting.setType(CommSetting.TCP)
        setting.setDestIP(host)
        setting.setDestPort(port.toString())
        return setting
    }

    private fun reply(result: MethodChannel.Result, value: Any?) = ui.post { result.success(value) }
    private fun error(result: MethodChannel.Result, e: Exception) =
        ui.post { result.error("pax_error", e.message ?: e.toString(), null) }
}
