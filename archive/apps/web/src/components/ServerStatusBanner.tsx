import { useEffect } from "react";
import { useBootstrapStore } from "../api/bootstrap.js";
import { KoboyoIcon } from "./ui/KoboyoIcon.js";

export function ServerStatusBanner({
  isReady,
  isConnected,
  error,
}: {
  isReady: boolean;
  isConnected: boolean;
  error: string | null;
}) {
  // 后端连接成功后，每隔 15s 探活一次
  const token = useBootstrapStore((s) => s.token);
  const setIsConnected = (v: boolean) => useBootstrapStore.setState({ isConnected: v });

  useEffect(() => {
    if (!isConnected || !token) return;
    const id = setInterval(async () => {
      try {
        const res = await fetch("/api/health", {
          headers: { Authorization: `Bearer ${token}` },
        });
        setIsConnected(res.ok);
      } catch {
        setIsConnected(false);
      }
    }, 15_000);
    return () => clearInterval(id);
  }, [isConnected, token]);

  if (!isReady) {
    return (
      <div className="flex items-center justify-center gap-2 bg-paper-deep px-4 py-2 text-sm tracking-widest text-ink-soft">
        <KoboyoIcon name="cartoon-hourglass" className="h-4 w-auto animate-pulse text-gold" />
        正在连接本地后端服务…
      </div>
    );
  }
  if (!isConnected) {
    return (
      <div className="flex items-center justify-center gap-2 border-b border-seal/40 bg-seal/15 px-4 py-2 text-sm text-seal">
        <KoboyoIcon name="bell-notification" className="h-4 w-auto shrink-0" />
        无法连接本地后端服务。{error ? `（${error}）` : "请确认后端已启动（默认 127.0.0.1:7788）。"}
      </div>
    );
  }
  return null;
}
