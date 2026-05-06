import { MenuIcon, MenuItem } from "@carbon/react";
import { Trans, useLingui } from "@lingui/react/macro";
import type { ColumnDef } from "@tanstack/react-table";
import { memo, useCallback, useMemo } from "react";
import { LuBookMarked, LuEuro, LuPencil, LuPercent } from "react-icons/lu";
import { useNavigate } from "react-router";
import { Hyperlink, Table } from "~/components";
import { usePermissions, useUrlParams } from "~/hooks";
import { useCustomColumns } from "~/hooks/useCustomColumns";
import { path } from "~/utils/path";
import type { Currency } from "../../types";

type ExchangeRatesTableProps = {
  data: Currency[];
  count: number;
};

const ExchangeRatesTable = memo(({ data, count }: ExchangeRatesTableProps) => {
  const { t } = useLingui();
  const [params] = useUrlParams();
  const navigate = useNavigate();
  const permissions = usePermissions();
  const customColumns = useCustomColumns<Currency>("currency");

  const columns = useMemo<ColumnDef<Currency>[]>(() => {
    const defaultColumns: ColumnDef<Currency>[] = [
      {
        accessorKey: "name",
        header: t`Name`,
        cell: ({ row }) => (
          <Hyperlink to={row.original.id as string}>
            {row.original.name}
          </Hyperlink>
        ),
        meta: {
          icon: <LuBookMarked />
        }
      },
      {
        accessorKey: "code",
        header: t`Code`,
        cell: (item) => item.getValue(),
        meta: {
          icon: <LuEuro />
        }
      },
      {
        accessorKey: "exchangeRate",
        header: t`Exchange Rate`,
        cell: (item) => item.getValue(),
        meta: {
          icon: <LuPercent />
        }
      }
    ];
    return [...defaultColumns, ...customColumns];
  }, [customColumns, t]);

  const renderContextMenu = useCallback(
    (row: Currency) => {
      return (
        <>
          <MenuItem
            disabled={!permissions.can("update", "accounting")}
            onClick={() => {
              navigate(
                `${path.to.exchangeRate(row.id as string)}?${params.toString()}`
              );
            }}
          >
            <MenuIcon icon={<LuPencil />} />
            <Trans>Edit Currency</Trans>
          </MenuItem>
        </>
      );
    },
    [navigate, params, permissions]
  );

  return (
    <Table<Currency>
      data={data}
      columns={columns}
      count={count}
      renderContextMenu={renderContextMenu}
      title={t`Exchange Rates`}
    />
  );
});

ExchangeRatesTable.displayName = "ExchangeRatesTable";
export default ExchangeRatesTable;
