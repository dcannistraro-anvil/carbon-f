import { createContext, useContext } from "react";

export type FormStateContextValue = {
  isDisabled: boolean;
  isReadOnly: boolean;
};

export const FormStateContext = createContext<FormStateContextValue>({
  isDisabled: false,
  isReadOnly: false
});

export function useFormStateContext() {
  return useContext(FormStateContext);
}
