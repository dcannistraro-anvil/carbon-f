import type { InputProps } from "@carbon/react";
import {
  FormControl,
  FormErrorMessage,
  FormHelperText,
  FormLabel,
  Input as InputBase,
  InputGroup,
  InputLeftAddon,
  InputRightAddon
} from "@carbon/react";
import type { ReactNode } from "react";
import { forwardRef } from "react";
import { useField } from "../hooks";
import { useFormStateContext } from "../internal/formStateContext";
import type { ValidationBehaviorOptions } from "../internal/getInputProps";

type FormInputProps = InputProps & {
  name: string;
  label?: ReactNode;
  isConfigured?: boolean;
  isOptional?: boolean;
  isRequired?: boolean;
  helperText?: string;
  prefix?: string;
  suffix?: string;
  validationBehavior?: ValidationBehaviorOptions;
  onConfigure?: () => void;
};

const Input = forwardRef<HTMLInputElement, FormInputProps>(
  (
    {
      name,
      label,
      isConfigured,
      isOptional,
      isRequired,
      helperText,
      prefix,
      suffix,
      onConfigure,
      isDisabled: isDisabledProp,
      isReadOnly: isReadOnlyProp,
      ...rest
    },
    ref
  ) => {
    const {
      getInputProps,
      error,
      isOptional: fieldIsOptional
    } = useField(name);
    const formState = useFormStateContext();
    const isDisabled = formState.isDisabled || isDisabledProp;
    const isReadOnly = formState.isReadOnly || isReadOnlyProp;
    const resolvedIsOptional =
      isOptional ?? (isRequired ? false : (fieldIsOptional ?? false));

    return (
      <FormControl
        isInvalid={!!error}
        isRequired={isRequired}
        isDisabled={isDisabled}
        isReadOnly={isReadOnly}
      >
        {label ? (
          <FormLabel
            htmlFor={name}
            isOptional={resolvedIsOptional}
            isConfigured={isConfigured}
            onConfigure={onConfigure}
          >
            {label}
          </FormLabel>
        ) : (
          <label htmlFor={name} className="sr-only">
            {rest.placeholder ?? name}
          </label>
        )}
        {prefix || suffix ? (
          <InputGroup>
            {prefix && <InputLeftAddon children={prefix} />}
            <InputBase
              ref={ref}
              {...getInputProps({
                id: name,
                ...rest
              })}
              isDisabled={isDisabled}
              isReadOnly={isReadOnly}
            />
            {suffix && <InputRightAddon children={suffix} />}
          </InputGroup>
        ) : (
          <InputBase
            ref={ref}
            {...getInputProps({
              id: name,
              ...rest
            })}
            isDisabled={isDisabled}
            isReadOnly={isReadOnly}
          />
        )}

        {helperText && <FormHelperText>{helperText}</FormHelperText>}
        {error && <FormErrorMessage>{error}</FormErrorMessage>}
      </FormControl>
    );
  }
);

Input.displayName = "Input";

export default Input;
