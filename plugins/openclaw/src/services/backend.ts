import { logger } from "../utils/logger.js";
import type { ServiceBuilder } from "./index.js";

export const createBackendService: ServiceBuilder = () => {
  return {
    id: "miloco-backend",
    start: async () => {
      logger.info(
        "miloco-backend service start skipped; desktop launcher owns backend lifecycle",
      );
    },
    stop: async () => {
      logger.info(
        "miloco-backend service stop skipped; desktop launcher owns backend lifecycle",
      );
    },
  };
};
