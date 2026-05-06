type AccountType = "asset" | "liability" | "equity" | "revenue" | "expense";
type AccountClass = "Asset" | "Liability" | "Equity" | "Revenue" | "Expense";

export const credit = (accountType: AccountType, amount: number) => {
  switch (accountType) {
    case "asset":
    case "expense":
      return -amount;
    case "liability":
    case "equity":
    case "revenue":
      return amount;
    default:
      throw new Error(`Invalid account type: ${accountType}`);
  }
};

export const debit = (accountType: AccountType, amount: number) => {
  switch (accountType) {
    case "asset":
    case "expense":
      return amount;
    case "liability":
    case "equity":
    case "revenue":
      return -amount;
    default:
      throw new Error(`Invalid account type: ${accountType}`);
  }
};

function isNaturalDebitAccount(cls: AccountClass): boolean {
  return cls === "Asset" || cls === "Expense";
}

export function toDisplayDebit(
  amount: number,
  accountClass: AccountClass
): number {
  const isDebit = isNaturalDebitAccount(accountClass) ? amount > 0 : amount < 0;
  return isDebit ? Math.abs(amount) : 0;
}

export function toDisplayCredit(
  amount: number,
  accountClass: AccountClass
): number {
  const isCredit = isNaturalDebitAccount(accountClass)
    ? amount < 0
    : amount > 0;
  return isCredit ? Math.abs(amount) : 0;
}

export function toStoredAmount(
  debitAmount: number,
  creditAmount: number,
  accountClass: AccountClass
): number {
  const type = accountClass.toLowerCase() as AccountType;
  if (debitAmount > 0) return debit(type, debitAmount);
  return credit(type, creditAmount);
}
