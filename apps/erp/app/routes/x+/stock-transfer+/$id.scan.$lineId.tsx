import type { Result } from "@carbon/auth";
import { error, success, useCarbon } from "@carbon/auth";
import { requirePermissions } from "@carbon/auth/auth.server";
import { flash } from "@carbon/auth/session.server";
import { Hidden, ValidatedForm } from "@carbon/form";
import {
  Alert,
  AlertTitle,
  Button,
  cn,
  Input,
  InputGroup,
  InputRightElement,
  Modal,
  ModalBody,
  ModalContent,
  ModalDescription,
  ModalFooter,
  ModalHeader,
  ModalTitle,
  toast
} from "@carbon/react";
import { useEffect, useState } from "react";
import {
  LuCheck,
  LuCircleCheck,
  LuQrCode,
  LuTriangleAlert,
  LuX
} from "react-icons/lu";
import type { ActionFunctionArgs } from "react-router";
import {
  data,
  redirect,
  useFetcher,
  useNavigate,
  useParams
} from "react-router";
import { useRouteData } from "~/hooks";
import type { StockTransfer, StockTransferLine } from "~/modules/inventory";
import {
  getStockTransfer,
  isStockTransferLocked,
  stockTransferLineScanValidator
} from "~/modules/inventory";
import { getItemShelfQuantities } from "~/modules/items";
import { requireUnlocked } from "~/utils/lockedGuard.server";
import { path } from "~/utils/path";

export async function action({ request, params }: ActionFunctionArgs) {
  const { client, companyId, userId } = await requirePermissions(request, {
    update: "inventory"
  });

  const { id } = params;
  if (!id) throw new Error("id is not found");

  const { client: viewClient } = await requirePermissions(request, {
    view: "inventory"
  });
  const transfer = await getStockTransfer(viewClient, id);
  await requireUnlocked({
    request,
    isLocked: isStockTransferLocked(transfer.data?.status),
    redirectTo: path.to.stockTransfer(id),
    message: "Cannot modify a locked stock transfer. Reopen it first."
  });

  const payload = await request.json();
  const validated = stockTransferLineScanValidator.safeParse(payload);
  if (!validated.success) {
    return data(
      { success: false, message: "Invalid form data" },
      await flash(request, error(validated.error.message, "Invalid form data"))
    );
  }

  const {
    id: lineId,
    stockTransferId,
    itemId,
    locationId,
    trackedEntityId
  } = validated.data;

  const [stockTransferLine, itemShelfQuantities] = await Promise.all([
    client.from("stockTransferLines").select("*").eq("id", lineId!).single(),
    getItemShelfQuantities(client, itemId, companyId, locationId)
  ]);

  if (stockTransferLine.error || itemShelfQuantities.error) {
    return data(
      {
        success: false,
        message: "Failed to load stock transfer line or item shelf quantities"
      },
      await flash(
        request,
        error(
          stockTransferLine.error || itemShelfQuantities.error,
          "Failed to load stock transfer line or item shelf quantities"
        )
      )
    );
  }

  const currentShelfId =
    itemShelfQuantities.data
      ?.sort((a, b) => b.quantity - a.quantity)
      .find((q) => q.trackedEntityId === trackedEntityId)?.shelfId ?? null;

  // Determine the type of transfer based on tracking requirements
  const transferType = stockTransferLine.data?.requiresBatchTracking
    ? "batch"
    : "serial";

  // Prepare the payload for the post-stock-transfer function
  const functionPayload: any = {
    type: transferType,
    stockTransferId,
    stockTransferLineId: lineId,
    trackedEntityId,
    quantity:
      transferType === "batch" ? (stockTransferLine.data?.quantity ?? 1) : 1,
    fromShelfId: currentShelfId,
    locationId: locationId,
    userId,
    companyId
  };

  const { error: functionError } = await client.functions.invoke(
    "post-stock-transfer",
    {
      body: JSON.stringify(functionPayload)
    }
  );

  if (functionError) {
    return data(
      { success: false, message: "Failed to pick line" },
      await flash(
        request,
        error(
          functionError.message || "Failed to pick line",
          "Failed to pick line"
        )
      )
    );
  }

  throw redirect(
    path.to.stockTransfer(stockTransferId),
    await flash(request, success("Tracked entity scanned and transferred"))
  );
}

