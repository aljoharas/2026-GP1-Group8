'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { wrappedYearDue } = require('../lib/reminders');

// Times are UTC; Riyadh is UTC+3.
const at = (iso) => new Date(iso);

test('due on Dec 31 in Riyadh, for that year', () => {
  assert.equal(wrappedYearDue(at('2026-12-31T00:00:00Z')), 2026);
  // 21:00 UTC on Dec 30 is already midnight Dec 31 in Riyadh
  assert.equal(wrappedYearDue(at('2026-12-30T21:00:00Z')), 2026);
});

test('not due before Dec 31 in Riyadh', () => {
  assert.equal(wrappedYearDue(at('2026-12-30T20:59:59Z')), null);
  assert.equal(wrappedYearDue(at('2026-06-15T12:00:00Z')), null);
});

test('still due early in January, for the year before', () => {
  assert.equal(wrappedYearDue(at('2027-01-01T10:00:00Z')), 2026);
  assert.equal(wrappedYearDue(at('2027-01-07T20:59:59Z')), 2026);
});

test('no longer due after the first week of January', () => {
  // Jan 8 00:00 in Riyadh
  assert.equal(wrappedYearDue(at('2027-01-07T21:00:00Z')), null);
});
