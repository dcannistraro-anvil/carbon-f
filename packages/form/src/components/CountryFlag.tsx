import type { Country } from "react-phone-number-input";
import flags from "react-phone-number-input/flags";

type CountryFlagProps = {
  countryCode: Country;
  className?: string;
};

export function CountryFlag({ countryCode, className }: CountryFlagProps) {
  const Flag = flags[countryCode];
  return (
    <span
      className={
        className ?? "flex h-4 w-6 overflow-hidden rounded-sm bg-foreground/20"
      }
    >
      {Flag && <Flag title={countryCode} />}
    </span>
  );
}
