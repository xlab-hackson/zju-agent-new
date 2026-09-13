import type { FastifyPluginAsync } from "fastify";
import { ok } from "@zju-agent/core";

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get("/health", async () => ok({ status: "ok", time: new Date().toISOString() }));
};
