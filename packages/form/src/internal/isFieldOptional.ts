import { z } from "zod";
import { stringToPathArray } from "../utils";

type ZodSchema = z.ZodTypeAny;

function unwrapSchema(schema: ZodSchema): {
  schema: ZodSchema;
  isOptional: boolean;
} {
  let current: ZodSchema = schema;
  let isOptional = false;

  while (true) {
    if (
      current instanceof z.ZodOptional ||
      current instanceof z.ZodDefault ||
      current instanceof z.ZodCatch
    ) {
      isOptional = true;
      current = current._def.innerType;
      continue;
    }

    if (current instanceof z.ZodEffects) {
      current = current._def.schema;
      continue;
    }

    if (current instanceof z.ZodNullable) {
      current = current.unwrap();
      continue;
    }

    if (current instanceof z.ZodBranded) {
      current = current.unwrap();
      continue;
    }

    if (current instanceof z.ZodReadonly) {
      current = current.unwrap();
      continue;
    }

    if (current instanceof z.ZodPipeline) {
      current = current._def.out;
      continue;
    }

    return { schema: current, isOptional };
  }
}

function getChildSchema(
  schema: ZodSchema,
  segment: string | number
): ZodSchema | null {
  if (schema instanceof z.ZodObject) {
    const shape = schema.shape;
    if (typeof segment !== "string") return null;
    return shape[segment] ?? null;
  }

  if (schema instanceof z.ZodArray) {
    return schema.element;
  }

  if (schema instanceof z.ZodTuple) {
    const index =
      typeof segment === "number"
        ? segment
        : Number.isNaN(Number(segment))
          ? null
          : Number(segment);
    if (index === null) return null;
    return schema.items[index] ?? null;
  }

  if (schema instanceof z.ZodRecord) {
    return schema._def.valueType;
  }

  return null;
}

export function isFieldOptional(
  schema: ZodSchema | undefined,
  fieldName: string
): boolean | undefined {
  if (!schema || !fieldName) return undefined;

  const path = stringToPathArray(fieldName);
  let current: ZodSchema | null = schema;
  let optionalFromParent = false;

  for (const segment of path) {
    if (!current) return undefined;

    const unwrapped = unwrapSchema(current);
    current = unwrapped.schema;
    optionalFromParent = optionalFromParent || unwrapped.isOptional;

    current = getChildSchema(current, segment);
  }

  if (!current) return undefined;

  const final = unwrapSchema(current);
  return optionalFromParent || final.isOptional;
}
