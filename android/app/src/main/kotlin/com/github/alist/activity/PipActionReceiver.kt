package com.github.alist.activity

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * BroadcastReceiver for handling Picture-in-Picture action button clicks.
 * 
 * This receiver is dynamically registered in PlayerActivity when PiP mode is entered,
 * and unregistered when PiP mode is exited. It delegates the actual playback control
 * back to PlayerActivity via a callback.
 */
class PipActionReceiver : BroadcastReceiver() {
    
    // Callback to be invoked when a PiP action is received
    var onAction: ((Int) -> Unit)? = null

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        
        if (intent.action == PlayerActivity.ACTION_PIP) {
            val requestCode = intent.getIntExtra("request_code", -1)
            onAction?.invoke(requestCode)
        }
    }
}
