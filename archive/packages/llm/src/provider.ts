/**
 * Provider 工厂。
 */

import type { LlmProvider, LlmRequest } from "./types.js";
import { OpenAIProvider } from "./adapters/openai.js";
import { AnthropicProvider } from "./adapters/anthropic.js";

export function createProvider(req: { protocol: "openai" | "anthropic" }): LlmProvider {
  switch (req.protocol) {
    case "openai":
      return new OpenAIProvider();
    case "anthropic":
      return new AnthropicProvider();
  }
}

export type { LlmProvider, LlmRequest };
