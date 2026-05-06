import { Status } from "@carbon/react";
import type { journalEntryStatuses } from "../../accounting.models";

type JournalEntryStatusProps = {
  status?: (typeof journalEntryStatuses)[number] | null;
};

const JournalEntryStatus = ({ status }: JournalEntryStatusProps) => {
  switch (status) {
    case "Draft":
      return <Status color="gray">{status}</Status>;
    case "Posted":
      return <Status color="green">{status}</Status>;
    case "Reversed":
      return <Status color="red">{status}</Status>;
    default:
      return null;
  }
};

export default JournalEntryStatus;
