package com.vido.food

import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.InetSocketAddress
import java.net.Socket

/// Cash-drawer bridge — opens a drawer via a vendor Android intent (built-in POS
/// drawers) or an ESC/POS pulse over network/USB to a receipt printer.
/// Mirrors the React CashDrawerPlugin.java.
class CashDrawerChannel(messenger: BinaryMessenger, private val context: Context) {
    private val ui = Handler(Looper.getMainLooper())

    private val commonActions = arrayOf(
        "com.android.CASH_DRAWER.OPEN", "com.pos.OPEN_CASH_DRAWER", "com.pos.cashdrawer.OPEN",
        "com.pos.printer.OPEN_CASH_DRAWER", "com.smartpos.cashdrawer.OPEN", "com.android.pos.OPEN_CASH_DRAWER",
        "com.android.action.CASH_DRAWER_OPEN", "com.sunmi.cashdrawer.OPEN",
        "woyou.aidlservice.jiuiv5.OPEN_CASH_DRAWER", "com.iposprinter.iposprinterservice.CASHBOX_OPEN",
        "net.nyx.printerservice.CASH_DRAWER", "com.vanstone.trans.api.CASH_DRAWER",
        "com.hoin.posprinter.OPEN_CASH_DRAWER", "com.gprinter.command.OPEN_CASH_DRAWER",
        "android.intent.action.OPEN_CASH_DRAWER"
    )

    init {
        MethodChannel(messenger, "vido/cashdrawer").setMethodCallHandler { call, result ->
            when (call.method) {
                "openCashDrawer" -> open(call.argument("mode") ?: "android_intent",
                    call.argument("printerHost"), call.argument("printerPort") ?: 9100,
                    call.argument("pulsePin") ?: 0, call.argument("pulseOnMs") ?: 25,
                    call.argument("pulseOffMs") ?: 250, call.argument("customIntentAction"),
                    call.argument("usbVendorId") ?: 0, call.argument("usbProductId") ?: 0, result)
                "listUsbDevices" -> result.success(mapOf("devices" to listUsb()))
                else -> result.notImplemented()
            }
        }
    }

    private fun open(mode: String, host: String?, port: Int, pin: Int, onMs: Int, offMs: Int,
                     customAction: String?, vid: Int, pid: Int, result: MethodChannel.Result) {
        when (mode) {
            "network_escpos" -> Thread {
                try {
                    Socket().use { s ->
                        s.connect(InetSocketAddress(host, port), 5000)
                        s.tcpNoDelay = true
                        s.getOutputStream().apply { write(pulse(pin, onMs, offMs)); flush() }
                    }
                    reply(result, mapOf("ok" to true, "mode" to "network_escpos"))
                } catch (e: Exception) { err(result, e) }
            }.start()
            "usb_escpos" -> Thread {
                try { reply(result, usbPulse(vid, pid, pin, onMs, offMs)) } catch (e: Exception) { err(result, e) }
            }.start()
            else -> try {
                var sent = 0
                if (!customAction.isNullOrBlank()) { broadcast(customAction.trim()); sent++ }
                for (a in commonActions) { broadcast(a); sent++ }
                reply(result, mapOf("ok" to true, "mode" to "android_intent", "broadcastsSent" to sent))
            } catch (e: Exception) { err(result, e) }
        }
    }

    private fun pulse(pin: Int, onMs: Int, offMs: Int): ByteArray = byteArrayOf(
        0x1B, 0x70, (if (pin == 1) 1 else 0).toByte(),
        maxOf(1, minOf(255, onMs / 2)).toByte(), maxOf(1, minOf(255, offMs / 2)).toByte())

    private fun broadcast(action: String) {
        context.sendBroadcast(Intent(action).setPackage(context.packageName))
        context.sendBroadcast(Intent(action))
    }

    private fun usbManager() = context.getSystemService(Context.USB_SERVICE) as UsbManager

    private fun listUsb(): List<Map<String, Any?>> {
        val m = usbManager()
        return m.deviceList.values.map { d ->
            mapOf("deviceName" to d.deviceName, "vendorId" to d.vendorId, "productId" to d.productId,
                "productName" to (d.productName ?: ""), "hasPermission" to m.hasPermission(d))
        }
    }

    private fun usbPulse(vid: Int, pid: Int, pin: Int, onMs: Int, offMs: Int): Map<String, Any?> {
        val m = usbManager()
        val device = findPrinter(m, vid, pid) ?: throw Exception("No USB printer found")
        if (!m.hasPermission(device)) throw Exception("USB permission needed — approve on the device, then retry")
        val iface = findBulkOutInterface(device) ?: throw Exception("USB output interface not found")
        val ep = findBulkOutEndpoint(iface) ?: throw Exception("USB output endpoint not found")
        var conn: UsbDeviceConnection? = null
        try {
            conn = m.openDevice(device) ?: throw Exception("Could not open USB printer")
            if (!conn.claimInterface(iface, true)) throw Exception("Could not claim USB interface")
            val data = pulse(pin, onMs, offMs)
            val sent = conn.bulkTransfer(ep, data, data.size, 3000)
            conn.releaseInterface(iface)
            if (sent < data.size) throw Exception("USB pulse not fully sent")
            return mapOf("ok" to true, "mode" to "usb_escpos", "deviceName" to device.deviceName)
        } finally { conn?.close() }
    }

    private fun findPrinter(m: UsbManager, vid: Int, pid: Int): UsbDevice? {
        var firstBulk: UsbDevice? = null
        for (d in m.deviceList.values) {
            if (vid > 0 && d.vendorId != vid) continue
            if (pid > 0 && d.productId != pid) continue
            for (i in 0 until d.interfaceCount) {
                if (findBulkOutEndpoint(d.getInterface(i)) != null) return d
            }
            if (firstBulk == null) firstBulk = d
        }
        return firstBulk
    }

    private fun findBulkOutInterface(d: UsbDevice): UsbInterface? {
        for (i in 0 until d.interfaceCount) {
            val iface = d.getInterface(i)
            if (findBulkOutEndpoint(iface) != null) return iface
        }
        return null
    }

    private fun findBulkOutEndpoint(iface: UsbInterface): UsbEndpoint? {
        for (e in 0 until iface.endpointCount) {
            val ep = iface.getEndpoint(e)
            if (ep.direction == UsbConstants.USB_DIR_OUT && ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) return ep
        }
        return null
    }

    private fun reply(result: MethodChannel.Result, value: Any?) = ui.post { result.success(value) }
    private fun err(result: MethodChannel.Result, e: Exception) = ui.post { result.error("cashdrawer", e.message ?: e.toString(), null) }
}
