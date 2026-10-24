// memory-bridge MCP server (Streamable HTTP, no dependencies)
// Exposes exactly 3 tools over a single markdown file. No filesystem paths accepted from clients.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const PORT = Number(process.env.MB_PORT || 8787);
const HOST = process.env.MB_HOST || '127.0.0.1';
const TOKEN = process.env.MB_TOKEN || '';
const FILE = process.env.MB_FILE || path.join(os.homedir(), '.claude', 'memory-bridge', 'memory.md');
const MAX_BODY = 256 * 1024;
const SECTION_WRITABLE = ['shared-facts', 'from-claude'];

/* ---------- file model ---------- */
function readAll() {
  try { return fs.readFileSync(FILE, 'utf8'); } catch { return ''; }
}

function parse(txt) {
  const pre = [];
  const secs = [];
  let cur = null;
  for (const ln of txt.split(/\r?\n/)) {
    const m = /^##\s+(.+?)\s*$/.exec(ln);
    if (m) { cur = { name: m[1].trim(), lines: [] }; secs.push(cur); }
    else if (cur) cur.lines.push(ln);
    else pre.push(ln);
  }
  return { pre, secs };
}

function render(p) {
  const out = [...p.pre];
  for (const s of p.secs) { out.push('## ' + s.name); out.push(...s.lines); }
  return out.join('\n');
}

function writeAtomic(txt) {
  const tmp = FILE + '.tmp';
  fs.writeFileSync(tmp, txt, 'utf8');
  fs.renameSync(tmp, FILE);
}

function stamp() {
  const d = new Date();
  const z = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())} ${z(d.getHours())}:${z(d.getMinutes())}`;
}

function getSection(name) {
  const p = parse(readAll());
  const s = p.secs.find((x) => x.name === name);
  if (!s) return '';
  return s.lines.join('\n').trim();
}

// newest first: insert right under the section header
function pushSection(name, text) {
  const clean = String(text).replace(/\r/g, '').trim();
  if (!clean) throw new Error('empty text');
  const p = parse(readAll());
  let s = p.secs.find((x) => x.name === name);
  if (!s) { s = { name, lines: [''] }; p.secs.push(s); }
  const block = clean.split('\n').map((l) => l.trimEnd());
  const entry = ['- [' + stamp() + '] ' + block[0], ...block.slice(1).map((l) => '  ' + l), ''];
  // drop leading blank lines so header stays followed by newest entry
  while (s.lines.length && s.lines[0].trim() === '') s.lines.shift();
  s.lines.unshift(...entry);
  writeAtomic(render(p));
  return entry[0];
}

/* ---------- tools ---------- */
const TOOLS = [
  {
    name: 'read_memory',
    description:
      '读取共享记忆文件。section 省略时返回全文；可选 shared-facts / from-claude / from-code。' +
      'from-code 是 Claude Code 侧自动记录的近期工作进展。',
    inputSchema: {
      type: 'object',
      properties: {
        section: { type: 'string', enum: ['shared-facts', 'from-claude', 'from-code'] },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'append_memory',
    description:
      '往共享记忆追加一条（不会被 Claude Code 覆盖）。shared-facts 用于长期不变的事实与偏好，' +
      'from-claude 用于本次对话得出的结论与决定。不要写入密钥、密码、token。',
    inputSchema: {
      type: 'object',
      properties: {
        section: { type: 'string', enum: SECTION_WRITABLE },
        text: { type: 'string', description: '一条自包含的事实或结论，尽量一句话，最多 400 字' },
      },
      required: ['section', 'text'],
      additionalProperties: false,
    },
  },
  {
    name: 'search_memory',
    description: '在共享记忆里按关键词检索（不区分大小写的子串匹配），返回命中的行。',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string' },
        limit: { type: 'number', description: '最多返回多少行，默认 20' },
      },
      required: ['query'],
      additionalProperties: false,
    },
  },
];

function callTool(name, args = {}) {
  if (name === 'read_memory') {
    const sec = args.section;
    if (sec) {
      const body = getSection(sec);
      return body ? `## ${sec}\n${body}` : `## ${sec}\n(空)`;
    }
    const txt = readAll();
    return txt.length > 12000 ? txt.slice(0, 12000) + '\n...(已截断)' : txt || '(空)';
  }
  if (name === 'append_memory') {
    const sec = String(args.section || '');
    if (!SECTION_WRITABLE.includes(sec)) throw new Error('section must be one of: ' + SECTION_WRITABLE.join(', '));
    const text = String(args.text || '');
    if (!text.trim()) throw new Error('text is empty');
    if (text.length > 2000) throw new Error('text too long (max 2000)');
    const head = pushSection(sec, text);
    return '已写入 ' + sec + '：' + head;
  }
  if (name === 'search_memory') {
    const q = String(args.query || '').trim();
    if (!q) throw new Error('query is empty');
    const limit = Math.min(Math.max(Number(args.limit) || 20, 1), 100);
    const hits = [];
    for (const ln of readAll().split(/\r?\n/)) {
      if (ln.toLowerCase().includes(q.toLowerCase())) hits.push(ln.trim());
      if (hits.length >= limit) break;
    }
    return hits.length ? hits.join('\n') : '(无匹配)';
  }
  throw new Error('unknown tool: ' + name);
}

