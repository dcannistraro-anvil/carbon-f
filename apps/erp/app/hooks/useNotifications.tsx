import { NOVU_API_URL, NOVU_APPLICATION_ID } from "@carbon/auth";
import { useMount } from "@carbon/react";
import type { IMessage } from "@novu/headless";
import { HeadlessService } from "@novu/headless";
import { useCallback, useEffect, useRef, useState } from "react";

export function getSubscriberId({
  companyId,
  userId
}: {
  companyId: string;
  userId: string;
}) {
  return `${companyId}:${userId}`;
}

export function useNotifications({
  userId,
  companyId
}: {
  userId: string;
  companyId: string;
}) {
  const [isLoading, setLoading] = useState(true);
  const [notifications, setNotifications] = useState<IMessage[]>([]);
  const [subscriberId, setSubscriberId] = useState<string>();
  const headlessServiceRef = useRef<HeadlessService>();

  const markAllMessagesAsRead = () => {
    const headlessService = headlessServiceRef.current;

    if (headlessService) {
      setNotifications((prevNotifications) =>
        prevNotifications.map((notification) => {
          return {
            ...notification,
            read: true
          };
        })
      );

      headlessService.markAllMessagesAsRead({
        // biome-ignore lint/suspicious/noEmptyBlockStatements: suppressed due to migration
        listener: () => {},
        // biome-ignore lint/suspicious/noEmptyBlockStatements: suppressed due to migration
        onError: () => {}
      });
    }
  };

  const markMessageAsRead = (messageId: string) => {
    const headlessService = headlessServiceRef.current;

    if (headlessService) {
      setNotifications((prevNotifications) =>
        prevNotifications.map((notification) => {
          if (notification._id === messageId) {
            return {
              ...notification,
              read: true
            };
          }

          return notification;
        })
      );

      headlessService.markNotificationsAsRead({
        messageId: [messageId],
        // biome-ignore lint/suspicious/noEmptyBlockStatements: suppressed due to migration
        listener: (result) => {},
        // biome-ignore lint/suspicious/noEmptyBlockStatements: suppressed due to migration
        onError: (error) => {}
      });
    }
  };

  const fetchNotifications = useCallback(() => {
    const headlessService = headlessServiceRef.current;

    if (headlessService) {
      headlessService.fetchNotifications({
        // biome-ignore lint/correctness/noEmptyPattern: suppressed due to migration
        // biome-ignore lint/suspicious/noEmptyBlockStatements: suppressed due to migration
        listener: ({}) => {},
        onSuccess: (response) => {
          setLoading(false);
          setNotifications(response.data);
        }
      });
    }
  }, []);

  const markAllMessagesAsSeen = () => {
    const headlessService = headlessServiceRef.current;

    if (headlessService) {
      setNotifications((prevNotifications) =>
        prevNotifications.map((notification) => ({
          ...notification,
          seen: true
        }))
      );
      headlessService.markAllMessagesAsSeen({
        // biome-ignore lint/suspicious/noEmptyBlockStatements: suppressed due to migration
        listener: () => {},
        // biome-ignore lint/suspicious/noEmptyBlockStatements: suppressed due to migration
        onError: () => {}
      });
    }
  };

  useMount(() => {
    setSubscriberId(getSubscriberId({ companyId, userId }));
  });

  // biome-ignore lint/correctness/useExhaustiveDependencies: suppressed due to migration
  useEffect(() => {
    const headlessService = headlessServiceRef.current;

    if (headlessService) {
      headlessService.listenNotificationReceive({
        listener: () => {
          fetchNotifications();
        }
      });
    }
  }, [headlessServiceRef.current]);

  useEffect(() => {
    if (subscriberId && !headlessServiceRef.current) {
      const isEu = NOVU_API_URL.includes("eu.");
      const headlessService = new HeadlessService({
        applicationIdentifier: NOVU_APPLICATION_ID!,
        backendUrl: isEu ? "https://eu.api.novu.co" : "https://api.novu.co",
        socketUrl: isEu ? "wss://eu.socket.novu.co" : undefined, // ← base only, no /socket.io
        subscriberId
      });

      headlessService.initializeSession({
        // biome-ignore lint/suspicious/noEmptyBlockStatements: suppressed due to migration
        listener: () => {},
        onSuccess: () => {
          headlessServiceRef.current = headlessService;
          fetchNotifications();
        },
        // biome-ignore lint/suspicious/noEmptyBlockStatements: suppressed due to migration
        onError: () => {}
      });
    }
  }, [fetchNotifications, subscriberId]);

  return {
    isLoading,
    markAllMessagesAsRead,
    markMessageAsRead,
    markAllMessagesAsSeen,
    hasUnseenNotifications: notifications.some(
      (notification) => !notification.seen
    ),
    notifications
  };
}
