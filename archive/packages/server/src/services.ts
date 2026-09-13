/**
 * 服务容器：集中持有各仓储、凭据存储、校园服务适配器。
 * 路由通过 deps 访问，避免全局单例。
 */

import type { Storage } from "./storage/db.js";
import { SettingsRepo } from "./storage/settings-repo.js";
import { CampusCache } from "./storage/cache.js";
import { AuditRepo } from "./storage/audit.js";
import { DownloadsRepo } from "./storage/downloads.js";
import { ConversationRepo } from "./storage/conversations.js";
import { ConfirmationRepo } from "./storage/confirmations.js";
import type { CredentialStore } from "./auth/credentials.js";
import type { ServerConfig } from "./config/env.js";
import { AuthSessionManager } from "./auth/auth-session.js";
import { CalendarService, NoticeService } from "@zju-agent/zju-services";
import type { ZjuServices } from "@zju-agent/zju-services";

export type ServicesContainer = {
  config: ServerConfig;
  storage: Storage;
  settings: SettingsRepo;
  cache: CampusCache;
  audit: AuditRepo;
  downloads: DownloadsRepo;
  conversations: ConversationRepo;
  confirmations: ConfirmationRepo;
  credentials: CredentialStore;
  auth: AuthSessionManager;
  zju: ZjuServices;
  /** 校历服务，与 ZJU 账号无关，独立持有 */
  calendar: CalendarService;
  /** 学校通知公告抓取（素质拓展 + 教务公开源），与 ZJU 账号无关，独立持有 */
  notices: NoticeService;
};

export function createServicesContainer(input: {
  config: ServerConfig;
  storage: Storage;
  credentials: CredentialStore;
  zju: ZjuServices;
}): ServicesContainer {
  const { config, storage, credentials, zju } = input;
  return {
    config,
    storage,
    settings: new SettingsRepo(storage.db),
    cache: new CampusCache(storage.db),
    audit: new AuditRepo(storage.db),
    downloads: new DownloadsRepo(storage.db),
    conversations: new ConversationRepo(storage.db),
    confirmations: new ConfirmationRepo(storage.db),
    credentials,
    auth: new AuthSessionManager(credentials, zju),
    zju,
    calendar: new CalendarService(),
    notices: new NoticeService(),
  };
}
