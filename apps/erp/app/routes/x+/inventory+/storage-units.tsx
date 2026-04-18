import { error } from "@carbon/auth";
import { requirePermissions } from "@carbon/auth/auth.server";
import { flash } from "@carbon/auth/session.server";
import { VStack } from "@carbon/react";
import { msg } from "@lingui/core/macro";
import type { LoaderFunctionArgs } from "react-router";
import { Outlet, redirect, useLoaderData } from "react-router";
import { getStorageTypesList, getStorageUnits } from "~/modules/inventory";
import StorageUnitsTable from "~/modules/inventory/ui/StorageUnits/StorageUnitsTable";
import { getLocationsList } from "~/modules/resources";
import { getUserDefaults } from "~/modules/users/users.server";
import type { Handle } from "~/utils/handle";
import { path } from "~/utils/path";
import { getGenericQueryFilters } from "~/utils/query";

export const handle: Handle = {
  breadcrumb: msg`Storage Units`,
  to: path.to.storageUnits,
  module: "inventory"
};

export async function loader({ request }: LoaderFunctionArgs) {
  const { client, companyId, userId } = await requirePermissions(request, {
    view: "inventory",
    bypassRls: true
  });

  const url = new URL(request.url);
  const searchParams = new URLSearchParams(url.search);
  const search = searchParams.get("search");

  const { limit, offset, sorts, filters } =
    getGenericQueryFilters(searchParams);

  let locationId = searchParams.get("location");

  if (!locationId) {
    const userDefaults = await getUserDefaults(client, userId, companyId);
    if (userDefaults.error) {
      throw redirect(
        path.to.storageUnits,
        await flash(
          request,
          error(userDefaults.error, "Failed to load default location")
        )
      );
    }

    locationId = userDefaults.data?.locationId ?? null;
  }

  // Always fetch the locations list server-side so the Location column can
  // render the resolved name on first paint instead of flashing the raw
  // locationId while the client-side useLocations() fetcher catches up.
  const locationsList = await getLocationsList(client, companyId);
  if (locationsList.error || !locationsList.data?.length) {
    throw redirect(
      path.to.storageUnits,
      await flash(
        request,
        error(locationsList.error, "Failed to load any locations")
      )
    );
  }

  if (!locationId) {
    locationId = locationsList.data[0].id as string;
  }

  const [storageUnits, storageTypesList] = await Promise.all([
    getStorageUnits(client, locationId, companyId, {
      search,
      limit,
      offset,
      sorts,
      filters
    }),
    // Fetch storage types server-side so the Storage Types column can render
    // resolved names on first paint instead of flashing raw ids while the
    // client-side useStorageTypes() fetcher catches up.
    getStorageTypesList(client, companyId)
  ]);

  if (storageUnits.error) {
    throw redirect(
      path.to.authenticatedRoot,
      await flash(
        request,
        error(storageUnits.error, "Failed to fetch storageUnits")
      )
    );
  }

  return {
    count: storageUnits.count ?? 0,
    storageUnits: storageUnits.data ?? [],
    locations: locationsList.data,
    locationId,
    storageTypes: storageTypesList.data ?? []
  };
}

export default function StorageUnitsRoute() {
  const { count, storageUnits, locations, locationId, storageTypes } =
    useLoaderData<typeof loader>();

  // storageUnits comes from storageUnits_recursive (a view) so every column
  // is nominally nullable in the generated types. In practice only roots have
  // a null parentId; id / name / active / companyId / locationId are always
  // populated for rows visible to a user. Narrow by filtering and casting.
  const rows = storageUnits.filter(
    (
      r
    ): r is typeof r & {
      id: string;
      name: string;
      active: boolean;
    } => r.id != null && r.name != null && r.active != null
  );

  return (
    <VStack spacing={0} className="h-full">
      <StorageUnitsTable
        data={rows}
        count={count}
        locations={locations}
        locationId={locationId}
        storageTypes={storageTypes}
      />
      <Outlet />
    </VStack>
  );
}
