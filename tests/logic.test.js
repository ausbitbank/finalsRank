// Offline tests for the pure helpers in FinalsLogic.qml and HistoryStore.qml.
//
// The functions are extracted from the shipped QML with brace matching and run
// in a vm sandbox. Nothing is copied or rewritten, so the tests exercise the
// same source the plugin loads.

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const ROOT = path.join(__dirname, '..');
const LOGIC_SRC = fs.readFileSync(path.join(ROOT, 'Logic', 'FinalsLogic.qml'), 'utf8');
const STORE_SRC = fs.readFileSync(path.join(ROOT, 'Logic', 'HistoryStore.qml'), 'utf8');

function grabFn(src, header) {
  const start = src.indexOf(header);
  if (start < 0) throw new Error(`function not found: ${header}`);
  const open = src.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) return src.slice(start, i + 1);
    }
  }
  throw new Error(`unbalanced braces: ${header}`);
}

function grabLiteral(src, name) {
  const re = new RegExp(`readonly property var ${name}:\\s*(\\{[\\s\\S]*?\\n\\s*\\})`);
  const m = re.exec(src);
  if (!m) throw new Error(`property not found: ${name}`);
  return m[1];
}

let passed = 0;
function eq(actual, expected, label) {
  assert.strictEqual(actual, expected, label);
  passed++;
}
function ok(condition, label) {
  assert.ok(condition, label);
  passed++;
}

// ── FinalsLogic helpers ─────────────────────────────────────────────────────
const logicContext = vm.createContext({});
vm.runInContext('var fd = globalThis;', logicContext);
vm.runInContext('var modeNames = ' + grabLiteral(LOGIC_SRC, 'modeNames') + ';', logicContext);
vm.runInContext('var upstreamSuffix = ' + grabLiteral(LOGIC_SRC, 'upstreamSuffix') + ';', logicContext);
vm.runInContext([
  'function modeLabel(',
  'function _baseName(',
  'function _stamp(',
  'function _splitResponse(',
  'function _upstreamUrl(',
  'function _findUpstreamRow(',
].map((h) => grabFn(LOGIC_SRC, h)).join('\n'), logicContext);

const fd = logicContext;

eq(fd.modeLabel('quickcash'), 'Quick Cash', 'known mode is named');
eq(fd.modeLabel(''), 'Ranked', 'empty mode is ranked');
eq(fd.modeLabel('weirdmode'), 'weirdmode', 'unknown mode falls through to its slug');
eq(fd.modeLabel(undefined), 'Ranked', 'undefined mode is ranked');

eq(fd._baseName('Player#1234'), 'player', 'discriminator is stripped');
eq(fd._baseName('  PLAYER  '), 'player', 'name is trimmed and lowercased');
eq(fd._baseName(''), '', 'empty name stays empty');

ok(/^\d{2}:\d{2}$/.test(fd._stamp(Date.now())), 'timestamp is HH:MM');

const redirect = fd._splitResponse(
  'HTTP/2 302 \r\nlocation: /x\r\n\r\nHTTP/2 200 \r\nage: 4\r\n\r\n{"data":[]}\n200', 0);
eq(redirect.headers.age, '4', 'redirect: last header block wins');
eq(redirect.headers.location, undefined, 'redirect: no location leaked');
eq(redirect.status, '200', 'redirect: status suffix is parsed');
eq(redirect.body, '{"data":[]}', 'redirect: body is preserved');

const notFound = fd._splitResponse(
  'HTTP/2 404 \r\ncontent-type: application/json\r\n\r\n\n404', 22);
eq(notFound.status, '404', '404: status recovered');
eq(notFound.body, '', '404: body stays empty');

for (const bad of ['', 'garbage', '\n200', 'HTTP/2 200\r\n\r\n']) {
  let threw = false;
  try { fd._splitResponse(bad, 0); } catch (e) { threw = true; }
  ok(!threw, `degenerate response does not throw: ${JSON.stringify(bad)}`);
}

eq(fd._upstreamUrl('s12quickcash'),
   'https://id.embark.games/the-finals/leaderboards/s12qc', 'quick cash slug');
eq(fd._upstreamUrl('s12'),
   'https://id.embark.games/the-finals/leaderboards/s12', 'ranked slug');
eq(fd._upstreamUrl('s12soloshowdown'),
   'https://id.embark.games/the-finals/leaderboards/s12ss', 'solo showdown slug');
eq(fd._upstreamUrl('s12notamode'), '', 'unknown mode refuses to guess');
eq(fd._upstreamUrl('orf'),
   'https://id.embark.games/the-finals/leaderboards/orf', 'special orf board');

const rows = [
  { '1': '5', '3': 'Phantom#1111', '5': '900' },
  { '1': '9', '3': 'Phantom#2222', '5': '800' },
  { '1': '3', '3': 'Player#1234', '5': '1000' },
];
const ambiguous = fd._findUpstreamRow(rows, 'phantom');
eq(ambiguous.__ambiguous, 2, 'colliding base names are reported, not guessed');
eq(fd._findUpstreamRow(rows, 'phantom#2222')['3'], 'Phantom#2222',
   'discriminator disambiguates a collision');
