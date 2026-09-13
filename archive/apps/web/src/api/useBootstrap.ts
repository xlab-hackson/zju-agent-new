import { useEffect } from "react";
import { useBootstrapStore } from "../api/bootstrap.js";

export function useBootstrap() {
  const bootstrap = useBootstrapStore((s) => s.bootstrap);
  const isReady = useBootstrapStore((s) => s.isReady);
  const isConnected = useBootstrapStore((s) => s.isConnected);
  const error = useBootstrapStore((s) => s.error);

  useEffect(() => {
    void bootstrap();
  }, [bootstrap]);

  return { isReady, isConnected, error };
}
