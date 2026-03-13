import { ValidatedForm } from "@carbon/form";
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle
} from "@carbon/react";
import { useState } from "react";
import { useFetcher, useParams } from "react-router";
import type { z } from "zod";
import {
  // biome-ignore lint/suspicious/noShadowRestrictedNames: suppressed due to migration
  Boolean,
  CustomFormFields,
  Hidden,
  PaymentTerm,
  Submit,
  Supplier,
  SupplierContact,
  SupplierLocation
} from "~/components/Form";
import { usePermissions, useRouteData } from "~/hooks";
import {
  isPurchaseOrderLocked,
  purchaseOrderPaymentValidator
} from "~/modules/purchasing";
import type { action } from "~/routes/x+/purchase-order+/$orderId.payment";
import { path } from "~/utils/path";

type PurchaseOrderPaymentFormProps = {
  initialValues: z.infer<typeof purchaseOrderPaymentValidator>;
};

const PurchaseOrderPaymentForm = ({
  initialValues
}: PurchaseOrderPaymentFormProps) => {
  const { orderId } = useParams();
  if (!orderId) {
    throw new Error("orderId not found");
  }

  const routeData = useRouteData<{
    purchaseOrder: { status: string };
  }>(path.to.purchaseOrder(orderId));

  const isLocked = isPurchaseOrderLocked(routeData?.purchaseOrder?.status);

  const fetcher = useFetcher<typeof action>();
  const permissions = usePermissions();

  const [supplier, setSupplier] = useState<string | undefined>(
    initialValues.invoiceSupplierId
  );

  return (
    <Card>
      <ValidatedForm
        method="post"
        action={path.to.purchaseOrderPayment(orderId)}
        validator={purchaseOrderPaymentValidator}
        defaultValues={initialValues}
        fetcher={fetcher}
        isDisabled={isLocked}
      >
        <CardHeader>
          <CardTitle>Payment</CardTitle>
        </CardHeader>
        <CardContent>
          <Hidden name="id" />
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-x-8 gap-y-4 w-full">
            <Supplier
              name="invoiceSupplierId"
              label="Invoice Supplier"
              onChange={(value) => setSupplier(value?.value as string)}
            />
            <SupplierLocation
              name="invoiceSupplierLocationId"
              label="Invoice Location"
              supplier={supplier}
            />
            <SupplierContact
              name="invoiceSupplierContactId"
              label="Invoice Contact"
              supplier={supplier}
            />

            <PaymentTerm name="paymentTermId" label="Payment Terms" />

            <Boolean name="paymentComplete" label="Payment Complete" />
            <CustomFormFields table="purchaseOrderPayment" />
          </div>
        </CardContent>
        <CardFooter>
          <Submit isDisabled={!permissions.can("update", "purchasing")}>
            Save
          </Submit>
        </CardFooter>
      </ValidatedForm>
    </Card>
  );
};

export default PurchaseOrderPaymentForm;
