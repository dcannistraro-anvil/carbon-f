import { describe, expect, it } from "vitest";
import { slugify } from "./worktree.js";

describe("slugify", () => {
  it("lowercases", () => {
    expect(slugify("Foo")).toBe("foo");
  });

  it("collapses non-alphanumeric runs to single dash", () => {
    expect(slugify("foo/bar baz")).toBe("foo-bar-baz");
    expect(slugify("foo   bar")).toBe("foo-bar");
  });

  it("strips leading and trailing dashes", () => {
    expect(slugify("--foo--")).toBe("foo");
    expect(slugify("/foo/")).toBe("foo");
  });

  it("preserves embedded dashes", () => {
    expect(slugify("feat-add-thing")).toBe("feat-add-thing");
  });

  it("collapses consecutive dashes", () => {
    expect(slugify("foo--bar")).toBe("foo-bar");
  });

  it("handles unicode by replacing with dashes", () => {
    expect(slugify("café/résumé")).toBe("caf-r-sum");
  });

  it("returns empty string when input is empty or all-symbol", () => {
    expect(slugify("")).toBe("");
    expect(slugify("///")).toBe("");
  });
});