export default function StockTransferScan() {
  const { id, lineId } = useParams();
  if (!id) throw new Error("id not found");
  if (!lineId) throw new Error("lineId not found");
  const routeData = useRouteData<{
    stockTransfer: StockTransfer;
    stockTransferLines: StockTransferLine[];
  }>(path.to.stockTransfer(id));

  const stockTransferLine = routeData?.stockTransferLines.find(
    (line) => line.id === lineId
  );

  if (!stockTransferLine) throw new Error("stock transfer line not found");

  const navigate = useNavigate();
  const onClose = () =>
    navigate(path.to.stockTransfer(stockTransferLine.stockTransferId!));

  const { carbon } = useCarbon();
  const [isLoading, setIsLoading] = useState(false);
  const [validationError, setValidationError] = useState<string | null>(null);
  const [isValid, setIsValid] = useState<boolean | null>(null);
  const [serialNumber, setSerialNumber] = useState("");

  const fetcher = useFetcher<Result>();

  useEffect(() => {
    if (fetcher.data?.success === false) {
      toast.error(fetcher.data.message);
    }
  }, [fetcher.data?.message, fetcher.data?.success]);

  const locationId =
    useRouteData<{
      stockTransfer: StockTransfer;
    }>(path.to.stockTransfer(stockTransferLine.stockTransferId!))?.stockTransfer
      .locationId ?? "";

  const onPick = (trackedEntityId?: string) => {
    fetcher.submit(
      {
        id: stockTransferLine.id!,
        stockTransferId: stockTransferLine.stockTransferId!,
        trackedEntityId: trackedEntityId!,
        itemId: stockTransferLine.itemId!,
        locationId: locationId
      },
      {
        method: "POST",
        encType: "application/json"
      }
    );
  };

  const validateTrackedEntity = async (trackedEntityId: string) => {
    if (!trackedEntityId.trim()) {
      setValidationError(null);
      setIsValid(null);
      return;
    }

    if (
      routeData?.stockTransferLines.some(
        (line) => line.trackedEntityId === trackedEntityId
      )
    ) {
      setValidationError("Tracked entity already picked");
      setIsValid(false);
      return;
    }

    setIsLoading(true);
    setValidationError(null);
    setIsValid(null);

    try {
      const result = await carbon
        ?.from("trackedEntity")
        .select("*")
        .eq("id", trackedEntityId)
        .eq("companyId", stockTransferLine.companyId!)
        .single();

      if (result?.error || !result?.data) {
        setValidationError("Serial number not found");
        setIsValid(false);
      } else if (result.data.status !== "Available") {
        setValidationError(`Entity is ${result.data.status}`);
        setIsValid(false);
      } else if (result.data.sourceDocumentId !== stockTransferLine.itemId!) {
        setValidationError(
          `Item ${result.data.sourceDocumentReadableId} is not the same as the item ${stockTransferLine.itemReadableId}`
        );
        setIsValid(false);
      } else {
        setValidationError(null);
        setIsValid(true);
        onPick(trackedEntityId);
      }
      // biome-ignore lint/correctness/noUnusedVariables: suppressed due to migration
    } catch (error) {
      setValidationError("Error validating serial number");
      setIsValid(false);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSerialNumberChange = (value: string) => {
    setSerialNumber(value);
    // Clear validation state when user types
    if (validationError || isValid !== null) {
      setValidationError(null);
      setIsValid(null);
    }
  };

  const handleBlur = () => {
    validateTrackedEntity(serialNumber);
  };

  const handleKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === "Enter") {
      event.preventDefault();
      validateTrackedEntity(serialNumber);
    }
  };

  return (
    <Modal
      open
      onOpenChange={(open) => {
        if (!open) {
          onClose();
        }
      }}
    >
      <ValidatedForm
        method="post"
        validator={stockTransferLineScanValidator}
        defaultValues={{
          id: stockTransferLine.id!,
          stockTransferId: stockTransferLine.stockTransferId!,
          itemId: stockTransferLine.itemId!,
          locationId: locationId,
          trackedEntityId: ""
        }}
      >
        <ModalContent>
          <ModalHeader>
            <ModalTitle>{stockTransferLine?.itemReadableId}</ModalTitle>
            <ModalDescription>
              Scan the tracking ID for this line
            </ModalDescription>
          </ModalHeader>
          <ModalBody>
            <Hidden name="id" />
            <Hidden name="stockTransferId" />
            <Hidden name="itemId" />
            <Hidden name="locationId" />

            <div className="space-y-4">
              {validationError && (
                <Alert variant="destructive">
                  <LuTriangleAlert className="h-4 w-4" />
                  <AlertTitle>{validationError}</AlertTitle>
                </Alert>
              )}
              <InputGroup>
                <Input
                  name="trackedEntityId"
                  value={serialNumber}
                  isDisabled={fetcher.state !== "idle"}
                  onChange={(e) => handleSerialNumberChange(e.target.value)}
                  onBlur={handleBlur}
                  onKeyDown={handleKeyDown}
                  autoFocus
                  placeholder="Enter or scan serial number"
                  className={cn(
                    validationError && "border-destructive",
                    isValid && "border-emerald-500"
                  )}
                  disabled={isLoading}
                />
                <InputRightElement className="pl-2">
                  {isLoading ? (
                    <div className="animate-spin h-4 w-4 border-2 border-gray-300 border-t-gray-600 rounded-full" />
                  ) : validationError ? (
                    <LuX className="text-destructive" />
                  ) : isValid ? (
                    <LuCheck className="text-emerald-500" />
                  ) : (
                    <LuQrCode />
                  )}
                </InputRightElement>
              </InputGroup>
            </div>
          </ModalBody>
          <ModalFooter>
            <Button
              variant="secondary"
              isDisabled={fetcher.state !== "idle"}
              onClick={() => onClose()}
            >
              Cancel
            </Button>
            <Button
              leftIcon={<LuCircleCheck />}
              isLoading={fetcher.state !== "idle"}
              isDisabled={fetcher.state !== "idle"}
              onClick={() => validateTrackedEntity(serialNumber)}
            >
              Pick
            </Button>
          </ModalFooter>
        </ModalContent>
      </ValidatedForm>
    </Modal>
  );
}