eq(fd._findUpstreamRow(rows, 'player')['3'], 'Player#1234',
   'unique base name resolves without a discriminator');
eq(fd._findUpstreamRow(rows, 'missing').__ambiguous, 0, 'absent name yields no row');

// ── HistoryStore helpers ────────────────────────────────────────────────────
const storeContext = vm.createContext({
  samples: [],
  scoped: [],
  retentionDays: 120,
  maxSamples: 20000,
  loaded: false,
  loadError: '',
});
vm.runInContext('var store = globalThis;', storeContext);
vm.runInContext([
  'function _signed(',
  'function _serialize(',
  'function _prune(',
  'function _ingest(',
  'function _atOrBefore(',
  'function _after(',
].map((h) => grabFn(STORE_SRC, h)).join('\n'), storeContext);

const store = storeContext;
eq(store._signed(0), '', 'zero delta is blank');
eq(store._signed(3), '+3', 'positive delta is signed');
eq(store._signed(-2), '-2', 'negative delta keeps its sign');

store.samples = [{ t: 1, b: 's12"qc', p: 'crossplay', r: 5, k: 10, a: 3 }];
const line = store._serialize().trim();
const row = JSON.parse(line);
eq(row.b, 's12"qc', 'JSONL escapes a quote in the board name');
eq(row.a, 3, 'data age is preserved when numeric');
store.samples = [{ t: 2, b: 'b', p: 'p', r: 6, k: 11, a: 'x' }];
eq(JSON.parse(store._serialize().trim()).a, undefined,
   'non-numeric data age is omitted');

store.retentionDays = 0;
store.maxSamples = 2;
const pruned = store._prune([{ t: 1 }, { t: 2 }, { t: 3 }]);
eq(pruned.length, 2, 'sample cap trims the list');
eq(pruned[0].t, 2, 'sample cap keeps the newest rows');
store.retentionDays = 30;
const now = Date.now();
const aged = store._prune([
  { t: now - 40 * 86400000 },
  { t: now - 10 * 86400000 },
]);
eq(aged.length, 1, 'retention drops old rows');
eq(aged[0].t, now - 10 * 86400000, 'retention keeps recent rows');

const raw = [
  '{"t":1,"b":"s12","p":"crossplay","r":5,"k":10}',
  '{"t":2,"b":"s12","p":"crossplay","r":6,"k":11}',
  '{"t":3,"b":"s12","p":"crosspla',
  '',
].join('\n');
store._ingest(raw);
eq(store.samples.length, 2, 'ingest skips a torn final line');
eq(store.loaded, true, 'ingest marks the store loaded');
eq(store.loadError, '', 'ingest clears the load error');

store.scoped = [{ t: 1 }, { t: 2 }, { t: 3 }];
eq(store._atOrBefore(2).t, 2, 'at-or-before finds the nearest sample');
eq(store._atOrBefore(0), null, 'at-or-before returns null before the first sample');
eq(store._after(1).length, 2, 'after returns the later samples');

// ── Repository hygiene ──────────────────────────────────────────────────────
function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8');
}

const qmlFiles = [
  'Widget.qml',
  'DesktopWidget.qml',
  'Settings.qml',
  'Logic/FinalsLogic.qml',
  'Logic/FinalsPanel.qml',
  'Logic/FinalsLogo.qml',
  'Logic/HistoryStore.qml',
  'Logic/Sparkline.qml',
];

for (const file of qmlFiles) {
  const text = read(file);
  ok(!/playerName:\s*"[^"]+"/.test(text), `${file} has no literal player default`);
  ok(!/\/home\//.test(text), `${file} has no absolute home path`);
  ok(!/\/tmp\//.test(text), `${file} has no scratch path`);
  ok(!/Mozilla\/5\.0/.test(text), `${file} does not impersonate a browser`);
}

ok(/property string playerName:\s*""/.test(read('Logic/FinalsLogic.qml')),
   'FinalsLogic defaults to an empty player');
ok(/defaultValue:\s*""/.test(read('Settings.qml')),
   'Settings defaults to an empty player');
ok(!/playerName:\s*"[^"]+"/.test(read('Widget.qml')),
   'Widget does not default to a player name');
ok(!/playerName:\s*"[^"]+"/.test(read('DesktopWidget.qml')),
   'DesktopWidget does not default to a player name');

const manifest = JSON.parse(read('plugin.json'));
eq(manifest.id, 'finalsRank', 'manifest id is stable');
eq(manifest.license, 'MIT', 'manifest license is MIT');
ok(manifest.author !== 'a' && typeof manifest.author === 'string',
   'manifest author is set');

console.log(`\n${passed} assertions passed.`);
