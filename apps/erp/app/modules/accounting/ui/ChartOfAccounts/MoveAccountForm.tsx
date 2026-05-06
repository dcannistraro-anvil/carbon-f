import { ValidatedForm } from "@carbon/form";
import {
  Button,
  HStack,
  ModalDrawer,
  ModalDrawerBody,
  ModalDrawerContent,
  ModalDrawerFooter,
  ModalDrawerHeader,
  ModalDrawerProvider,
  ModalDrawerTitle,
  toast,
  VStack
} from "@carbon/react";
import { useEffect } from "react";
import { useFetcher } from "react-router";
import { Combobox, Hidden, Submit } from "~/components/Form";
import { usePermissions } from "~/hooks";
import { path } from "~/utils/path";
import { moveAccountValidator } from "../../accounting.models";

type MoveAccountFormProps = {
  accountId: string;
  accountName: string;
  groupAccounts: {
    id: string;
    name: string;
    incomeBalance: string;
    class: string | null;
  }[];
  currentParentId?: string | null;
  open?: boolean;
  onClose: () => void;
};

const MoveAccountForm = ({
  accountId,
  accountName,
  groupAccounts,
  currentParentId,
  open = true,
  onClose
}: MoveAccountFormProps) => {
  const permissions = usePermissions();
  const fetcher = useFetcher();

  useEffect(() => {
    if (fetcher.state === "loading" && fetcher.data?.data) {
      onClose?.();
      toast.success("Moved account");
    } else if (fetcher.state === "idle" && fetcher.data?.error) {
      toast.error(`Failed to move account: ${fetcher.data.error.message}`);
    }
  }, [fetcher.data, fetcher.state, onClose]);

  const isDisabled = !permissions.can("update", "accounting");

  return (
    <ModalDrawerProvider type="modal">
      <ModalDrawer
        open={open}
        onOpenChange={(open) => {
          if (!open) onClose?.();
        }}
      >
        <ModalDrawerContent>
          <ValidatedForm
            validator={moveAccountValidator}
            method="post"
            action={path.to.moveChartOfAccount(accountId)}
            defaultValues={{
              id: accountId,
              parentId: currentParentId ?? undefined
            }}
            fetcher={fetcher}
            className="flex flex-col h-full"
          >
            <ModalDrawerHeader>
              <ModalDrawerTitle>Move {accountName}</ModalDrawerTitle>
            </ModalDrawerHeader>
            <ModalDrawerBody>
              <Hidden name="id" />
              <VStack spacing={4}>
                <p className="text-sm text-muted-foreground">
                  Select a new parent group for this account.
                </p>
                <Combobox
                  name="parentId"
                  label="Move to Group"
                  options={groupAccounts.map((a) => ({
                    label: a.name,
                    value: a.id
                  }))}
                />
              </VStack>
            </ModalDrawerBody>
            <ModalDrawerFooter>
              <HStack>
                <Submit isDisabled={isDisabled}>Move</Submit>
                <Button size="md" variant="solid" onClick={() => onClose?.()}>
                  Cancel
                </Button>
              </HStack>
            </ModalDrawerFooter>
          </ValidatedForm>
        </ModalDrawerContent>
      </ModalDrawer>
    </ModalDrawerProvider>
  );
};

export default MoveAccountForm;
