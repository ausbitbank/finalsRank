// Optional live network check. This is NOT part of `npm test`, because it needs
// network access and a real player name.
//
// Usage:
//   FINALS_PLAYER='YourName#1234' npm run test:live
//
// Optional:
//   FINALS_BOARD=s12quickcash
//   FINALS_PLATFORM=crossplay
//   FINALS_UPSTREAM=1        # also parse the live upstream fallback page
//
// The harness extracts the real functions from Logic/FinalsLogic.qml and runs
// them in a vm sandbox, so it tests the shipped code rather than a copy.

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const SRC = fs.readFileSync(path.join(ROOT, 'Logic', 'FinalsLogic.qml'), 'utf8');
const UA = 'finalsRank/1.3.0 (DankMaterialShell plugin)';

const PLAYER = process.env.FINALS_PLAYER || '';
const BOARD = process.env.FINALS_BOARD || 's12quickcash';
const PLATFORM = process.env.FINALS_PLATFORM || 'crossplay';
const CHECK_UPSTREAM = process.env.FINALS_UPSTREAM === '1';

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

function makeEnv() {
  const recorded = [];
  const sandbox = {
    proc: { requestUrl: '', buffer: '', statusCode: '' },
    proc1: { requestUrl: '', buffer: '' },
    proc2: { requestUrl: '', buffer: '' },
    proc3: { requestUrl: '', buffer: '' },
    proc4: { requestUrl: '', buffer: '', running: false },
    playerName: PLAYER,
    board: BOARD,
    platform: PLATFORM,
    seasonName: 'PRIME TIME',
    seasonStartIso: '2026-10-20T13:00:00Z',
    seasonEndIso: '2027-01-21T13:00:00Z',
    showPoints: true,
    refreshMinutes: 15,
    historyEnabled: false,
    retentionDays: 120,
    dedupeChanges: true,
    deltaHours: 24,
    showPercentile: true,
    showSeasons: false,
    includeSponsors: false,
    toastOnRankChange: true,
    historyPath: '',
    loading: false,
    hasEntry: false,
    rank: -1,
    points: -1,
    lastUpdated: '',
    errorText: '',
    resolvedName: '',
    dataAgeSec: -1,
    dataModifiedMs: 0,
    dataFreshnessKnown: false,
    lastGoodMs: 0,
    boardCount: -1,
    offBoardReason: '',
    validatingName: false,
    previousRank: 0,
    seasons: [],
    serverUpdated: '',
    seasonsError: false,
    _now: Date.now(),
    history: [],
    nameChecks: [],
    seasonFetchUrls: [],
    rankMoves: [],
    hist: {
      record: (...args) => recorded.push(args),
    },
    rankMoved: (...args) => sandbox.rankMoves.push(args),
  };
  Object.defineProperty(sandbox, 'playerKey', {
    get() { return String(sandbox.playerName || '').trim(); },
  });

  const ctx = vm.createContext(sandbox);
  vm.runInContext('var fd = globalThis;', ctx);
  vm.runInContext('var upstreamSuffix = ' + grabLiteral(SRC, 'upstreamSuffix') + ';', ctx);
  vm.runInContext([
    'function _parse(',
    'function _baseName(',
    'function _stamp(',
    'function _splitResponse(',
    'function _upstreamUrl(',
    'function _findUpstreamRow(',
    'function _parseUpstream(',
    'function _tryUpstream(',
    'function _parseNameCheck(',
  ].map((h) => grabFn(SRC, h)).join('\n'), ctx);

  sandbox._validateName = function () {
    sandbox.nameChecks.push(sandbox.playerKey);
  };
  sandbox._seasonFetch = function () {
    if (sandbox.showSeasons) sandbox.seasonFetchUrls.push(sandbox.resolvedName);
  };
  sandbox.__recorded = recorded;
  return sandbox;
}

function curl(url, maxTime, withHeaders) {
  const args = ['-sL', '--fail', '--retry', '2',
                '--connect-timeout', '10', '--max-time', String(maxTime)];
  if (withHeaders) args.push('-D', '-');
  args.push('-w', '\n%{http_code}', '-H', `User-Agent: ${UA}`, url);
  try {
    return { code: 0, out: execFileSync('curl', args, { encoding: 'utf8', maxBuffer: 1 << 24 }) };
  } catch (e) {
    return { code: e.status ?? 1, out: (e.stdout || '') };
  }
}

function onExited(s, code) {
  s.loading = false;
  const split = s._splitResponse(s.proc.buffer, code);
  s.proc.buffer = '';
  s.proc.statusCode = split.status;
  if (code === 0) s._parse(split.body, split.headers);
  else if (s.errorText === '') {
    s.errorText = 'HTTP ' + (split.status === '' ? '?' : split.status)
      + ' (curl ' + code + ')';
  }
}

