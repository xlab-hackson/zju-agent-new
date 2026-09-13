import { lazy, Suspense, useEffect } from "react";
import { Navigate, type RouteObject } from "react-router-dom";
import { useFloatingChatStore } from "../stores/useFloatingChat.js";

const DashboardPage = lazy(() => import("../pages/Dashboard.js").then((m) => ({ default: m.DashboardPage })));
const SetupPage = lazy(() => import("../pages/Setup.js").then((m) => ({ default: m.SetupPage })));
const CoursesPage = lazy(() => import("../pages/Courses.js").then((m) => ({ default: m.CoursesPage })));
const AssignmentsPage = lazy(() => import("../pages/Assignments.js").then((m) => ({ default: m.AssignmentsPage })));
const ExamsPage = lazy(() => import("../pages/Exams.js").then((m) => ({ default: m.ExamsPage })));
const SchoolInfoPage = lazy(() => import("../pages/SchoolInfo.js").then((m) => ({ default: m.SchoolInfoPage })));
const DownloadsPage = lazy(() => import("../pages/Downloads.js").then((m) => ({ default: m.DownloadsPage })));
const ClassroomPage = lazy(() => import("../pages/Classroom.js").then((m) => ({ default: m.ClassroomPage })));
const SettingsPage = lazy(() => import("../pages/Settings.js").then((m) => ({ default: m.SettingsPage })));

function withSuspense(element: React.ReactNode) {
  return (
    <Suspense
      fallback={
        <div className="p-6 text-sm tracking-[3px] text-ink-faint">加载中…</div>
      }
    >
      {element}
    </Suspense>
  );
}

function ChatRedirect() {
  const openChat = useFloatingChatStore((s) => s.openChat);
  useEffect(() => {
    openChat();
  }, [openChat]);
  return <Navigate to="/" replace />;
}

export const routes: RouteObject[] = [
  { path: "/", element: withSuspense(<DashboardPage />) },
  { path: "/chat", element: <ChatRedirect /> },
  { path: "/dashboard", element: <Navigate to="/" replace /> },
  { path: "/toolbox", element: <Navigate to="/" replace /> },
  { path: "/setup", element: withSuspense(<SetupPage />) },
  { path: "/courses", element: withSuspense(<CoursesPage />) },
  { path: "/assignments", element: withSuspense(<AssignmentsPage />) },
  { path: "/exams", element: withSuspense(<ExamsPage />) },
  { path: "/school-info", element: withSuspense(<SchoolInfoPage />) },
  { path: "/downloads", element: withSuspense(<DownloadsPage />) },
  { path: "/classroom", element: withSuspense(<ClassroomPage />) },
  { path: "/settings", element: withSuspense(<SettingsPage />) },
];
