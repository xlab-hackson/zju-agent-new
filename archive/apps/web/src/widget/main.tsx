/**
 * 桌面挂件入口：独立于主应用外壳（不挂 Router / Layout / ServerStatusBanner）。
 */
import React from "react";
import ReactDOM from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ErrorBoundary } from "../components/ErrorBoundary.js";
import { WidgetApp } from "./WidgetApp.js";
import "@crisp-ui-kit/crisp/styles.css";
import "../styles/global.css";
import "./widget.css";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <WidgetApp />
      </QueryClientProvider>
    </ErrorBoundary>
  </React.StrictMode>,
);
