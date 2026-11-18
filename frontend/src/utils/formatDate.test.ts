import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { formatDate } from "./formatDate";

// Construct a date in the test machine's local timezone, then encode it
// as a valid UTC timestamp. This keeps the expected output independent
// of whether the tests run in Israel, UTC, or another timezone.
function localTimestamp(
  year: number,
  month: number,
  day: number,
  hour = 0,
  minute = 0,
): string {
  return new Date(year, month - 1, day, hour, minute).toISOString();
}

describe("formatDate", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2026, 10, 18, 20, 0)); // Nov 18, 2026, 20:00 local
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns an empty string for null, undefined, or empty input", () => {
    expect(formatDate(null)).toBe("");
    expect(formatDate(undefined)).toBe("");
    expect(formatDate("")).toBe("");
  });

  it("returns an empty string for invalid dates", () => {
    expect(formatDate("not-a-date")).toBe("");
    expect(formatDate("2026-11-18T99:99:00Z")).toBe("");
  });

  it("rejects timestamps without an explicit timezone", () => {
    expect(formatDate("2026-11-18T12:00:00")).toBe("");
    expect(formatDate("2026-11-18")).toBe("");
  });

  it("returns HH:MM for a time earlier today", () => {
    expect(formatDate(localTimestamp(2026, 11, 18, 8, 5))).toBe("08:05");
  });

  it("returns HH:MM for a date at the start of today", () => {
    expect(formatDate(localTimestamp(2026, 11, 18, 0, 0))).toBe("00:00");
  });

  it("returns HH:MM for a date later on the same calendar day", () => {
    expect(formatDate(localTimestamp(2026, 11, 18, 23, 59))).toBe("23:59");
  });

  it("returns DD-MM for yesterday, even when less than 24 hours ago", () => {
    // At 20:00, yesterday at 23:59 was just 20 hours and 1 minute ago.
    expect(formatDate(localTimestamp(2026, 11, 17, 23, 59))).toBe("17-11");
  });

  it("switches formats at midnight, even when only 2 minutes have passed", () => {
    vi.setSystemTime(new Date(2026, 10, 18, 0, 1));
    expect(formatDate(localTimestamp(2026, 11, 17, 23, 59))).toBe("17-11");
    expect(formatDate(localTimestamp(2026, 11, 18, 0, 0))).toBe("00:00");
  });

  it("returns DD-MM for a date earlier this year", () => {
    expect(formatDate(localTimestamp(2026, 6, 3, 14, 30))).toBe("03-06");
  });

  it("returns DD-MM for a date within the last year in the previous calendar year", () => {
    expect(formatDate(localTimestamp(2025, 12, 20, 10, 0))).toBe("20-12");
  });

  it("returns DD-MM at the exact one-year cutoff", () => {
    expect(formatDate(localTimestamp(2025, 11, 18, 20, 0))).toBe("18-11");
  });

  it("returns DD-MM-YY for dates older than one year", () => {
    expect(formatDate(localTimestamp(2025, 11, 18, 19, 59))).toBe("18-11-25");
    expect(formatDate(localTimestamp(2024, 1, 9, 12, 0))).toBe("09-01-24");
  });

  it("accepts explicit UTC offsets as well as Z", () => {
    const iso = localTimestamp(2026, 11, 18, 9, 7);
    expect(formatDate(iso)).toBe("09:07");
    expect(formatDate(iso.replace(/Z$/, "+00:00"))).toBe("09:07");
  });

  it("returns DD-MM for a date on a future calendar day", () => {
    expect(formatDate(localTimestamp(2026, 11, 19, 9, 0))).toBe("19-11");
  });
});
