import { useRoutes } from "react-router-dom";
import { routes } from "./routes/index.js";
import { useBootstrap } from "./api/useBootstrap.js";
import { ServerStatusBanner } from "./components/ServerStatusBanner.js";

export default function App() {
  const element = useRoutes(routes);
  const { isReady, isConnected, error } = useBootstrap();

  return (
    <div className="min-h-screen">
      <ServerStatusBanner
        isReady={isReady}
        isConnected={isConnected}
        error={error}
      />
      {element}
    </div>
  );
}
