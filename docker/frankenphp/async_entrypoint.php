<?php

use FrankenPHP\HttpServer;
use FrankenPHP\Request;
use FrankenPHP\Response;

set_time_limit(0);

$startTime = microtime(true);

echo "TrueAsync FrankenPHP worker started.\n";

HttpServer::onRequest(function (Request $request, Response $response) use ($startTime): void {
    $uri    = $request->getUri();
    $path   = parse_url($uri, PHP_URL_PATH) ?? '/';
    $method = $request->getMethod();

    match (true) {
        $path === '/api/info'  => handleApiInfo($request, $response, $startTime),
        $path === '/api/ping'  => handleApiPing($response),
        default                => handleIndex($response, $startTime),
    };
});

// ---------------------------------------------------------------------------

function handleApiPing(Response $response): void
{
    $response->setStatus(200);
    $response->setHeader('Content-Type', 'application/json');
    $response->write(json_encode(['pong' => true, 'ts' => microtime(true)]));
    $response->end();
}

function handleApiInfo(Request $request, Response $response, float $startTime): void
{
    $response->setStatus(200);
    $response->setHeader('Content-Type', 'application/json');
    $response->write(json_encode([
        'php'        => PHP_VERSION,
        'zts'        => ZEND_THREAD_SAFE,
        'async'      => extension_loaded('true_async'),
        'coroutines' => count(\Async\get_coroutines()),
        'memory_mb'  => round(memory_get_usage(true) / 1048576, 2),
        'uptime_s'   => round(microtime(true) - $startTime, 3),
        'method'     => $request->getMethod(),
        'uri'        => $request->getUri(),
        'headers'    => count($request->getHeaders()),
    ], JSON_PRETTY_PRINT));
    $response->end();
}

