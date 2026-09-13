import { KoboyoIcon } from "./ui/KoboyoIcon.js";

export function Loading({ message }: { message?: string }) {
  return (
    <div className="flex items-center justify-center gap-2.5 p-8 text-sm tracking-widest text-ink-faint">
      <KoboyoIcon name="cartoon-hourglass" className="h-5 w-auto animate-pulse text-gold" />
      <span>{message ?? "加载中…"}</span>
    </div>
  );
}