function runPrimary() {
  const s = makeEnv();
  s.proc.requestUrl = 'https://api.the-finals-leaderboard.com/v1/leaderboard/'
    + BOARD + '/' + PLATFORM
    + '?name=' + encodeURIComponent(PLAYER) + '&exactMatch=true';
  const { code, out } = curl(s.proc.requestUrl, 20, true);
  s.proc.buffer = out;
  onExited(s, code);
  return s;
}

function runUpstream() {
  const s = makeEnv();
  const url = s._upstreamUrl(BOARD);
  if (!url) return { skipped: 'no upstream mapping for this board' };
  const { code, out } = curl(url, 45, false);
  if (code !== 0) return { skipped: `upstream HTTP ${code}` };
  const body = out.replace(/\n\d{3}\s*$/, '');
  s._parseUpstream(body);
  return s;
}

let ok = true;
const check = (label, condition, detail = '') => {
  console.log(`  ${condition ? 'PASS' : 'FAIL'}  ${label}${detail ? `  [${detail}]` : ''}`);
  if (!condition) ok = false;
};

console.log('=== offline parsing checks ===');
{
  const s = makeEnv();
  const redirect = s._splitResponse(
    'HTTP/2 302 \r\nlocation: /x\r\n\r\nHTTP/2 200 \r\nage: 4\r\n\r\n{"data":[]}\n200', 0);
  check('redirect: last header block wins', redirect.headers.age === '4');
  check('redirect: no location leaked', redirect.headers.location === undefined);
  check('redirect: status parsed', redirect.status === '200');
  check('quick cash maps to qc',
        s._upstreamUrl('s12quickcash') === 'https://id.embark.games/the-finals/leaderboards/s12qc');
  check('unknown mode refuses to guess', s._upstreamUrl('s12notamode') === '');

  const rows = [
    { '1': '5', '3': 'Phantom#1111', '5': '900' },
    { '1': '9', '3': 'Phantom#2222', '5': '800' },
    { '1': '3', '3': 'Player#1234', '5': '1000' },
  ];
  const ambiguous = s._findUpstreamRow(rows, 'phantom');
  check('colliding base names are rejected', ambiguous.__ambiguous === 2);
  check('discriminator disambiguates',
        s._findUpstreamRow(rows, 'phantom#2222')['3'] === 'Phantom#2222');
}

if (PLAYER === '') {
  console.log('\nSkipping live checks: set FINALS_PLAYER to a player name.');
  console.log(ok ? 'ALL PASS' : 'FAILURES PRESENT');
  process.exit(ok ? 0 : 1);
}

console.log(`\n=== live primary: ${PLAYER} on ${BOARD}/${PLATFORM} ===`);
{
  const s = runPrimary();
  check('HTTP success', s.proc.statusCode === '200' || s.proc.statusCode === '404',
        `status=${s.proc.statusCode}`);
  check('no unexpected error', s.errorText === '', s.errorText);
  if (s.hasEntry) {
    check('rank is a positive int', Number.isInteger(s.rank) && s.rank > 0, `rank=${s.rank}`);
    check('points is an int', Number.isInteger(s.points), `points=${s.points}`);
    check('canonical name captured', s.resolvedName !== '', s.resolvedName);
    check('data age is known or absent', s.dataAgeSec >= -1, `age=${s.dataAgeSec}`);
  } else {
    check('off-board state is clean', s.rank === -1 && s.points === -1);
    check('reason is one of the expected states',
          s.offBoardReason === '' || s.offBoardReason === 'unknown-player'
          || s.offBoardReason === 'not-on-board', s.offBoardReason);
  }
}

if (CHECK_UPSTREAM) {
  console.log(`\n=== live upstream: ${BOARD} ===`);
  const s = runUpstream();
  if (s.skipped) {
    console.log(`  SKIP  ${s.skipped}`);
  } else {
    check('no upstream parse error', s.errorText === '', s.errorText);
    check('upstream has an entry', s.hasEntry, `rank=${s.rank}`);
    if (s.hasEntry) {
      check('rank is a positive int', Number.isInteger(s.rank) && s.rank > 0, `rank=${s.rank}`);
      check('points is an int', Number.isInteger(s.points), `points=${s.points}`);
      check('board count is positive', s.boardCount > 0, `boardCount=${s.boardCount}`);
      check('canonical name captured', s.resolvedName !== '', s.resolvedName);
    }
  }
}

console.log('\n' + (ok ? 'ALL PASS' : 'FAILURES PRESENT'));
process.exit(ok ? 0 : 1);
