package com.trueasync.demo

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.trueasync.demo.databinding.ActivityMainBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    // Single-threaded dispatcher — PHP embed is not re-entrant
    private val phpDispatcher = Dispatchers.Default.limitedParallelism(1)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.phpVersion.text = "PHP ${PhpBridge.version()}"

        binding.codeInput.setText(
            """<?php
echo "Hello from PHP " . PHP_VERSION . "\n\n";
echo "Loaded extensions:\n";
foreach (get_loaded_extensions() as ${'$'}ext) {
    echo "  - ${'$'}ext\n";
}
echo "\nAsync available: " . (extension_loaded('async') ? 'YES' : 'NO') . "\n";
"""
        )

        binding.runButton.setOnClickListener { runPhp() }
    }

    private fun runPhp() {
        val code = binding.codeInput.text.toString()
        binding.runButton.isEnabled = false
        binding.output.text = "Running…"

        lifecycleScope.launch {
            val result = withContext(phpDispatcher) {
                runCatching { PhpBridge.eval(code) }
                    .getOrElse { "Error: ${it.message}" }
            }
            binding.output.text = result.ifEmpty { "(no output)" }
            binding.runButton.isEnabled = true
        }
    }
}
