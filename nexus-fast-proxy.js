// nexus-fast-proxy.js — Local proxy that only touches Nexus CDN downloads
// Routes through parallel connections. Everything else passes through untouched.
// Usage: node nexus-fast-proxy.js [port]

const http = require('http');
const https = require('https');
const url = require('url');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = parseInt(process.argv[2]) || 8888;
const TMP = os.tmpdir();
const CHUNKS = 12;
const UA = 'Vortex/1.0';

function isNexusCDN(u) {
    try {
        const h = new URL(u).hostname;
        return h.includes('nexusmods.com') && (u.includes('/cdn/') || u.includes('filedelivery'));
    } catch (_) { return false; }
}

function downloadChunk(targetUrl, start, end, id) {
    return new Promise((resolve, reject) => {
        const parsed = new URL(targetUrl);
        const transport = parsed.protocol === 'https:' ? https : http;
        const opts = {
            hostname: parsed.hostname,
            port: parsed.port,
            path: parsed.pathname + parsed.search,
            method: 'GET',
            headers: {
                'User-Agent': UA,
                'Range': `bytes=${start}-${end}`,
                'Accept-Encoding': 'identity'
            },
            timeout: 30000
        };

        const req = transport.request(opts, (res) => {
            const chunks = [];
            res.on('data', (c) => chunks.push(c));
            res.on('end', () => {
                const data = Buffer.concat(chunks);
                if (res.statusCode === 206) {
                    resolve({ data, ranged: true });
                } else if (res.statusCode === 200 || res.statusCode === 302 || res.statusCode === 301) {
                    // Server doesn't support Range — got full file (or redirect)
                    resolve({ data, ranged: false });
                } else {
                    reject(new Error(`HTTP ${res.statusCode}`));
                }
            });
            res.on('error', reject);
        });
        req.on('error', reject);
        req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
        req.end();
    });
}

async function downloadWithChunks(targetUrl, totalSize, res) {
    const chunkSize = Math.ceil(totalSize / CHUNKS);
    const jobs = [];

    for (let i = 0; i < CHUNKS; i++) {
        const start = i * chunkSize;
        const end = (i === CHUNKS - 1) ? totalSize - 1 : start + chunkSize - 1;
        jobs.push(downloadChunk(targetUrl, start, end, i));
    }

    const results = await Promise.allSettled(jobs);
    const ranged = results.filter(r => r.status === 'fulfilled' && r.value.ranged);

    if (ranged.length < 2) {
        // Range not supported — pass through normally
        console.log('[proxy] Range not supported, passing through');
        return false;
    }

    // Reassemble from ranged chunks
    console.log(`[proxy] ${ranged.length}/${CHUNKS} chunks via Range, reassembling...`);
    const parts = new Array(CHUNKS);
    for (let i = 0; i < results.length; i++) {
        if (results[i].status === 'fulfilled' && results[i].value.ranged) {
            parts[i] = results[i].value.data;
        }
    }

    // Fill gaps by re-downloading individual chunks
    for (let i = 0; i < CHUNKS; i++) {
        if (!parts[i]) {
            const start = i * chunkSize;
            const end = (i === CHUNKS - 1) ? totalSize - 1 : start + chunkSize - 1;
            try {
                const r = await downloadChunk(targetUrl, start, end, i);
                parts[i] = r.data;
            } catch (e) {
                console.error(`[proxy] Chunk ${i} failed: ${e.message}`);
                return false;
            }
        }
    }

    const full = Buffer.concat(parts);
    res.writeHead(200, {
        'Content-Type': 'application/octet-stream',
        'Content-Length': full.length
    });
    res.end(full);
    return true;
}

function passThrough(req, res) {
    const targetUrl = req.url;
    const parsed = new URL(targetUrl);
    const transport = parsed.protocol === 'https:' ? https : http;

    const opts = {
        hostname: parsed.hostname,
        port: parsed.port,
        path: parsed.pathname + parsed.search,
        method: req.method,
        headers: { ...req.headers, 'Accept-Encoding': 'identity' }
    };

    const upstream = transport.request(opts, (upRes) => {
        res.writeHead(upRes.statusCode, upRes.headers);
        upRes.pipe(res);
    });
    upstream.on('error', (e) => {
        if (!res.headersSent) { res.writeHead(502); }
        res.end('Upstream error: ' + e.message);
    });
    req.pipe(upstream);
}

const server = http.createServer(async (req, res) => {
    const targetUrl = req.url;

    if (!targetUrl || targetUrl === '/' || targetUrl === '/favicon.ico') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('nexus-fast-proxy');
        return;
    }

    if (!isNexusCDN(targetUrl)) {
        passThrough(req, res);
        return;
    }

    console.log('[proxy] Nexus CDN: ' + targetUrl.slice(0, 120) + '...');

    // HEAD to get file size
    try {
        const parsed = new URL(targetUrl);
        const transport = parsed.protocol === 'https:' ? https : http;
        const headResult = await new Promise((resolve, reject) => {
            const r = transport.request({
                hostname: parsed.hostname,
                port: parsed.port,
                path: parsed.pathname + parsed.search,
                method: 'HEAD',
                headers: { 'User-Agent': UA },
                timeout: 10000
            }, (hr) => {
                const len = parseInt(hr.headers['content-length'] || '0');
                resolve({ size: len, status: hr.statusCode });
            });
            r.on('error', reject);
            r.on('timeout', () => { r.destroy(); reject(new Error('timeout')); });
            r.end();
        });

        if (headResult.size > 1048576) { // Only chunk files > 1MB
            const ok = await downloadWithChunks(targetUrl, headResult.size, res);
            if (ok) return;
        }
    } catch (e) {
        console.log('[proxy] HEAD failed: ' + e.message);
    }

    // Fall through to pass-through
    passThrough(req, res);
});

server.listen(PORT, '127.0.0.1', () => {
    console.log('[proxy] 127.0.0.1:' + PORT);
    console.log('[proxy] Nexus CDN -> ' + CHUNKS + ' parallel chunks');
    console.log('[proxy] Everything else -> pass-through');
});
