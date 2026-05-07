import { useEffect } from "react";
import { Form, useFetcher } from "react-router";
import { Button } from "./Button";
import type useDisclosure from "./hooks/useDisclosure";
import {
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
  ModalTitle
} from "./Modal";
import { toast } from "./Toast";
/** 
 * 
export function AcademyBanner({
  acknowledgeAction
}: {
  acknowledgeAction: string;
}) {
  const fetcher = useFetcher<{}>();
  
  return (
    <div className="fixed bottom-3 left-1/2 -translate-x-1/2 flex items-center justify-between gap-10  bg-[#212278] dark:bg-[#2f31ae] text-white py-1 px-2 rounded-lg z-50 shadow-md">
    <div />
    <fetcher.Form method="post" action={acknowledgeAction}>
    <input type="hidden" name="intent" value="academy" />
    <input
    type="hidden"
    name="redirectTo"
    value="https://learn.carbon.ms"
    />
    <Button
    type="submit"
    variant="ghost"
    size="lg"
    className="hover:bg-transparent text-white hover:text-white"
    rightIcon={<LuArrowUpRight />}
    >
    <span>Introducing Carbon Academy</span>
    </Button>
    </fetcher.Form>
    <fetcher.Form method="post" action={acknowledgeAction}>
    <input type="hidden" name="intent" value="academy" />
    <IconButton
    type="submit"
    aria-label="Close"
    variant="ghost"
    className="text-white dark:text-white hover:text-white"
    icon={<LuX />}
    />
    </fetcher.Form>
    </div>
  );
}
*/

export function ItarLoginDisclaimer() {
  return (
    <p>
      <p>
        This is an ITAR-controlled solution. Access and use are restricted to
        U.S. Persons only
      </p>
    </p>
  );
}

export function ItarDisclosure({
  disclosure
}: {
  disclosure: ReturnType<typeof useDisclosure>;
}) {
  return (
    <Modal
      open={disclosure.isOpen}
      onOpenChange={(open) => {
        if (!open) disclosure.onClose();
      }}
    >
      <ModalContent size="medium">
        <ModalHeader>
          <ModalTitle>ITAR-controlled solution</ModalTitle>
        </ModalHeader>
        <ModalBody>
          <p className="text-sm text-muted-foreground">
            This is an ITAR-controlled solution. Access and use are restricted
            to U.S. Persons only
          </p>
        </ModalBody>
        <ModalFooter>
          <Button variant="secondary" onClick={disclosure.onClose}>
            Close
          </Button>
        </ModalFooter>
      </ModalContent>
    </Modal>
  );
}

export function ItarPopup({
  acknowledgeAction,
  logoutAction
}: {
  acknowledgeAction: string;
  logoutAction: string;
}) {
  const acknowledgeFetcher = useFetcher<{
    success: boolean;
    message: string;
  }>();
  const isLoading = acknowledgeFetcher.state !== "idle";
  useEffect(() => {
    if (acknowledgeFetcher.data?.success === true) {
      toast.success(acknowledgeFetcher.data?.message);
    } else if (acknowledgeFetcher.data?.success === false) {
      toast.error(acknowledgeFetcher.data?.message);
    }
  }, [acknowledgeFetcher.data]);

  return (
    <Modal open>
      <ModalContent size="medium">
        <ModalHeader>
          <ModalTitle>ITAR-controlled solution</ModalTitle>
        </ModalHeader>
        <ModalBody>
          <p className="text-sm text-muted-foreground">
            This is an ITAR-controlled solution. Access and use are restricted
            to U.S. Persons only
          </p>
        </ModalBody>
        <ModalFooter>
          <acknowledgeFetcher.Form method="post" action={acknowledgeAction}>
            <input type="hidden" name="intent" value="itar" />
            <Button type="submit" isLoading={isLoading} isDisabled={isLoading}>
              I am a U.S. Person
            </Button>
          </acknowledgeFetcher.Form>

          <Form method="post" action={logoutAction}>
            <Button type="submit" variant="secondary" isDisabled={isLoading}>
              I am not a U.S. Person
            </Button>
          </Form>
        </ModalFooter>
      </ModalContent>
    </Modal>
  );
}
