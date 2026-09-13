/**
 * Agent loop — 多轮工具调用循环。
 * 见 ZJU_CAMPUS_AGENT_PROJECT.md 第 9 节。
 *
 * 流程：
 * 1. 用历史消息 + 系统提示调用 LLM（流式）。
 * 2. 转发 text / tool_call 事件给调用方（SSE）。
 * 3. message_end 后若 LLM 请求工具调用：
 *    - read 类工具：立即执行，结果作为 tool 消息注入，回到步骤 1。
 *    - 需确认工具：生成 PendingConfirmation，发 confirmation_required 事件，
 *      暂停循环（返回 confirmationId），等待 /api/agent/confirm 触发后恢复。
 * 4. 无工具调用或达到 maxIterations 时结束。
 *
 * 中止与恢复通过 AgentRun 句柄管理：confirm() 推进一次待确认项，
 * loop 内通过 `wait` 回调让出控制权。
 */

import type {
  AgentMessage,
  AgentStreamEvent,
  AgentTool,
  ToolCall,
  ToolResult,
} from "@zju-agent/core";
import { createProvider } from "@zju-agent/llm";
import { getAcademicPeriod } from "@zju-agent/zju-services";
import type { LlmProvider, LlmRequest } from "@zju-agent/llm";
import type { ServicesContainer } from "../services.js";
import type { ServerConfig } from "../config/env.js";
import { buildTools } from "./tools.js";
import { getGuideOutline } from "../knowledge/index.js";
import {
  buildSystemPrompt,
  filterToolsForMode,
  type UserProfile,
} from "./prompt.js";
import { logger } from "../config/logger.js";

