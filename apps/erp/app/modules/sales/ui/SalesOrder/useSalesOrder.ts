import { useCallback } from "react";
import { useNavigate, useSubmit } from "react-router";
import { path } from "~/utils/path";
import type { SalesOrder } from "../../types";

export const useSalesOrder = () => {
  const navigate = useNavigate();
  const submit = useSubmit();

  const edit = useCallback(
    (salesOrder: SalesOrder) => navigate(path.to.salesOrder(salesOrder.id!)),
    [navigate]
  );

  const invoice = useCallback(
    (salesOrder: SalesOrder) =>
      navigate(
        `${path.to.newSalesInvoice}?sourceDocument=Sales Order&sourceDocumentId=${salesOrder.id}`
      ),
    [navigate]
  );

  const ship = useCallback(
    (salesOrder: SalesOrder) => {
      const formData = new FormData();
      formData.set("sourceDocument", "Sales Order");
      formData.set("sourceDocumentId", salesOrder.id!);
      submit(formData, { method: "post", action: path.to.newShipment });
    },
    [submit]
  );

  return {
    edit,
    invoice,
    ship
  };
};
