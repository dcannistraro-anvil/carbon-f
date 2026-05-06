import { Transaction } from "kysely";
import { DB } from "../lib/database.ts";

export interface CostLayer {
  costLedgerId: string;
  quantityConsumed: number;
  unitCost: number;
}

export interface COGSResult {
  unitCost: number;
  totalCost: number;
  layersConsumed: CostLayer[];
}

export async function calculateCOGS(
  trx: Transaction<DB>,
  {
    itemId,
    quantity,
    companyId,
  }: {
    itemId: string;
    quantity: number;
    companyId: string;
  }
): Promise<COGSResult> {
  const itemCost = await trx
    .selectFrom("itemCost")
    .selectAll()
    .where("itemId", "=", itemId)
    .where("companyId", "=", companyId)
    .executeTakeFirstOrThrow();

  const costingMethod = itemCost.costingMethod;

  switch (costingMethod) {
    case "Standard": {
      const standardCost = Number(itemCost.standardCost ?? 0);
      return {
        unitCost: standardCost,
        totalCost: standardCost * quantity,
        layersConsumed: [],
      };
    }

    case "Average": {
      const unitCost = Number(itemCost.unitCost ?? 0);
      return {
        unitCost,
        totalCost: unitCost * quantity,
        layersConsumed: [],
      };
    }

    case "FIFO":
    case "LIFO": {
      const orderDirection = costingMethod === "FIFO" ? "asc" : "desc";

      const layers = await trx
        .selectFrom("costLedger")
        .selectAll()
        .where("itemId", "=", itemId)
        .where("companyId", "=", companyId)
        .where("remainingQuantity", ">", 0)
        .orderBy("postingDate", orderDirection)
        .orderBy("createdAt", orderDirection)
        .execute();

      let remainingToConsume = quantity;
      let totalCost = 0;
      const layersConsumed: CostLayer[] = [];

      for (const layer of layers) {
        if (remainingToConsume <= 0) break;

        const layerRemaining = Number(layer.remainingQuantity);
        const layerUnitCost =
          Number(layer.quantity) > 0
            ? Number(layer.cost) / Number(layer.quantity)
            : 0;

        const quantityFromLayer = Math.min(remainingToConsume, layerRemaining);
        const costFromLayer = quantityFromLayer * layerUnitCost;

        totalCost += costFromLayer;
        remainingToConsume -= quantityFromLayer;

        layersConsumed.push({
          costLedgerId: layer.id,
          quantityConsumed: quantityFromLayer,
          unitCost: layerUnitCost,
        });

        await trx
          .updateTable("costLedger")
          .set({
            remainingQuantity: layerRemaining - quantityFromLayer,
          })
          .where("id", "=", layer.id)
          .execute();
      }

      // Fallback: insufficient layers (negative inventory scenario)
      if (remainingToConsume > 0) {
        const fallbackUnitCost = Number(itemCost.unitCost ?? 0);
        totalCost += remainingToConsume * fallbackUnitCost;
      }

      const effectiveUnitCost = quantity > 0 ? totalCost / quantity : 0;

      return {
        unitCost: effectiveUnitCost,
        totalCost,
        layersConsumed,
      };
    }

    default:
      throw new Error(`Unsupported costing method: ${costingMethod}`);
  }
}