/* ---------- JSON-RPC / MCP ---------- */
const SERVER_INFO = { name: 'memory-bridge', version: '1.0.0' };
const PROTOCOLS = ['2025-06-18', '2025-03-26', '2024-11-05'];

function handle(msg) {
  const { id, method, params } = msg;
  const isNotification = id === undefined || id === null;
  const ok = (result) => ({ jsonrpc: '2.0', id, result });
  const fail = (code, message) => ({ jsonrpc: '2.0', id, error: { code, message } });

  if (method === 'initialize') {
    const wanted = params?.protocolVersion;
    return ok({
      protocolVersion: PROTOCOLS.includes(wanted) ? wanted : PROTOCOLS[0],
      capabilities: { tools: { listChanged: false } },
      serverInfo: SERVER_INFO,
      instructions:
        '这是用户本机的共享记忆：Claude Code（终端编码助手）与 claude.ai 共用一份 markdown。' +
        '需要了解用户在终端里最近做了什么时，调用 read_memory 的 from-code 段；' +
        '得出值得长期保留的结论时，用 append_memory 写入 from-claude 段。不必每次对话都调用。',
    });
  }
  if (method === 'notifications/initialized' || method === 'notifications/cancelled') return null;
  if (method === 'ping') return ok({});
  if (method === 'tools/list') return ok({ tools: TOOLS });
  if (method === 'tools/call') {
    const name = params?.name;
    try {
      const text = callTool(name, params?.arguments || {});
      return ok({ content: [{ type: 'text', text }], isError: false });
    } catch (e) {
      return ok({ content: [{ type: 'text', text: 'ERROR: ' + e.message }], isError: true });
    }
  }
  if (method === 'resources/list') return ok({ resources: [] });
  if (method === 'prompts/list') return ok({ prompts: [] });
  if (isNotification) return null;
  return fail(-32601, 'Method not found: ' + method);
}

function authorized(req, url) {
  if (!TOKEN) return true;
  const allowQuery = process.env.MB_ALLOW_QUERY !== '0';
  const q = url.searchParams.get('token');
  const h = req.headers['authorization'] || '';
  const bearer = h.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : '';
  const hdr = req.headers['x-mb-token'] || '';
  return (allowQuery && q === TOKEN) || bearer === TOKEN || hdr === TOKEN;
}

function send(res, code, obj, sse) {
  const body = JSON.stringify(obj);
  if (sse) {
    res.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
    });
    res.end('event: message\ndata: ' + body + '\n\n');
  } else {
    res.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store' });
    res.end(body);
  }
}

const RATE = new Map();

const server = http.createServer((req, res) => {
  let url;
  try { url = new URL(req.url, 'http://' + (req.headers.host || 'localhost')); } catch { res.writeHead(400).end(); return; }

  if (req.method === 'GET' && url.pathname === '/health') {
    if (!authorized(req, url)) { res.writeHead(401, { 'content-type': 'text/plain' }).end('unauthorized'); return; }
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('ok ' + (fs.existsSync(FILE) ? fs.statSync(FILE).size + 'B' : 'MISSING'));
    return;
  }
  // crude rate limit: 120 requests / minute per client
  const ip = req.socket.remoteAddress || '-';
  const now = Date.now();
  const slot = (RATE.get(ip) || []).filter((t) => now - t < 60000);
  if (slot.length >= 120) { res.writeHead(429, { 'content-type': 'text/plain' }).end('rate limited'); return; }
  slot.push(now);
  RATE.set(ip, slot);
  if (url.pathname !== '/mcp' && url.pathname !== '/') { res.writeHead(404).end(); return; }
  if (!authorized(req, url)) { res.writeHead(401, { 'content-type': 'text/plain' }).end('unauthorized'); return; }
  if (req.method !== 'POST') { res.writeHead(405, { allow: 'POST' }).end(); return; }

  let size = 0;
  const chunks = [];
  req.on('data', (c) => {
    size += c.length;
    if (size > MAX_BODY) { req.destroy(); return; }
    chunks.push(c);
  });
  req.on('end', () => {
    let payload;
    try { payload = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { res.writeHead(400).end(); return; }
    const sse = String(req.headers['accept'] || '').includes('text/event-stream');
    const batch = Array.isArray(payload) ? payload : [payload];
    const replies = [];
    for (const m of batch) {
      try {
        const r = handle(m);
        if (r) replies.push(r);
        try {
          const tag = m?.method === 'tools/call' ? 'tools/call:' + (m?.params?.name || '?') : String(m?.method || '?');
          fs.appendFileSync(path.join(path.dirname(FILE), 'access.log'), `${new Date().toISOString()} ${tag}\n`);
        } catch { /* logging must never break the request */ }
      } catch { /* ignore */ }
    }
    if (!replies.length) { res.writeHead(202).end(); return; }
    send(res, 200, Array.isArray(payload) ? replies : replies[0], sse);
  });
});

server.listen(PORT, HOST, () => {
  console.log(`[memory-bridge] listening http://${HOST}:${PORT}/mcp`);
  console.log(`[memory-bridge] file: ${FILE}`);
  console.log(`[memory-bridge] auth: ${TOKEN ? 'token required' : 'DISABLED (local only)'}`);
});
