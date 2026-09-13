/**
 * 会话持久化仓储。
 * conversations / messages 两张表，见 db.ts schema。
 */

import type { Database } from "better-sqlite3";
import { nanoid } from "nanoid";
import type { AgentMessage, ToolCall } from "@zju-agent/core";

export type ConversationRecord = {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
};

export type MessageMetadata =
  | { toolCalls: ToolCall[] } // assistant 携带工具调用
  | { toolCallId: string; name: string } // tool 结果消息
  | { error?: string; finishReason?: string };

export type MessageRecord = {
  id: string;
  conversationId: string;
  role: AgentMessage["role"];
  content: string;
  metadata?: MessageMetadata;
  createdAt: string;
};

export class ConversationRepo {
  constructor(private db: Database) {}

  create(title?: string): ConversationRecord {
    const id = nanoid();
    const now = new Date().toISOString();
    const title2 =
      title && title.trim() ? title.trim().slice(0, 60) : "新对话";
    this.db
      .prepare(
        `INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`,
      )
      .run(id, title2, now, now);
    return { id, title: title2, createdAt: now, updatedAt: now };
  }

  list(): ConversationRecord[] {
    const rows = this.db
      .prepare(
        `SELECT id, title, created_at AS createdAt, updated_at AS updatedAt
         FROM conversations ORDER BY updated_at DESC`,
      )
      .all() as ConversationRecord[];
    return rows;
  }

  get(id: string): ConversationRecord | null {
    const row = this.db
      .prepare(
        `SELECT id, title, created_at AS createdAt, updated_at AS updatedAt
         FROM conversations WHERE id = ?`,
      )
      .get(id) as ConversationRecord | undefined;
    return row ?? null;
  }

  touch(id: string): void {
    this.db
      .prepare("UPDATE conversations SET updated_at = ? WHERE id = ?")
      .run(new Date().toISOString(), id);
  }

  rename(id: string, title: string): void {
    this.db
      .prepare("UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?")
      .run(title.slice(0, 60), new Date().toISOString(), id);
  }

  delete(id: string): void {
    this.db.prepare("DELETE FROM messages WHERE conversation_id = ?").run(id);
    this.db.prepare("DELETE FROM conversations WHERE id = ?").run(id);
  }

  appendMessage(conversationId: string, msg: AgentMessage): MessageRecord {
    const id = nanoid();
    const now = new Date().toISOString();
    let content = "";
    let metadata: MessageMetadata | undefined;
    switch (msg.role) {
      case "system":
      case "user":
        content = msg.content;
        break;
      case "assistant":
        content = msg.content;
        if (msg.toolCalls && msg.toolCalls.length > 0) {
          metadata = { toolCalls: msg.toolCalls };
        }
        break;
      case "tool":
        content = msg.content;
        metadata = { toolCallId: msg.toolCallId, name: msg.name };
        break;
    }
    this.db
      .prepare(
        `INSERT INTO messages (id, conversation_id, role, content, metadata, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .run(
        id,
        conversationId,
        msg.role,
        content,
        metadata === undefined ? null : JSON.stringify(metadata),
        now,
      );
    this.touch(conversationId);
    return {
      id,
      conversationId,
      role: msg.role,
      content,
      metadata,
      createdAt: now,
    };
  }

  listMessages(conversationId: string): MessageRecord[] {
    const rows = this.db
      .prepare(
        "SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at ASC",
      )
      .all(conversationId) as Array<
      Omit<MessageRecord, "metadata"> & { metadata: string | null }
    >;
    return rows.map((r) => ({
      ...r,
      metadata: r.metadata ? safeParse(r.metadata) : undefined,
    }));
  }
}

function safeParse(s: string): MessageMetadata {
  try {
    return JSON.parse(s) as MessageMetadata;
  } catch {
    return { error: "metadata 解析失败" };
  }
}

/** 把持久化记录还原成 AgentMessage */
export function recordToMessage(r: MessageRecord): AgentMessage {
  switch (r.role) {
    case "system":
      return { role: "system", content: r.content };
    case "user":
      return { role: "user", content: r.content };
    case "assistant": {
      const meta =
        r.metadata && "toolCalls" in r.metadata ? r.metadata.toolCalls : undefined;
      return {
        role: "assistant",
        content: r.content,
        toolCalls: meta,
      };
    }
    case "tool": {
      const meta =
        r.metadata && "toolCallId" in r.metadata
          ? r.metadata
          : { toolCallId: "", name: "" };
      return {
        role: "tool",
        toolCallId: meta.toolCallId,
        name: meta.name,
        content: r.content,
      };
    }
  }
}
