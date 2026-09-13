import type { CSSProperties } from "react";
import notebookDesk from "../../assets/icons/notebook-desk.svg?raw";
import calendarDays from "../../assets/icons/calendar-days.svg?raw";
import calendarGrid from "../../assets/icons/calendar-grid.svg?raw";
import checklistPaper from "../../assets/icons/checklist-paper.svg?raw";
import examPaper from "../../assets/icons/exam-paper.svg?raw";
import announcementHorn from "../../assets/icons/announcement-horn.svg?raw";
import folder from "../../assets/icons/folder.svg?raw";
import folders from "../../assets/icons/folders.svg?raw";
import cartoonSettings from "../../assets/icons/cartoon-settings.svg?raw";
import videoLessonPlay from "../../assets/icons/video-lesson-play.svg?raw";
import graduationCap from "../../assets/icons/graduation-cap.svg?raw";
import university from "../../assets/icons/university.svg?raw";
import commentThread from "../../assets/icons/comment-thread.svg?raw";
import paymentCard from "../../assets/icons/payment-card.svg?raw";
import libraryPublic from "../../assets/icons/library-public.svg?raw";
import schoolBuilding from "../../assets/icons/school-building.svg?raw";
import areaChart from "../../assets/icons/area-chart.svg?raw";
import mapLocationPin from "../../assets/icons/map-location-pin.svg?raw";
import scroll from "../../assets/icons/scroll.svg?raw";
import inkbrushCalligraphyPen from "../../assets/icons/inkbrush-calligraphy-pen.svg?raw";
import stamp from "../../assets/icons/stamp.svg?raw";
import cartoonHourglass from "../../assets/icons/cartoon-hourglass.svg?raw";
import searchMagnifier from "../../assets/icons/search-magnifier.svg?raw";
import bellNotification from "../../assets/icons/bell-notification.svg?raw";
import users from "../../assets/icons/users.svg?raw";
import keyIcon from "../../assets/icons/key.svg?raw";
import downloadArrow from "../../assets/icons/download-arrow.svg?raw";
import bookOpen from "../../assets/icons/book-open.svg?raw";
import screen from "../../assets/icons/screen.svg?raw";
import homeworkDiary from "../../assets/icons/homework-diary.svg?raw";
import cartoonTest from "../../assets/icons/cartoon-test.svg?raw";

/**
 * Koboyo 手绘 SVG 图标（https://koboyo.com/icons，许可：免费商用、可修改、无需署名）。
 * 源文件已下载到 src/assets/icons/ 随仓库提交；均为 fill="currentColor" 单色图标，
 * 颜色跟随 CSS color。注意：手绘图标非正方形 viewBox，只设高度、宽度 auto。
 */
const SOURCES = {
  "notebook-desk": notebookDesk,
  "calendar-days": calendarDays,
  "calendar-grid": calendarGrid,
  "checklist-paper": checklistPaper,
  "exam-paper": examPaper,
  "announcement-horn": announcementHorn,
  folder,
  folders,
  "cartoon-settings": cartoonSettings,
  "video-lesson-play": videoLessonPlay,
  "graduation-cap": graduationCap,
  university,
  "comment-thread": commentThread,
  "payment-card": paymentCard,
  "library-public": libraryPublic,
  "school-building": schoolBuilding,
  "area-chart": areaChart,
  "map-location-pin": mapLocationPin,
  scroll,
  "inkbrush-calligraphy-pen": inkbrushCalligraphyPen,
  stamp,
  "cartoon-hourglass": cartoonHourglass,
  "search-magnifier": searchMagnifier,
  "bell-notification": bellNotification,
  users,
  key: keyIcon,
  "download-arrow": downloadArrow,
  "book-open": bookOpen,
  screen,
  "homework-diary": homeworkDiary,
  "cartoon-test": cartoonTest,
} as const;

export type IconName = keyof typeof SOURCES;

type ParsedIcon = { viewBox: string; inner: string };

const parsedCache = new Map<IconName, ParsedIcon>();

function parseIcon(name: IconName): ParsedIcon {
  const cached = parsedCache.get(name);
  if (cached) return cached;
  const raw = SOURCES[name];
  const viewBox = /viewBox="([^"]+)"/.exec(raw)?.[1] ?? "0 0 24 24";
  const inner = raw.replace(/<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "");
  const parsed = { viewBox, inner };
  parsedCache.set(name, parsed);
  return parsed;
}

export function KoboyoIcon({
  name,
  className,
  style,
}: {
  name: IconName;
  className?: string;
  style?: CSSProperties;
}) {
  const { viewBox, inner } = parseIcon(name);
  return (
    <svg
      viewBox={viewBox}
      fill="currentColor"
      aria-hidden="true"
      className={className}
      style={style}
      dangerouslySetInnerHTML={{ __html: inner }}
    />
  );
}
