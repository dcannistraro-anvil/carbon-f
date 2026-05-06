import { Status } from "@carbon/react";
import type { intercompanyTransactionStatuses } from "../../accounting.models";

type IntercompanyTransactionStatusProps = {
  status?: (typeof intercompanyTransactionStatuses)[number] | null;
};

const IntercompanyTransactionStatus = ({
  status
}: IntercompanyTransactionStatusProps) => {
  switch (status) {
    case "Unmatched":
      return <Status color="orange">{status}</Status>;
    case "Matched":
      return <Status color="green">{status}</Status>;
    case "Eliminated":
      return <Status color="gray">{status}</Status>;
    default:
      return null;
  }
};

export default IntercompanyTransactionStatus;
