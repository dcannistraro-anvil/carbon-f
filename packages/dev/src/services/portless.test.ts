import { describe, expect, it } from "vitest";
import { portlessPrivilegedCmd } from "./portless.js";

describe("portlessPrivilegedCmd", () => {
  it("runs portless directly on Windows (no sudo binary)", () => {
    expect(
      portlessPrivilegedCmd(["proxy", "start"], {
        platform: "win32",
        home: "C:\\Users\\someone"
      })
    ).toEqual({ file: "portless", args: ["proxy", "start"] });
  });

  it("wraps in sudo with HOME=... on POSIX shells", () => {
    expect(
      portlessPrivilegedCmd(["proxy", "start"], {
        platform: "linux",
        home: "/home/someone"
      })
    ).toEqual({
      file: "sudo",
      args: ["HOME=/home/someone", "portless", "proxy", "start"]
    });
  });
});