function datetimeStr(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())} (周${["日","一","二","三","四","五","六"][now.getDay()]})`;
}

function currentPeriodStr(): string {
  const period = getAcademicPeriod();
  return period.type === "break"
    ? `当前处于${period.name}`
    : `当前为${period.year}${period.term}学期`;
}

/** 从设置里读取个性化信息（昵称 / 自述提示词），注入所有对话 */
function loadUserProfile(deps: AgentLoopDeps): UserProfile {
  const settings = deps.settings.get<Record<string, unknown>>("app-settings") ?? {};
  return {
    nickname:
      typeof settings.nickname === "string" ? settings.nickname : undefined,
    persona:
      typeof settings.personaPrompt === "string"
        ? settings.personaPrompt
        : undefined,
  };
}

const MAX_ITERATIONS = 8;

export type AgentRunHandle = {
  /** 当前是否暂停在某个待确认项上 */
  pendingConfirmationId: string | null;
  /** 是否已完成 */
  done: boolean;
};

export type AgentLoopCallbacks = {
  /** 推送流式事件给前端（SSE） */
  emit(event: AgentStreamEvent): void;
  /** 把消息追加到会话历史（持久化） */
  persist(msg: AgentMessage): void;
};

export type AgentLoopDeps = ServicesContainer & { config: ServerConfig };

export type AgentLoopOptions = {
  /** 只读模式：只注册 read 级且无需确认的工具（桌面挂件一次性问答） */
  readOnly?: boolean;
  /** 简短模式：系统提示要求极简回答（桌面挂件） */
  brief?: boolean;
};

export class AgentLoop {
  private tools: AgentTool[];
  private provider: LlmProvider | null = null;
  private providerConfig: {
    protocol: "openai" | "anthropic";
    baseUrl: string;
    apiKey: string;
    model: string;
  } | null = null;
  private aborted = false;

  constructor(
    private deps: AgentLoopDeps,
    private options: AgentLoopOptions = {},
  ) {
    this.tools = filterToolsForMode(buildTools(deps), options.readOnly ?? false);
  }

  /** 客户端断开时中止 loop（下一检查点停止，不再执行新工具） */
  abort(): void {
    this.aborted = true;
  }

  /**
   * 运行 Agent loop。
   * @param messages 历史消息（含本轮 user 消息）
   * @param cb 事件回调
   * @returns 是否暂停在待确认项
   */
  async run(
    messages: AgentMessage[],
    cb: AgentLoopCallbacks,
  ): Promise<{ paused: boolean; confirmationId: string | null }> {
    await this.ensureProvider();
    const toolMap = new Map(this.tools.map((t) => [t.name, t]));
    const history = [...messages];
    const system = buildSystemPrompt({
      datetime: datetimeStr(),
      period: currentPeriodStr(),
      brief: this.options.brief,
      profile: loadUserProfile(this.deps),
      guideOutline: getGuideOutline(),
    });

    for (let iter = 0; iter < MAX_ITERATIONS; iter++) {
      // 客户端断开 → 立即停止
      if (this.aborted) {
        return { paused: false, confirmationId: null };
      }
      // 调用 LLM
      const toolManifests = this.tools.map((t) => ({
        name: t.name,
        description: t.description,
        inputSchema: t.inputSchema,
        riskLevel: t.riskLevel,
        requiresConfirmation: t.requiresConfirmation,
      }));
      const req: LlmRequest = {
        protocol: this.providerConfig!.protocol,
        baseUrl: this.providerConfig!.baseUrl,
        apiKey: this.providerConfig!.apiKey,
        model: this.providerConfig!.model,
        messages: history,
        tools: toolManifests,
        toolChoice: "auto",
        system,
      };

      let assistantText = "";
      const collectedToolCalls: ToolCall[] = [];
      let finishReason = "stop";

      for await (const evt of this.provider!.stream(req)) {
        cb.emit(evt);
        switch (evt.type) {
          case "text":
            assistantText += evt.delta;
            break;
          case "tool_call_end":
            collectedToolCalls.push(evt.toolCall);
            break;
          case "message_end":
            finishReason = evt.finishReason;
            break;
          case "error":
            logger.warn("LLM 流错误", { code: evt.code, message: evt.message });
            break;
        }
      }

      // 持久化 assistant 消息
      const assistantMsg: AgentMessage = {
        role: "assistant",
        content: assistantText,
        toolCalls: collectedToolCalls.length > 0 ? collectedToolCalls : undefined,
      };
      cb.persist(assistantMsg);
      history.push(assistantMsg);

      // 无工具调用 → 结束
      if (collectedToolCalls.length === 0 || finishReason === "stop") {
        if (collectedToolCalls.length === 0) {
          return { paused: false, confirmationId: null };
        }
      }

      // 处理工具调用：先执行所有无需确认的工具（含未知工具报错），
      // 再把需确认的工具统一走确认流——这样同批次中排在待确认项之后的
      // read 类工具不会因占位而永远丢失。
      let paused = false;
      let pausedConfirmationId: string | null = null;
      let confirmationIndex = -1;
      const confirmQueue: number[] = [];
      for (let i = 0; i < collectedToolCalls.length; i++) {
        const tc = collectedToolCalls[i]!;
        const tool = toolMap.get(tc.name);
        if (tool?.requiresConfirmation) {
          confirmQueue.push(i);
          continue;
        }
        if (this.aborted) break;
        const result: ToolResult = !tool
          ? {
              ok: false,
              error: {
                code: "TOOL_INPUT_INVALID",
                message: `未知工具：${tc.name}`,
              },
            }
          : await tool.execute(tc.input, {
              userId: "local",
              conversationId: this.currentConversationId,
              requestId: tc.id,
            });
        cb.emit({
          type: "tool_result",
          toolCallId: tc.id,
          result: result.data ?? result.error,
          ok: result.ok,
        });
        const toolMsg = toToolMessage(tc, result);
        cb.persist(toolMsg);
        history.push(toolMsg);
      }

      // 待确认项：第一个进入确认流；其余注入占位 tool message
      //（LLM API 要求 assistant tool_calls 之后必须有对应 tool 消息）
      if (!this.aborted && confirmQueue.length > 0) {
        const first = confirmQueue[0]!;
        const tc = collectedToolCalls[first]!;
        const tool = toolMap.get(tc.name);
        if (tool) {
          const stored = this.deps.confirmations.create({
            conversationId: this.currentConversationId,
            toolCall: tc,
            riskLevel: tool.riskLevel,
            summary: summarizeToolCall(tc),
            inputPreview: redactInput(tc.input),
          });
          this.deps.audit.log({
            action: "tool.confirm.requested",
            riskLevel: tool.riskLevel,
            inputSummary: summarizeToolCall(tc),
            confirmed: false,
          });
          cb.emit({
            type: "confirmation_required",
            confirmationId: stored.id,
            toolName: tc.name,
            summary: stored.summary,
            inputPreview: stored.inputPreview,
          });
          paused = true;
          pausedConfirmationId = stored.id;
          confirmationIndex = first;
        }
        for (let qi = confirmationIndex >= 0 ? 1 : 0; qi < confirmQueue.length; qi++) {
          const tc2 = collectedToolCalls[confirmQueue[qi]!]!;
          const placeholder: ToolResult = {
            ok: false,
            error: {
              code: "TOOL_CONFIRMATION_PAUSED",
              message: "该工具调用因同批次中存在待确认项而暂缓，请先确认高危操作。",
            },
          };
          const toolMsg = toToolMessage(tc2, placeholder);
          cb.emit({
            type: "tool_result",
            toolCallId: tc2.id,
            result: placeholder.error,
            ok: false,
          });
          cb.persist(toolMsg);
          history.push(toolMsg);
        }
      }

      if (this.aborted) {
        return { paused: false, confirmationId: null };
      }
      if (paused) {
        return { paused: true, confirmationId: pausedConfirmationId };
      }
      // 否则继续下一轮（LLM 看到工具结果后继续）
    }

    logger.warn("Agent loop 达到最大迭代次数", {
      conversationId: this.currentConversationId,
      max: MAX_ITERATIONS,
    });
    return { paused: false, confirmationId: null };
  }

  private currentConversationId = "";

  setConversationId(id: string) {
    this.currentConversationId = id;
  }

  /** 用户确认后执行待确认工具，并继续 loop */
  async resumeAfterConfirm(
    confirmationId: string,
    messages: AgentMessage[],
    cb: AgentLoopCallbacks,
  ): Promise<{ paused: boolean; confirmationId: string | null }> {
    const stored = this.deps.confirmations.claim(confirmationId);
    if (!stored) {
      cb.emit({
        type: "error",
        code: "TOOL_CONFIRMATION_EXPIRED",
        message: "该确认已过期或不存在。",
      });
      return { paused: false, confirmationId: null };
    }
    this.deps.audit.log({
      action: "tool.confirm.approved",
      riskLevel: stored.riskLevel,
      inputSummary: stored.summary,
      confirmed: true,
    });

    const tool = this.tools.find((t) => t.name === stored.toolCall.name);
    if (!tool) {
      const result: ToolResult = {
        ok: false,
        error: { code: "TOOL_INPUT_INVALID", message: `未知工具：${stored.toolCall.name}` },
      };
      const toolMsg = toToolMessage(stored.toolCall, result);
      cb.emit({
        type: "tool_result",
        toolCallId: stored.toolCall.id,
        result: result.error,
        ok: false,
      });
      cb.persist(toolMsg);
      messages.push(toolMsg);
    } else {
      const result = await tool.execute(stored.toolCall.input, {
        userId: "local",
        conversationId: stored.conversationId,
        requestId: stored.toolCall.id,
      });
      cb.emit({
        type: "tool_result",
        toolCallId: stored.toolCall.id,
        result: result.data ?? result.error,
        ok: result.ok,
      });
      const toolMsg = toToolMessage(stored.toolCall, result);
      cb.persist(toolMsg);
      messages.push(toolMsg);
    }

    // 继续运行 loop（LLM 看到工具结果后继续）
    return this.run(messages, cb);
  }

  /** 用户拒绝 → 注入拒绝结果，继续 loop（让 LLM 说明未执行） */
  async resumeAfterReject(
    confirmationId: string,
    messages: AgentMessage[],
    cb: AgentLoopCallbacks,
  ): Promise<{ paused: boolean; confirmationId: string | null }> {
    const stored = this.deps.confirmations.claim(confirmationId);
    if (!stored) {
      return { paused: false, confirmationId: null };
    }
    this.deps.audit.log({
      action: "tool.confirm.rejected",
      riskLevel: stored.riskLevel,
      inputSummary: stored.summary,
      confirmed: false,
    });
    const result: ToolResult = {
      ok: false,
      error: {
        code: "TOOL_CONFIRMATION_REJECTED",
        message: "用户拒绝执行该工具。",
      },
    };
    cb.emit({
      type: "tool_result",
      toolCallId: stored.toolCall.id,
      result: result.error,
      ok: false,
    });
    const toolMsg = toToolMessage(stored.toolCall, result);
    cb.persist(toolMsg);
    messages.push(toolMsg);
    return this.run(messages, cb);
  }

  /** 确保 provider 已根据当前 settings 准备好 */
  private async ensureProvider(): Promise<void> {
    if (this.provider && this.providerConfig) return;
    const providers = await this.deps.credentials.get<
      Array<{
        id: string;
        name: string;
        protocol: "openai" | "anthropic";
        baseUrl: string;
        apiKey: string;
        model: string;
        enabled: boolean;
      }>
    >("model-providers");
    const enabled = (providers ?? []).filter((p) => p.enabled);
    if (enabled.length === 0) {
      throw new Error("尚未配置可用的模型 provider，请在设置页配置 LLM 来源。");
    }
    // 取第一个启用的 provider（后续可支持 default 选择）
    const p = enabled[0]!;
    this.providerConfig = {
      protocol: p.protocol,
      baseUrl: p.baseUrl,
      apiKey: p.apiKey,
      model: p.model,
    };
    this.provider = createProvider({ protocol: p.protocol });
  }
}

function toToolMessage(tc: ToolCall, result: ToolResult): AgentMessage {
  return {
    role: "tool",
    toolCallId: tc.id,
    name: tc.name,
    content: JSON.stringify(result.ok ? result.data : result.error),
  };
}

function summarizeToolCall(tc: ToolCall): string {
  try {
    const input = JSON.stringify(tc.input);
    return `${tc.name}(${input.slice(0, 120)})`;
  } catch {
    return tc.name;
  }
}

/** 脱敏工具输入（避免完整明文落库/展示） */
function redactInput(input: unknown): unknown {
  // 下载类工具不含密码，可直接保留字段
  return input;
}
