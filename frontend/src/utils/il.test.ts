import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { formatDate } from "./formatDate";

describe("formatDate (Asia/Jerusalem)", () => {
  beforeEach(() => {
    vi.stubEnv("TZ", "Asia/Jerusalem");
    vi.useFakeTimers();
    // System time: 24 Aug 2026, 21:00:00 IDT (UTC+3)
    vi.setSystemTime(new Date("2026-08-24T21:00:00+03:00"));
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.useRealTimers();
  });

  it("returns local HH:MM for dates under 24 hours ago", () => {
    // 1 hour ago -> 20:00 IDT
    const oneHourAgo = new Date("2026-08-24T20:00:00+03:00").toISOString();
    expect(formatDate(oneHourAgo)).toBe("20:00");

    // 23 hours ago -> 22:00 IDT (yesterday)
    const twentyThreeHoursAgo = new Date(
      "2026-08-23T22:00:00+03:00",
    ).toISOString();
    expect(formatDate(twentyThreeHoursAgo)).toBe("22:00");
  });

  it("returns local date (DD-MM) across UTC midnight boundary", () => {
    // 01:30 IDT on Aug 24 is 22:30 UTC on Aug 23
    const lateNightUtc = "2026-08-23T22:30:00Z";
    expect(formatDate(lateNightUtc)).toBe("01:30");
  });

  it("returns DD-MM for dates older than 24 hours but within the same year", () => {
    // 25 hours ago -> 20:00 IDT on 23 Aug 2026
    const date = new Date("2026-08-23T20:00:00+03:00").toISOString();
    expect(formatDate(date)).toBe("23-08");
  });

  it("returns DD-MM on exact 1-year boundary", () => {
    // Exactly 1 year ago today
    const exactOneYear = new Date("2025-08-24T21:00:00+03:00").toISOString();
    expect(formatDate(exactOneYear)).toBe("24-08");
  });

  it("returns DD-MM-YY for dates older than 1 year", () => {
    // 1 year + 1 day ago
    const olderThanOneYear = new Date(
      "2025-08-23T21:00:00+03:00",
    ).toISOString();
    expect(formatDate(olderThanOneYear)).toBe("23-08-25");
  });

  it("handles null and invalid inputs gracefully", () => {
    expect(formatDate(null)).toBe("");
    expect(formatDate(undefined)).toBe("");
    expect(formatDate("invalid-date")).toBe("");
  });
});
