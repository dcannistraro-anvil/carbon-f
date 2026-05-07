import type { Integration } from "@carbon/ee";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  useUrlParams
} from "@carbon/react";
import { Trans, useLingui } from "@lingui/react/macro";
import { useMemo, useState } from "react";
import { LuPuzzle } from "react-icons/lu";
import { SearchFilter } from "~/components";
import {
  UpgradeOverlayActions,
  UpgradeOverlayContent,
  UpgradeOverlayDescription,
  UpgradeOverlayIcon,
  UpgradeOverlayStickyGradient,
  UpgradeOverlayTitle,
  UpgradeOverlayUpgradeButton
} from "~/components/UpgradeOverlay";
import { usePlanGate } from "~/hooks/usePlanGate";
import type { IntegrationHealth } from "./IntegrationCard";
import { IntegrationCard } from "./IntegrationCard";

type IntegrationsListProps = {
  availableIntegrations: Integration[];
  integrations: Array<IntegrationHealth>;
};

const IntegrationsList = ({
  integrations,
  availableIntegrations
}: IntegrationsListProps) => {
  const { t } = useLingui();
  const [params] = useUrlParams();
  const [filter, setFilter] = useState<"all" | "installed" | "available">(
    "all"
  );
  const { isGated } = usePlanGate();
  const search = params.get("search") || "";

  const installed = integrations.filter((i) => i.id && i.active);
  const installedIds = installed.map((i) => i.id);

  const filteredIntegrations = useMemo(() => {
    let filtered = availableIntegrations;

    if (search) {
      filtered = filtered.filter((integration) =>
        integration.name.toLowerCase().includes(search.toLowerCase())
      );
    }

    if (filter === "installed") {
      filtered = filtered.filter((integration) =>
        installedIds.includes(integration.id)
      );
    } else if (filter === "available") {
      filtered = filtered.filter(
        (integration) =>
          !installedIds.includes(integration.id) && integration.active
      );
    }

    return filtered;
  }, [availableIntegrations, installedIds, search, filter]);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-row gap-2 pt-4 px-4">
        <div>
          <SearchFilter param="search" size="sm" placeholder={t`Search`} />
        </div>
        <div>
          <Select
            value={filter}
            onValueChange={(value) =>
              setFilter(value as "all" | "installed" | "available")
            }
          >
            <SelectTrigger size="sm">
              <SelectValue placeholder="Select a category" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All</SelectItem>
              <SelectItem value="installed">Installed</SelectItem>
              <SelectItem value="available">Available</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </div>
      <div
        className={`grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3 px-4 w-full ${
          isGated ? "" : "pb-4"
        }`}
      >
        {filteredIntegrations.map((integration) => {
          return (
            <IntegrationCard
              key={integration.id}
              integration={integration}
              installed={installed.find((i) => i.id === integration.id) || null}
            />
          );
        })}
      </div>

      {isGated && (
        <>
          <UpgradeOverlayStickyGradient>
            <UpgradeOverlayIcon>
              <LuPuzzle className="size-6 text-muted-foreground" />
            </UpgradeOverlayIcon>
            <UpgradeOverlayContent>
              <UpgradeOverlayTitle>
                <Trans>Integrations</Trans>
              </UpgradeOverlayTitle>
              <UpgradeOverlayDescription>
                <Trans>
                  Connect Carbon to your accounting, project, and CAD tools and
                  much more.
                </Trans>
              </UpgradeOverlayDescription>
            </UpgradeOverlayContent>
            <UpgradeOverlayActions>
              <UpgradeOverlayUpgradeButton />
            </UpgradeOverlayActions>
          </UpgradeOverlayStickyGradient>
        </>
      )}
    </div>
  );
};

export default IntegrationsList;
