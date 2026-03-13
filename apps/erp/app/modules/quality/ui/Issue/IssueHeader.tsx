import {
  Button,
  Copy,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuIcon,
  DropdownMenuItem,
  DropdownMenuTrigger,
  Heading,
  HStack,
  IconButton,
  useDisclosure,
  VStack
} from "@carbon/react";
import {
  LuChevronDown,
  LuCircleCheck,
  LuCirclePlay,
  LuEllipsisVertical,
  LuExternalLink,
  LuFile,
  LuLoaderCircle,
  LuTrash
} from "react-icons/lu";
import { Link, useFetcher, useParams } from "react-router";
import ConfirmDelete from "~/components/Modals/ConfirmDelete";
import { usePermissions, useRouteData } from "~/hooks";
import { useSuppliers } from "~/stores/suppliers";
import { path } from "~/utils/path";
import { isIssueLocked } from "../../quality.models";
import type { Issue } from "../../types";
import IssueStatus from "./IssueStatus";

const IssueHeader = () => {
  const { id } = useParams();
  if (!id) throw new Error("id not found");

  const routeData = useRouteData<{
    nonConformance: Issue;
    suppliers: { supplierId: string; externalLinkId: string | null }[];
  }>(path.to.issue(id));

  const status = routeData?.nonConformance?.status;
  const permissions = usePermissions();
  const statusFetcher = useFetcher<{}>();
  const [suppliers] = useSuppliers();
  const deleteIssueModal = useDisclosure();

  return (
    <>
      <div className="flex flex-shrink-0 items-center justify-between px-4 py-2 bg-card border-b border-border h-[50px] overflow-x-auto scrollbar-hide dark:border-none dark:shadow-[inset_0_0_1px_rgb(255_255_255_/_0.24),_0_0_0_0.5px_rgb(0,0,0,1),0px_0px_4px_rgba(0,_0,_0,_0.08)]">
        <VStack spacing={0}>
          <HStack>
            <Link to={path.to.issueDetails(id)}>
              <Heading size="h4" className="flex items-center gap-2">
                {/* <ModuleIcon icon={<MethodItemTypeIcon type="Part" />} /> */}
                <span>{routeData?.nonConformance?.nonConformanceId}</span>
              </Heading>
            </Link>
            <IssueStatus status={status} />
            <Copy text={routeData?.nonConformance?.nonConformanceId ?? ""} />
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <IconButton
                  aria-label="More options"
                  icon={<LuEllipsisVertical />}
                  variant="secondary"
                  size="sm"
                />
              </DropdownMenuTrigger>
              <DropdownMenuContent>
                <DropdownMenuItem
                  destructive
                  disabled={
                    !permissions.can("delete", "quality") ||
                    !permissions.is("employee") ||
                    isIssueLocked(status)
                  }
                  onClick={deleteIssueModal.onOpen}
                >
                  <DropdownMenuIcon icon={<LuTrash />} />
                  Delete Issue
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </HStack>
        </VStack>

        <HStack>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                leftIcon={<LuFile />}
                variant="secondary"
                rightIcon={<LuChevronDown />}
              >
                Reports
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent>
              {routeData?.suppliers?.map((s) => {
                if (!s.externalLinkId) return null;
                const supplier = suppliers.find(
                  (sup) => sup.id === s.supplierId
                );
                return (
                  <DropdownMenuItem key={s.supplierId} asChild>
                    <Link to={path.to.externalScar(s.externalLinkId)}>
                      <DropdownMenuIcon icon={<LuExternalLink />} />
                      {supplier?.name} SCAR
                    </Link>
                  </DropdownMenuItem>
                );
              })}
              <DropdownMenuItem asChild>
                <a
                  target="_blank"
                  href={path.to.file.nonConformance(id)}
                  rel="noreferrer"
                >
                  <DropdownMenuIcon icon={<LuFile />} />
                  Report
                </a>
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <statusFetcher.Form method="post" action={path.to.issueStatus(id)}>
            <input type="hidden" name="status" value="In Progress" />
            <Button
              type="submit"
              leftIcon={<LuCirclePlay />}
              variant={status === "Registered" ? "primary" : "secondary"}
              isDisabled={
                status !== "Registered" ||
                statusFetcher.state !== "idle" ||
                !permissions.can("update", "quality")
              }
              isLoading={
                statusFetcher.state !== "idle" &&
                statusFetcher.formData?.get("status") === "In Progress"
              }
            >
              Start
            </Button>
          </statusFetcher.Form>

          <statusFetcher.Form method="post" action={path.to.issueStatus(id)}>
            <input type="hidden" name="status" value="Closed" />
            <Button
              type="submit"
              leftIcon={<LuCircleCheck />}
              variant={status === "In Progress" ? "primary" : "secondary"}
              isDisabled={
                status !== "In Progress" ||
                statusFetcher.state !== "idle" ||
                !permissions.can("update", "quality")
              }
              isLoading={
                statusFetcher.state !== "idle" &&
                statusFetcher.formData?.get("status") === "Closed"
              }
            >
              Complete
            </Button>
          </statusFetcher.Form>

          <statusFetcher.Form method="post" action={path.to.issueStatus(id)}>
            <input type="hidden" name="status" value="Registered" />
            <Button
              type="submit"
              leftIcon={<LuLoaderCircle />}
              variant={status === "Closed" ? "primary" : "secondary"}
              isDisabled={
                !["In Progress", "Closed"].includes(status ?? "") ||
                statusFetcher.state !== "idle" ||
                !permissions.can("update", "quality")
              }
            >
              Reopen
            </Button>
          </statusFetcher.Form>
        </HStack>
      </div>
      {deleteIssueModal.isOpen && (
        <ConfirmDelete
          action={path.to.deleteIssue(id)}
          isOpen={deleteIssueModal.isOpen}
          name={routeData?.nonConformance?.nonConformanceId!}
          text={`Are you sure you want to delete ${routeData?.nonConformance
            ?.nonConformanceId!}? This cannot be undone.`}
          onCancel={() => {
            deleteIssueModal.onClose();
          }}
          onSubmit={() => {
            deleteIssueModal.onClose();
          }}
        />
      )}
    </>
  );
};

export default IssueHeader;