function handleIndex(Response $response, float $startTime): void
{
    $php        = PHP_VERSION;
    $zts        = ZEND_THREAD_SAFE ? 'yes' : 'no';
    $async      = extension_loaded('true_async') ? 'loaded' : 'not loaded';
    $coroutines = count(\Async\get_coroutines());
    $memory     = round(memory_get_usage(true) / 1048576, 2);
    $uptime     = round(microtime(true) - $startTime, 3);

    $html = <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>TrueAsync · FrankenPHP</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg:        #0d0f1a;
    --surface:   #141727;
    --border:    #1e2340;
    --accent:    #6c63ff;
    --accent2:   #00d4aa;
    --text:      #e2e8f0;
    --muted:     #64748b;
    --card-bg:   #161929;
    --green:     #22c55e;
    --yellow:    #eab308;
    --red:       #ef4444;
  }

  body {
    background: var(--bg);
    color: var(--text);
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  /* ── Hero ─────────────────────────────────────────────────── */
  .hero {
    width: 100%;
    padding: 64px 24px 48px;
    text-align: center;
    background: radial-gradient(ellipse 80% 60% at 50% -10%, #6c63ff22 0%, transparent 70%);
    border-bottom: 1px solid var(--border);
  }

  .logo {
    display: inline-flex;
    align-items: center;
    gap: 14px;
    margin-bottom: 20px;
  }

  .logo-icon {
    width: 52px; height: 52px;
    background: linear-gradient(135deg, var(--accent), var(--accent2));
    border-radius: 14px;
    display: flex; align-items: center; justify-content: center;
    font-size: 26px;
    box-shadow: 0 0 32px #6c63ff44;
  }

  .logo-text {
    text-align: left;
  }

  .logo-title {
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.5px;
    background: linear-gradient(90deg, var(--accent), var(--accent2));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }

  .logo-sub {
    font-size: 13px;
    color: var(--muted);
    margin-top: 2px;
  }

  .tagline {
    font-size: 15px;
    color: var(--muted);
    max-width: 520px;
    margin: 0 auto;
    line-height: 1.6;
  }

  .badge {
    display: inline-block;
    padding: 3px 10px;
    border-radius: 20px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.5px;
    text-transform: uppercase;
    margin-bottom: 14px;
    background: #6c63ff22;
    border: 1px solid #6c63ff55;
    color: var(--accent);
  }

  /* ── Main layout ──────────────────────────────────────────── */
  .main {
    width: 100%;
    max-width: 960px;
    padding: 48px 24px;
    display: flex;
    flex-direction: column;
    gap: 40px;
  }

  /* ── Section title ────────────────────────────────────────── */
  .section-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-bottom: 16px;
  }

  /* ── Stats grid ───────────────────────────────────────────── */
  .stats {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
    gap: 16px;
  }

  .stat-card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 14px;
    padding: 20px;
    transition: border-color .2s;
  }

  .stat-card:hover { border-color: var(--accent); }

  .stat-label {
    font-size: 11px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.8px;
    margin-bottom: 8px;
  }

  .stat-value {
    font-size: 22px;
    font-weight: 700;
    line-height: 1;
    color: var(--text);
  }

  .stat-value.accent  { color: var(--accent); }
  .stat-value.green   { color: var(--green); }
  .stat-value.accent2 { color: var(--accent2); }

  .stat-note {
    font-size: 12px;
    color: var(--muted);
    margin-top: 6px;
  }

  /* ── Status pill ──────────────────────────────────────────── */
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    border-radius: 20px;
    font-size: 12px;
    font-weight: 600;
  }

  .pill-green  { background: #22c55e18; border: 1px solid #22c55e44; color: var(--green); }
  .pill-purple { background: #6c63ff18; border: 1px solid #6c63ff44; color: var(--accent); }
  .pill-yellow { background: #eab30818; border: 1px solid #eab30844; color: var(--yellow); }

  .dot { width: 7px; height: 7px; border-radius: 50%; background: currentColor; }

  /* ── Endpoints ────────────────────────────────────────────── */
  .endpoints {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .endpoint {
    display: flex;
    align-items: center;
    gap: 14px;
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 14px 18px;
    text-decoration: none;
    color: var(--text);
    transition: border-color .2s, transform .1s;
  }

  .endpoint:hover { border-color: var(--accent2); transform: translateX(4px); }

  .method {
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 1px;
    padding: 3px 8px;
    border-radius: 6px;
    background: #00d4aa18;
    color: var(--accent2);
    min-width: 42px;
    text-align: center;
  }

  .ep-path   { font-size: 14px; font-family: 'Courier New', monospace; color: var(--text); }
  .ep-desc   { font-size: 12px; color: var(--muted); margin-left: auto; }

  /* ── Architecture ─────────────────────────────────────────── */
  .arch {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 14px;
    padding: 24px;
  }

  .arch-flow {
    display: flex;
    align-items: center;
    gap: 0;
    flex-wrap: wrap;
    justify-content: center;
    margin-top: 4px;
  }

  .arch-node {
    text-align: center;
    padding: 12px 20px;
  }

  .arch-node-box {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 10px 16px;
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
  }

  .arch-node-box.accent  { border-color: var(--accent);  color: var(--accent); }
  .arch-node-box.accent2 { border-color: var(--accent2); color: var(--accent2); }
  .arch-node-box.green   { border-color: var(--green);   color: var(--green); }

  .arch-node-label { font-size: 11px; color: var(--muted); margin-top: 6px; }

  .arch-arrow { color: var(--muted); font-size: 18px; padding: 0 4px; }

  /* ── Footer ───────────────────────────────────────────────── */
  footer {
    margin-top: auto;
    width: 100%;
    padding: 24px;
    text-align: center;
    border-top: 1px solid var(--border);
    font-size: 12px;
    color: var(--muted);
  }

  footer a { color: var(--accent); text-decoration: none; }
  footer a:hover { text-decoration: underline; }
</style>
</head>
<body>

<div class="hero">
  <div class="badge">Live Demo</div>
  <div class="logo">
    <div class="logo-icon">⚡</div>
    <div class="logo-text">
      <div class="logo-title">TrueAsync PHP</div>
      <div class="logo-sub">powered by FrankenPHP</div>
    </div>
  </div>
  <p class="tagline">
    Coroutine-based async runtime for PHP &mdash; real concurrency without threads,
    served by FrankenPHP's embedded Go + Caddy stack.
  </p>
</div>

<div class="main">

  <!-- Runtime stats -->
  <div>
    <div class="section-title">Runtime</div>
    <div class="stats">
      <div class="stat-card">
        <div class="stat-label">PHP Version</div>
        <div class="stat-value accent">{$php}</div>
        <div class="stat-note">ZTS: {$zts}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Async Extension</div>
        <div class="stat-value" style="font-size:16px;padding-top:4px">
          <span class="pill pill-green"><span class="dot"></span>{$async}</span>
        </div>
        <div class="stat-note">TrueAsync coroutine engine</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Active Coroutines</div>
        <div class="stat-value accent2">{$coroutines}</div>
        <div class="stat-note">this worker thread</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Memory</div>
        <div class="stat-value green">{$memory} MB</div>
        <div class="stat-note">worker resident</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Worker Uptime</div>
        <div class="stat-value">{$uptime}s</div>
        <div class="stat-note">script stays loaded</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Server</div>
        <div class="stat-value" style="font-size:14px;padding-top:6px">
          <span class="pill pill-purple"><span class="dot"></span>FrankenPHP</span>
        </div>
        <div class="stat-note">Caddy + Go + PHP embed</div>
      </div>
    </div>
  </div>

  <!-- Architecture -->
  <div>
    <div class="section-title">Request Flow</div>
    <div class="arch">
      <div class="arch-flow">
        <div class="arch-node">
          <div class="arch-node-box">HTTP Client</div>
          <div class="arch-node-label">browser / curl</div>
        </div>
        <div class="arch-arrow">→</div>
        <div class="arch-node">
          <div class="arch-node-box accent">Caddy</div>
          <div class="arch-node-label">TLS / HTTP/2</div>
        </div>
        <div class="arch-arrow">→</div>
        <div class="arch-node">
          <div class="arch-node-box accent">FrankenPHP</div>
          <div class="arch-node-label">Go dispatcher</div>
        </div>
        <div class="arch-arrow">→</div>
        <div class="arch-node">
          <div class="arch-node-box accent2">Worker queue</div>
          <div class="arch-node-label">buffer_size 20</div>
        </div>
        <div class="arch-arrow">→</div>
        <div class="arch-node">
          <div class="arch-node-box green">Coroutine</div>
          <div class="arch-node-label">TrueAsync event loop</div>
        </div>
      </div>
    </div>
  </div>

  <!-- Endpoints -->
  <div>
    <div class="section-title">Endpoints</div>
    <div class="endpoints">
      <a class="endpoint" href="/">
        <span class="method">GET</span>
        <span class="ep-path">/</span>
        <span class="ep-desc">This page</span>
      </a>
      <a class="endpoint" href="/api/info">
        <span class="method">GET</span>
        <span class="ep-path">/api/info</span>
        <span class="ep-desc">Runtime info as JSON</span>
      </a>
      <a class="endpoint" href="/api/ping">
        <span class="method">GET</span>
        <span class="ep-path">/api/ping</span>
        <span class="ep-desc">Ping / latency check</span>
      </a>
    </div>
  </div>

</div>

<footer>
  <a href="https://github.com/true-async/php-src" target="_blank">php-src</a> &nbsp;·&nbsp;
  <a href="https://github.com/true-async/frankenphp" target="_blank">frankenphp</a> &nbsp;·&nbsp;
  <a href="https://github.com/true-async/php-async" target="_blank">php-async</a>
</footer>

</body>
</html>
HTML;

    $response->setStatus(200);
    $response->setHeader('Content-Type', 'text/html; charset=utf-8');
    $response->write($html);
    $response->end();
}
