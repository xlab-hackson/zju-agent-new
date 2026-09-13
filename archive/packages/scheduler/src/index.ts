/**
 * @zju-agent/scheduler — 提醒与定时任务（占位）。
 *
 * 第二阶段实现：
 * - 课程开始前 15 分钟提醒（可配置）
 * - 考试前 1 天 / 2 小时 / 30 分钟提醒
 *
 * 桌面端用 node-cron 或 setTimeout；
 * 移动端用 Capacitor Background Task 插件。
 */

export type ReminderInput = {
  title: string;
  remindAt: string;
  source?: string;
  metadata?: Record<string, unknown>;
};

export interface Scheduler {
  createReminder(input: ReminderInput): Promise<string>;
  listReminders(): Promise<ReminderInput[]>;
  cancelReminder(id: string): Promise<void>;
}
