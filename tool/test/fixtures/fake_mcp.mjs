// Minimal stand-in for `firebase mcp` used by export_live_rules.test.mjs.
// Behaviour is controlled by env vars; every call is appended to FAKE_LOG.
import fs from 'node:fs';
import readline from 'node:readline';

const log = (m) => process.env.FAKE_LOG && fs.appendFileSync(process.env.FAKE_LOG, `${m}\n`);
const reply = (id, result) => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n');

process.stdout.write('not json: banner line\n');
readline.createInterface({ input: process.stdin }).on('line', (line) => {
  const msg = JSON.parse(line);
  log(`${msg.method}${msg.params?.name ? ` ${msg.params.name}(${msg.params.arguments?.type})` : ''}`);
  if (msg.id === undefined) return;
  if (msg.method === 'initialize') return reply(msg.id, { protocolVersion: '2025-06-18', capabilities: {} });
  if (msg.method === 'tools/list') {
    return reply(msg.id, {
      tools: [
        { name: 'firebase_get_security_rules', annotations: { readOnlyHint: process.env.FAKE_RO !== '0' } },
        { name: 'firebase_deploy_something', annotations: { readOnlyHint: false } },
      ],
    });
  }
  if (msg.method === 'tools/call') {
    const type = msg.params.arguments.type;
    if (type === 'storage' && process.env.FAKE_NO_STORAGE === '1') {
      return reply(msg.id, { isError: true, content: [{ type: 'text', text: "No active Storage rules were found in project 'x'" }] });
    }
    return reply(msg.id, { content: [{ type: 'text', text: `rules_version = '2';\n// live ${type}\n` }] });
  }
  return reply(msg.id, {});
});
