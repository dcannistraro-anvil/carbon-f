import type { ColumnDef } from "@tanstack/react-table";
import type { ReactNode } from "react";
import { memo, useMemo } from "react";
import {
  LuBuilding2,
  LuCircleDollarSign,
  LuFileText,
  LuStar
} from "react-icons/lu";
import { Table } from "~/components";
import { intercompanyTransactionStatuses } from "../../accounting.models";
import IntercompanyTransactionStatus from "./IntercompanyTransactionStatus";

type IntercompanyTransaction = {
  id: string;
  sourceCompanyId: string;
  targetCompanyId: string;
  amount: number;
  currencyCode: string;
  description: string | null;
  status: string;
  documentType: string | null;
  createdAt: string;
  sourceCompany: { name: string } | null;
  targetCompany: { name: string } | null;
};

type IntercompanyTransactionTableProps = {
  data: IntercompanyTransaction[];
  count: number;
  primaryAction?: ReactNode;
};

const IntercompanyTransactionTable = memo(
  ({ data, count, primaryAction }: IntercompanyTransactionTableProps) => {
    const columns = useMemo<ColumnDef<IntercompanyTransaction>[]>(() => {
      const defaultColumns: ColumnDef<IntercompanyTransaction>[] = [
        {
          accessorKey: "sourceCompany",
          header: "Source",
          cell: ({ row }) => row.original.sourceCompany?.name ?? "—",
          meta: {
            icon: <LuBuilding2 />
          }
        },
        {
          accessorKey: "targetCompany",
          header: "Target",
          cell: ({ row }) => row.original.targetCompany?.name ?? "—",
          meta: {
            icon: <LuBuilding2 />
          }
        },
        {
          accessorKey: "amount",
          header: "Amount",
          cell: ({ row }) => {
            const formatted = new Intl.NumberFormat("en-US", {
              style: "currency",
              currency: row.original.currencyCode || "USD"
            }).format(row.original.amount);
            return formatted;
          },
          meta: {
            icon: <LuCircleDollarSign />
          }
        },
        {
          accessorKey: "description",
          header: "Description",
          cell: ({ row }) => (
            <div className="max-w-[240px] truncate">
              {row.original.description || row.original.documentType || "—"}
            </div>
          ),
          meta: {
            icon: <LuFileText />
          }
        },
        {
          accessorKey: "status",
          header: "Status",
          cell: ({ row }) => (
            <IntercompanyTransactionStatus
              status={
                row.original
                  .status as (typeof intercompanyTransactionStatuses)[number]
              }
            />
          ),
          meta: {
            filter: {
              type: "static",
              options: intercompanyTransactionStatuses.map((v) => ({
                label: v,
                value: v
              }))
            },
            icon: <LuStar />
          }
        },
        {
          accessorKey: "createdAt",
          header: "Created",
          cell: ({ row }) =>
            new Date(row.original.createdAt).toLocaleDateString()
        }
      ];
      return defaultColumns;
    }, []);

    return (
      <Table<IntercompanyTransaction>
        data={data}
        columns={columns}
        count={count}
        primaryAction={primaryAction}
        title="Intercompany Transactions"
      />
    );
  }
);

IntercompanyTransactionTable.displayName = "IntercompanyTransactionTable";
export default IntercompanyTransactionTable;
