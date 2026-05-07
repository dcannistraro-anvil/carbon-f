import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { REALTIME_SUBSCRIBE_STATES } from "@supabase/supabase-js";
import { useCallback, useEffect, useRef } from "react";
import { useCarbon } from "../CarbonContext";

interface UseRealtimeChannelOptions<TDeps extends any[]> {
  topic: string;
  setup: (
    channel: RealtimeChannel,
    carbon: SupabaseClient,
    deps: TDeps
  ) => RealtimeChannel;
  enabled?: boolean;
  dependencies?: TDeps;
}

export const useRealtimeChannel = <TDeps extends any[]>(
  options: UseRealtimeChannelOptions<TDeps>
) => {
  const { topic, setup, enabled = true, dependencies = [] } = options;
  const channelRef = useRef<RealtimeChannel | null>(null);
  const isTearingDownRef = useRef(false);
  const { carbon, isRealtimeAuthSet } = useCarbon();

  // biome-ignore lint/correctness/useExhaustiveDependencies: suppressed due to migration
  const memoSetup = useCallback(setup, [topic, ...dependencies]);

  // biome-ignore lint/correctness/useExhaustiveDependencies: suppressed due to migration
  useEffect(() => {
    if (!carbon) return;

    // Define teardown inline - NOT in dependency array
    const teardown = async () => {
      // Re-entrancy guard
      if (isTearingDownRef.current) {
        console.log(
          `🌀 Teardown already in progress for ${topic}, skipping...`
        );
        return;
      }

      console.log(`🌀 Tearing down realtime channel ${topic}...`);
      const channel = channelRef.current;

      if (!channel) return;

      isTearingDownRef.current = true;

      try {
        // Add timeout to prevent hanging indefinitely
        await Promise.race([
          carbon.removeChannel(channel),
          new Promise((_, reject) =>
            setTimeout(() => reject(new Error("Channel removal timeout")), 5000)
          )
        ]);
      } catch (error) {
        console.error(`❌ Error removing channel ${topic}:`, error);
      } finally {
        console.log(`🌀 Realtime channel ${topic} torn down.`);
        channelRef.current = null;
        isTearingDownRef.current = false;
      }
    };

    if (!isRealtimeAuthSet || !enabled) {
      // If disabled/auth lost, tear down any existing channel
      void teardown();
      return;
    }

    // Always create a fresh channel instance when deps change
    (async () => {
      // Ensure previous instance is gone before creating a new one
      if (channelRef.current) {
        await teardown();
      }

      try {
        const channel = carbon.channel(topic);

        const configuredChannel = memoSetup(
          channel,
          carbon,
          dependencies as TDeps
        );

        channelRef.current = configuredChannel;

        configuredChannel.subscribe(async (status, err) => {
          console.log(`🌀 Realtime channel ${topic} status:`, status);
          if (status === REALTIME_SUBSCRIBE_STATES.SUBSCRIBED) {
            return;
          }

          // Treat error/timeout/closed as dead; tear down so effect can recreate
          if (
            status === REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR ||
            status === REALTIME_SUBSCRIBE_STATES.TIMED_OUT ||
            status === REALTIME_SUBSCRIBE_STATES.CLOSED
          ) {
            await teardown();
          }
        });
      } catch (error) {
        console.error(
          `Failed to subscribe to realtime channel ${topic}:`,
          error
        );
      }
    })();

    // Cleanup on unmount or dependency change
    return () => {
      void teardown();
    };
  }, [
    carbon,
    isRealtimeAuthSet,
    enabled,
    topic,
    memoSetup
    // teardown is NOT in dependencies - it's defined inline
  ]);

  return channelRef;
};
