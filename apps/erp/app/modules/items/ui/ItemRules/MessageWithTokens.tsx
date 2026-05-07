import { useControlField } from "@carbon/form";
import {
  Button,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
  HStack
} from "@carbon/react";
import {
  type Condition,
  FIELD_REGISTRY,
  type FieldDef,
  getFieldDef,
  type TransactionSurface
} from "@carbon/utils";
import { Trans, useLingui } from "@lingui/react/macro";
import { useCallback, useMemo, useRef } from "react";
import { LuBraces } from "react-icons/lu";
import { TextArea } from "~/components/Form";

type MessageWithTokensProps = {
  name: string;
  label?: string;
  /**
   * Live conditions from `RuleBuilder`. Each contributes a section with
   * `{condition[N].field|operator|value}` tokens that resolve at eval time
   * to the rule's required values rather than the runtime ctx.
   */
  conditions?: Condition[];
  /**
   * Form-field name of the surfaces multi-select (default `"surfaces"`).
   * Read live via `useControlField` so the dropdown updates when the user
   * toggles surface scope without prop drilling.
   */
  surfacesFieldName?: string;
};

type TokenItem = { token: string; description: string };
type TokenGroup = { heading: string; tokens: TokenItem[] };

/**
 * Maps each surface to the ctx-block keys whose fields will be populated
 * at eval time. Used to filter the FIELD_REGISTRY into a relevant
 * suggestion list.
 */
const CTX_KEYS_BY_SURFACE: Record<TransactionSurface, FieldDef["context"][]> = {
  receipt: ["storage", "transaction"],
  shipment: ["storage", "transaction"],
  stockTransfer: ["storage", "transaction"],
  warehouseTransfer: ["storage", "transaction"],
  inventoryAdjustment: ["storage", "transaction"]
};

const CONTEXT_LABELS: Record<FieldDef["context"], string> = {
  item: "Item",
  storage: "Storage",
  transaction: "Transaction"
};

export default function MessageWithTokens({
  name,
  label,
  conditions,
  surfacesFieldName = "surfaces"
}: MessageWithTokensProps) {
  const { t } = useLingui();
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const [surfacesValue] =
    useControlField<TransactionSurface[]>(surfacesFieldName);
  const surfaces = surfacesValue ?? [];

  // Carbon TextArea wraps a native textarea; reach for it via DOM after mount.
  const setRefFromDom = useCallback((el: HTMLDivElement | null) => {
    textareaRef.current = el?.querySelector("textarea") ?? null;
  }, []);

  const insertToken = useCallback((token: string) => {
    const el = textareaRef.current;
    if (!el) return;
    const start = el.selectionStart ?? el.value.length;
    const end = el.selectionEnd ?? el.value.length;
    const insertion = `{${token}}`;
    el.value = el.value.slice(0, start) + insertion + el.value.slice(end);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    const cursor = start + insertion.length;
    el.setSelectionRange(cursor, cursor);
    el.focus();
  }, []);

  const groups = useMemo<TokenGroup[]>(() => {
    const out: TokenGroup[] = [];
    const conds = conditions ?? [];

    // 1. Per-condition tokens.
    conds.forEach((c, i) => {
      const def = getFieldDef(c.field);
      out.push({
        heading: `Condition ${i + 1}: ${def?.label ?? c.field}`,
        tokens: [
          {
            token: `condition[${i}].field`,
            description: "Field name"
          },
          {
            token: `condition[${i}].operator`,
            description: "Operator"
          },
          {
            token: `condition[${i}].value`,
            description: "Required value"
          }
        ]
      });
    });

    // 2. Item ctx tokens — always populated regardless of surface.
    //    Includes display-only tokens (`item.id`, `item.name`) on top of
    //    the predicate-eligible fields from `FIELD_REGISTRY`.
    const itemFields = FIELD_REGISTRY.filter((f) => f.context === "item");
    const itemTokens: TokenItem[] = [
      // `item.id` is the readable id (e.g. "PART-001"), not the UUID — see
      // `evaluateLinesForSurface` where the ctx is normalised.
      { token: "item.id", description: "Readable ID (e.g. PART-001)" },
      { token: "item.name", description: "Display name" },
      ...itemFields.map((f) => ({ token: f.path, description: f.label }))
    ];
    out.push({ heading: CONTEXT_LABELS.item, tokens: itemTokens });

    // 3. Surface-relevant ctx tokens. Compute the union of ctx keys
    //    populated by any selected surface; hide groups no surface uses.
    const allowedCtx = new Set<FieldDef["context"]>();
    for (const s of surfaces) {
      for (const k of CTX_KEYS_BY_SURFACE[s] ?? []) allowedCtx.add(k);
    }
    const orderedCtx: FieldDef["context"][] = ["storage", "transaction"];
    for (const ctxKey of orderedCtx) {
      if (!allowedCtx.has(ctxKey)) continue;
      const fields = FIELD_REGISTRY.filter((f) => f.context === ctxKey);
      if (fields.length === 0) continue;
      out.push({
        heading: CONTEXT_LABELS[ctxKey],
        tokens: fields.map((f) => ({
          token: f.path,
          description: f.label
        }))
      });
    }

    return out;
  }, [conditions, surfaces]);

  return (
    <div className="w-full" ref={setRefFromDom}>
      <TextArea
        name={name}
        label={label ?? t`Message`}
        placeholder={t`Shown to the user when this rule fails. Use {item.name} or other tokens.`}
      />
      <HStack className="justify-end mt-2">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="sm" leftIcon={<LuBraces />}>
              <Trans>Insert token</Trans>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent className="max-h-[420px] overflow-y-auto">
            {groups.map((group, gi) => (
              <DropdownMenuGroup key={`${group.heading}-${gi}`}>
                {gi > 0 && <DropdownMenuSeparator />}
                <DropdownMenuLabel className="text-[10px] font-semibold uppercase tracking-wider">
                  {group.heading}
                </DropdownMenuLabel>
                {group.tokens.map((tok) => (
                  <DropdownMenuItem
                    key={tok.token}
                    onClick={() => insertToken(tok.token)}
                    className="flex items-center gap-2"
                  >
                    <span className="font-mono text-xs">{`{${tok.token}}`}</span>
                    <span className="text-muted-foreground text-xs">
                      {tok.description}
                    </span>
                  </DropdownMenuItem>
                ))}
              </DropdownMenuGroup>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      </HStack>
    </div>
  );
}
