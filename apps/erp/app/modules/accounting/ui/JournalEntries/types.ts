export type ClientJournalLine = {
  id: string;
  accountId: string;
  description: string;
  debit: number | null;
  credit: number | null;
  dimensions: JournalLineDimensionValue[];
};

export type DimensionWithValues = {
  dimensionId: string;
  dimensionName: string;
  entityType: string;
  required: boolean;
  values: { id: string; name: string }[];
};

export type JournalLineDimensionValue = {
  dimensionId: string;
  dimensionName: string;
  valueId: string;
  valueName: string;
};
