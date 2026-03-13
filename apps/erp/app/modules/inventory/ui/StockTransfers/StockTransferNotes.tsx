import { useCarbon } from "@carbon/auth";
import type { JSONContent } from "@carbon/react";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  generateHTML,
  toast,
  useDebounce
} from "@carbon/react";
import { Editor } from "@carbon/react/Editor";
import { getLocalTimeZone, today } from "@internationalized/date";
import { nanoid } from "nanoid";
import { useState } from "react";
import { usePermissions, useRouteData, useUser } from "~/hooks";
import { isStockTransferLocked, type StockTransfer } from "~/modules/inventory";
import { getPrivateUrl, path } from "~/utils/path";

const ShipmentNotes = ({
  id,
  notes: initialNotes
}: {
  id: string | null;
  notes?: JSONContent;
}) => {
  const {
    id: userId,
    company: { id: companyId }
  } = useUser();
  const { carbon } = useCarbon();
  const permissions = usePermissions();
  const routeData = useRouteData<{
    stockTransfer: StockTransfer;
  }>(path.to.stockTransfer(id!));
  const isLocked = isStockTransferLocked(routeData?.stockTransfer?.status);
  const [notes, setNotes] = useState(initialNotes ?? {});

  const onUploadImage = async (file: File) => {
    const fileType = file.name.split(".").pop();
    const fileName = `${companyId}/inventory/${id}/${nanoid()}.${fileType}`;

    const result = await carbon?.storage.from("private").upload(fileName, file);

    if (result?.error) {
      toast.error("Failed to upload image");
      throw new Error(result.error.message);
    }

    if (!result?.data) {
      throw new Error("Failed to upload image");
    }

    return getPrivateUrl(result.data.path);
  };

  const onUpdateNotes = useDebounce(
    async (content: JSONContent) => {
      await carbon
        ?.from("stockTransfer")
        .update({
          notes: content,
          updatedAt: today(getLocalTimeZone()).toString(),
          updatedBy: userId
        })
        .eq("id", id!);
    },
    2500,
    true
  );
  if (!id) return null;

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>Stock Transfer Notes</CardTitle>
        </CardHeader>
        <CardContent>
          {permissions.can("update", "inventory") && !isLocked ? (
            <Editor
              initialValue={(notes ?? {}) as JSONContent}
              onUpload={onUploadImage}
              onChange={(value) => {
                setNotes(value);
                onUpdateNotes(value);
              }}
            />
          ) : (
            <div
              className="prose dark:prose-invert"
              dangerouslySetInnerHTML={{
                __html: generateHTML(notes as JSONContent)
              }}
            />
          )}
        </CardContent>
      </Card>
    </>
  );
};

export default ShipmentNotes;
