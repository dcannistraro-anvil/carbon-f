import { ValidatedForm } from "@carbon/form";
import { VStack } from "@carbon/react";
import { Trans, useLingui } from "@lingui/react/macro";
import type { z } from "zod";
import { Currency, Hidden, Input, PhoneInput, Submit } from "~/components/Form";
import AddressAutocomplete from "~/components/Form/AddressAutocomplete";
import { companyValidator } from "~/modules/settings";
import { path } from "~/utils/path";

type CompanyFormProps = {
  company: z.infer<typeof companyValidator>;
};

const CompanyForm = ({ company }: CompanyFormProps) => {
  const { t } = useLingui();
  return (
    <>
      <ValidatedForm
        method="post"
        action={path.to.company}
        validator={companyValidator}
        defaultValues={company}
      >
        <Hidden name="intent" value="about" />

        <VStack spacing={4}>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 w-full">
            <Input name="name" label={t`Company Name`} />
            <Input name="taxId" label={t`Tax ID`} />
            <Input name="vatNumber" label={t`VAT Number`} />
            <AddressAutocomplete variant="grid" />
            <Currency
              name="baseCurrencyCode"
              label={t`Base Currency`}
              disabled={true}
            />
            <PhoneInput name="phone" label={t`Phone Number`} />
            <PhoneInput name="fax" label={t`Fax Number`} />
            <Input name="email" label={t`Email`} />
            <Input name="website" label={t`Website`} />
          </div>
          <Submit>
            <Trans>Save</Trans>
          </Submit>
        </VStack>
      </ValidatedForm>
    </>
  );
};

export default CompanyForm;
