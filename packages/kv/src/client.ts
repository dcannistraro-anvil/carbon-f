import { REDIS_URL } from "@carbon/env";
import Redis from "ioredis";

declare global {
  var __redis: Redis | undefined;
}

if (!REDIS_URL) {
  throw new Error("REDIS_URL is not defined");
}

if (!global.__redis) {
  global.__redis = new Redis(REDIS_URL, {
    maxRetriesPerRequest: 3,
    lazyConnect: true, // don't connect until first command
    enableOfflineQueue: true, // buffer commands while connecting
    retryStrategy(times) {
      if (times > 3) return null; // stop retrying, don't hang the lambda
      return Math.min(times * 50, 2000);
    }
  });
}

const redis = global.__redis;

export default redis;
