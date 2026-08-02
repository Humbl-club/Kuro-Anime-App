#!/usr/bin/env node
/*
  Offline self-test for descriptor row validation (mirrors upsert_media_realm_llm).
  Run: node scripts/realm_descriptor_validate_selftest.js
*/

const TONE_VOCAB = new Set([
  'whimsical', 'melancholic', 'brutal', 'cozy', 'cerebral', 'kinetic',
  'tender', 'eerie', 'absurd', 'earnest', 'dark', 'warm',
  'bleak', 'playful', 'solemn', 'lush', 'gritty', 'dreamlike',
  'frantic', 'intimate', 'epic', 'quiet', 'hysterical', 'meditative',
]);
const REGISTERS = new Set(['family', 'general', 'seinen-otaku', 'arthouse']);
const PACINGS = new Set(['slow-burn', 'steady', 'relentless']);
const REALMS = new Set(['auteur-cinema', 'quiet-melancholy', 'coming-of-age']);

function charLen(s) { return [...s].length; }

function validate(row) {
  const errors = [];
  if (row.media_type !== 'ANIME' && row.media_type !== 'MANGA') errors.push('media_type');
  if (!Number.isInteger(row.media_id) || row.media_id < 1) errors.push('media_id');
  if (!Array.isArray(row.realms) || row.realms.length < 1 || row.realms.length > 3) errors.push('realms');
  else {
    for (const e of row.realms) {
      if (!REALMS.has(e.realm)) errors.push('realm');
      if (typeof e.weight !== 'number' || e.weight < 0 || e.weight > 1) errors.push('weight');
    }
  }
  if (!Array.isArray(row.tone) || row.tone.some((w) => !TONE_VOCAB.has(w))) errors.push('tone');
  if (!REGISTERS.has(row.register)) errors.push('register');
  if (!PACINGS.has(row.pacing)) errors.push('pacing');
  if (typeof row.confidence !== 'number' || row.confidence < 0 || row.confidence > 1) errors.push('confidence');
  if (typeof row.descriptor !== 'string' || charLen(row.descriptor) < 100 || charLen(row.descriptor) > 600) {
    errors.push('descriptor');
  }
  return errors;
}

const good = {
  media_type: 'ANIME',
  media_id: 111,
  realms: [{ realm: 'auteur-cinema', weight: 0.9 }, { realm: 'coming-of-age', weight: 0.4 }],
  tone: ['dreamlike', 'whimsical'],
  register: 'general',
  pacing: 'steady',
  confidence: 0.9,
  descriptor: 'A bathhouse of spirits becomes the proving ground for a girl learning to see people as more than what they want from her. Folklore fantasy with a director\'s hand, not a power fantasy.',
  model: 'test',
};

let failed = 0;
function assert(name, cond) {
  if (!cond) {
    console.error('FAIL', name);
    failed += 1;
  } else {
    console.log('ok', name);
  }
}

assert('good row', validate(good).length === 0);
assert('bad realm', validate({ ...good, realms: [{ realm: 'nope', weight: 0.5 }] }).includes('realm'));
assert('short descriptor', validate({ ...good, descriptor: 'too short' }).includes('descriptor'));
assert('bad tone', validate({ ...good, tone: ['spicy'] }).includes('tone'));

if (failed) process.exit(1);
console.log('selftest passed');
