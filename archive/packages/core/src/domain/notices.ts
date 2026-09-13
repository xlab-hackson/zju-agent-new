/**
 * 学校通知公告领域类型（素质拓展平台 + 教务系统·通知公告）。
 *
 * 数据由本地后端从两个免登录的公开 JSON 接口抓取（与浙大账号无关），
 * 协议实测记录参照「浙大网页抓包」项目（shared/sources.py）。
 */

export type NoticeSource = "sztz" | "zdbk";

export const NOTICE_SOURCE_NAMES: Record<NoticeSource, string> = {
  sztz: "素质拓展平台",
  zdbk: "教务系统",
};

export type Notice = {
  /** 由详情 URL 派生的稳定 id（noticeId()），用作 React key */
  id: string;
  source: NoticeSource;
  sourceName: string;
  title: string;
  /** 详情页绝对 URL（去重键）；点击后交由系统浏览器打开 */
  url: string;
  /** 发布日期 "YYYY-MM-DD"；解析失败为 "" */
  date: string;
  /** 发布人（素拓 fbr / 教务 xwfbr） */
  publisher?: string;
  /** 是否置顶（教务 sfzd==="1"） */
  important?: boolean;
  /** 正文纯文本摘要（仅素拓源正文 HTML 可提取；教务列表接口无正文） */
  summary?: string;
};

export type NoticeFetchResult = {
  items: Notice[];
  /** 抓取失败的源描述（单源失败不整体报错） */
  failures: string[];
};

/**
 * FNV-1a 32 位哈希 → 8 位 hex。纯 JS 实现，core 内零依赖（不用 node:crypto）。
 * 通知量级（几十条）下碰撞概率可忽略。
 */
export function noticeId(url: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < url.length; i++) {
    hash ^= url.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}
