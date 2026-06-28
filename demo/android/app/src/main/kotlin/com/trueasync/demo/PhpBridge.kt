package com.trueasync.demo

object PhpBridge {
    init {
        System.loadLibrary("phpbridge")
    }

    external fun eval(code: String): String
    external fun version(): String
}
