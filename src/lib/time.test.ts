import { describe, expect, it } from 'vitest';
import { formatIST } from './time';

describe('formatIST', () => {
  it('shows UTC midnight as 5:30 AM India time', () => {
    expect(formatIST('2026-11-19T00:00:00Z')).toBe('19 Nov 2026, 5:30 AM');
  });

  it('rolls the date forward across midnight in India', () => {
    expect(formatIST('2026-11-19T20:00:00Z', 'yyyy-MM-dd HH:mm')).toBe('2026-11-20 01:30');
  });

  it('returns an empty string for an invalid date', () => {
    expect(formatIST('not a date')).toBe('');
  });
});
