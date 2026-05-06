import { describe, expect, it } from "vitest";
import { getClientCache, getCompanyId } from "./react-query";

describe("getCompanyId", () => {
  it("returns null when called during server rendering", () => {
    expect(() => getCompanyId()).not.toThrow();
    expect(getCompanyId()).toBeNull();
  });

  it("does not read the client cache during server rendering", () => {
    expect(() => getClientCache()).not.toThrow();
    expect(getClientCache()).toBeUndefined();
  });
});
