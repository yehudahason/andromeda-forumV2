import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { formatDate } from "./formatDate";

beforeEach(() => {
  vi.stubEnv("TZ", "Europe/Rome");
});
describe("formatDate", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  const setTestTime = () => {
    vi.useFakeTimers();

    // Italy local time: 24 Aug 2026, 21:00 CEST
    const now = new Date("2026-08-24T21:00:00+02:00");
    vi.setSystemTime(now);

    return now;
  };

  it("returns DD-MM on the exact one-year boundary", () => {
    const now = setTestTime();

    const date = new Date(now);
    date.setFullYear(date.getFullYear() - 1);

    expect(formatDate(date.toISOString())).toBe("24-08");
  });

  it("returns DD-MM-YY one millisecond before the one-year boundary", () => {
    const now = setTestTime();

    const date = new Date(now);
    date.setFullYear(date.getFullYear() - 1);
    date.setMilliseconds(date.getMilliseconds() - 1);

    expect(formatDate(date.toISOString())).toBe("24-08-25");
  });

  it("returns local HH:MM for a date less than 24 hours ago", () => {
    const now = setTestTime();

    // 1 hour ago → 20:00 Italy
    const date = new Date(now.getTime() - 1 * 60 * 60 * 1000);

    expect(formatDate(date.toISOString())).toBe("20:00");
  });

  it("returns HH:MM for exactly 23 hours ago", () => {
    const now = setTestTime();

    const date = new Date(now.getTime() - 23 * 60 * 60 * 1000);

    expect(formatDate(date.toISOString())).toBe("22:00");
  });

  it("returns DD-MM for exactly 25 hours ago", () => {
    const now = setTestTime();

    const date = new Date(now.getTime() - 25 * 60 * 60 * 1000);

    expect(formatDate(date.toISOString())).toBe("23-08");
  });

  it("returns DD-MM for exactly 364 days ago", () => {
    const now = setTestTime();

    const date = new Date(now);
    date.setDate(date.getDate() - 364);

    expect(formatDate(date.toISOString())).toBe("25-08");
  });

  it("returns DD-MM-YY for exactly 366 days ago", () => {
    const now = setTestTime();

    const date = new Date(now);
    date.setDate(date.getDate() - 366);

    expect(formatDate(date.toISOString())).toBe("23-08-25");
  });

  it("returns DD-MM-YY for more than one year ago", () => {
    setTestTime();

    const date = new Date("2025-07-15T12:00:00+02:00");

    expect(formatDate(date.toISOString())).toBe("15-07-25");
  });

  it("returns DD-MM for a date less than one year old", () => {
    setTestTime();

    const date = "2026-07-15T12:00:00Z";

    expect(formatDate(date)).toBe("15-07");
  });

  it("returns empty string for null", () => {
    expect(formatDate(null)).toBe("");
  });
});
