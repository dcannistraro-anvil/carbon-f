import pc from "picocolors";
import { TLD } from "../constants.js";
import type { PortMap } from "../lib/ports.js";

/**
 * OSC 8 hyperlink. Supported by iTerm2, Terminal.app, Warp, kitty, etc.
 * Falls back to plain text in unsupported terminals.
 */
function link(url: string, text?: string): string {
  const label = text ?? url;
  return `\x1b]8;;${url}\x1b\\${label}\x1b]8;;\x1b\\`;
}

type Color = (s: string) => string;

/** Boxed list of URLs + DB DSN for the up-summary. */
export function summaryLines(
  ports: PortMap,
  branchPrefix: string | null
): string[] {
  const host = (sub: string) =>
    branchPrefix
      ? `https://${branchPrefix}.${sub}.${TLD}`
      : `https://${sub}.${TLD}`;
  const dbUrl = `postgresql://postgres:postgres@localhost:${ports.PORT_DB}/postgres`;
  return [
    row(pc.cyan, "ERP", host("erp")),
    row(pc.magenta, "MES", host("mes")),
    row(pc.green, "API", host("api"), ports.PORT_API),
    row(pc.green, "Studio", host("studio"), ports.PORT_STUDIO),
    row(pc.yellow, "Mail", host("mail"), ports.PORT_INBUCKET),
    row(pc.blue, "Inngest", host("inngest"), ports.PORT_INNGEST),
    `${pc.gray(pc.bold("Postgres".padEnd(8)))}  ${pc.gray(dbUrl)}`
  ];
}

function row(color: Color, label: string, url: string, port?: number): string {
  const lbl = color(pc.bold(label.padEnd(8)));
  const target = color(link(url));
  const portTag = port ? `  ${pc.dim(`:${port}`)}` : "";
  return `${lbl}  ${target}${portTag}`;
}
