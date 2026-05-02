import { useRouteData } from "@carbon/remix";
import { useEffect, useState } from "react";
import { path } from "~/utils/path";

export function useSupplierApprovalRequired(): boolean {
  const routeData = useRouteData<{
    supplierApprovalRequired: Promise<boolean>;
  }>(path.to.authenticatedRoot);
  const [value, setValue] = useState(false);

  useEffect(() => {
    routeData?.supplierApprovalRequired
      ?.then((v) => setValue(!!v))
      ?.catch(() => {});
  }, [routeData?.supplierApprovalRequired]);

  return value;
}
