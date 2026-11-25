'use strict';

// The pure parts of lib/igdb: name cleaning, picking among same-name games,
// query quoting and the stored fields. No network.

const test = require('node:test');
const assert = require('node:assert/strict');

const { cleanName, pickByYear, closeInYear, quote, enrichmentFields } = require('../lib/igdb');

const at = (year) => Date.UTC(year, 5, 1) / 1000; // IGDB dates are unix seconds

test('cleanName takes a trailing year out of the name', () => {
  assert.deepEqual(cleanName('God of War (2018)'), { name: 'God of War', year: 2018 });
  assert.deepEqual(cleanName('Overwatch 2'), { name: 'Overwatch 2', year: null });
  assert.deepEqual(cleanName('Halo (Remastered)'), { name: 'Halo (Remastered)', year: null });
});

test('pickByYear takes a single result as is', () => {
  const only = { slug: 'life-is-strange', first_release_date: at(2015) };
  assert.equal(pickByYear([only], null), only);
});

test('pickByYear picks the closest release year among same-name games', () => {
  const games = [
    { slug: 'god-of-war', first_release_date: at(2005) },
    { slug: 'god-of-war--1', first_release_date: at(2018) },
    { slug: 'god-of-war--2', first_release_date: at(2009) },
  ];
  assert.equal(pickByYear(games, 2018).slug, 'god-of-war--1');
  assert.equal(pickByYear(games, 2006).slug, 'god-of-war');
});

test('pickByYear does not guess between same-name games without a year', () => {
  assert.equal(pickByYear([{ slug: 'a', first_release_date: at(2005) }, { slug: 'b', first_release_date: at(2018) }], null), null);
  assert.equal(pickByYear([{ slug: 'a' }, { slug: 'b' }], 2018), null);
  assert.equal(pickByYear([], 2018), null);
});

test('quote escapes quotes and backslashes for an IGDB query', () => {
  assert.equal(quote('Tom Clancy\'s "Rainbow Six"'), '"Tom Clancy\'s \\"Rainbow Six\\""');
  assert.equal(quote('a\\b'), '"a\\\\b"');
});

test('enrichmentFields maps IGDB names and upgrades the cover URL', () => {
  const f = enrichmentFields({
    game_modes: [{ name: 'Multiplayer' }, { name: 'Co-operative' }],
    themes: [{ name: 'Action' }],
    cover: { url: '//images.igdb.com/igdb/image/upload/t_thumb/co1.jpg' },
  });
  assert.deepEqual(f.gameModes, ['Multiplayer', 'Co-operative']);
  assert.deepEqual(f.themes, ['Action']);
  assert.deepEqual(f.keywords, []);
  assert.equal(f.coverImage, 'https://images.igdb.com/igdb/image/upload/t_cover_big/co1.jpg');
  assert.equal(f.summary, null);
});

test('closeInYear drops alternative-name matches released years apart', () => {
  const games = [
    { slug: 'total-annihilation', first_release_date: at(1997) },
    { slug: 'remnant-ii', first_release_date: at(2023) },
    { slug: 'undated' },
  ];
  assert.deepEqual(closeInYear(games, 2022).map((g) => g.slug), ['remnant-ii', 'undated']);
  assert.equal(closeInYear(games, null).length, 3);
});
