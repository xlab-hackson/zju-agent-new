import { useState } from "react";
import { Layout } from "../components/Layout.js";
import { ErrorState } from "../components/ErrorState.js";
import { Loading } from "../components/Loading.js";
import { useDownloads, useDeleteDownload, downloadPreviewUrl } from "../api/zju.js";
import { useToken } from "../api/bootstrap.js";
import { formatBytes, formatDateTime } from "../utils/format.js";
import type { DownloadRecord } from "../api/zju.js";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import {
  faXmark,
  faFilePdf,
  faFileWord,
  faFilePowerpoint,
  faFileExcel,
  faFileImage,
  faFileVideo,
  faFileAudio,
  faFileZipper,
  faFileLines,
  faFile,
} from "@fortawesome/free-solid-svg-icons";
import type { IconDefinition } from "@fortawesome/fontawesome-svg-core";
import { KoboyoIcon } from "../components/ui/KoboyoIcon.js";
import { InkTag, PageHead, PaperCard, PaperEmpty } from "../components/ui/Paper.js";

type PreviewState =
  | { type: "none" }
  | { type: "loading"; id: string }
  | { type: "error"; message: string }
  | { type: "image"; url: string }
  | { type: "pdf"; url: string }
  | { type: "text"; url: string }
  | { type: "unsupported"; fileName: string; mime?: string };

/** 哪些文件可在浏览器内联预览 */
function previewKind(record: DownloadRecord): "image" | "pdf" | "text" | "unsupported" {
  const mime = record.mimeType?.toLowerCase() ?? "";
  const ext = record.fileName.toLowerCase().split(".").pop() ?? "";
  if (mime.startsWith("image/") || ["png", "jpg", "jpeg", "gif", "webp", "svg"].includes(ext)) {
    return "image";
  }
  if (mime === "application/pdf" || ext === "pdf") return "pdf";
  if (["text/plain", "text/markdown", "application/json"].includes(mime) || ["txt", "md", "json"].includes(ext)) {
    return "text";
  }
  return "unsupported";
}

export function DownloadsPage() {
  const { data, isLoading, error, refetch, isFetching } = useDownloads();
  const del = useDeleteDownload();
  const token = useToken();
  const [preview, setPreview] = useState<PreviewState>({ type: "none" });
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const records = data?.records ?? [];

  async function openPreview(record: DownloadRecord) {
    setSelectedId(record.id);
    setPreview({ type: "loading", id: record.id });
    try {
      const kind = previewKind(record);
      const url = downloadPreviewUrl(record.id, token, true);
      if (kind === "unsupported") {
        setPreview({ type: "unsupported", fileName: record.fileName, mime: record.mimeType });
        return;
      }
      // 文本类需 fetch 内容；图片/PDF 直接用 URL（带 token query）
      if (kind === "text") {
        const res = await fetch(url, {
          headers: { Authorization: `Bearer ${token ?? ""}` },
        });
        if (!res.ok) throw new Error(`读取失败 HTTP ${res.status}`);
        const text = await res.text();
        // 用 blob URL 渲染文本，避免直接塞大字符串进 state
        const blobUrl = URL.createObjectURL(new Blob([text], { type: "text/plain" }));
        setPreview({ type: "text", url: blobUrl });
      } else {
        setPreview({ type: kind, url });
      }
    } catch (err) {
      setPreview({
        type: "error",
        message: err instanceof Error ? err.message : "预览失败",
      });
    }
  }

  function closePreview() {
    if (preview.type === "text" && preview.url.startsWith("blob:")) {
      URL.revokeObjectURL(preview.url);
    }
    setPreview({ type: "none" });
    setSelectedId(null);
  }

  return (
    <Layout>
      <PageHead
        title="下载中心"
        sub={data?.downloadDir ? `存储目录：${data.downloadDir}` : "课件与资料的本地文库"}
        right={
          <button
            onClick={() => refetch()}
            disabled={isFetching}
            className="btn-ink-outline !px-3.5 !py-1.5 text-xs"
          >
            {isFetching ? "刷新中…" : "刷新"}
          </button>
        }
      />

      {error ? (
        <ErrorState message={error.message} />
      ) : isLoading ? (
        <Loading />
      ) : records.length === 0 ? (
        <PaperCard className="border-dashed">
          <PaperEmpty
            icon="folder"
            title="还没有下载过文件"
            description="前往「课程」页下载课件后会出现在这里。"
          />
        </PaperCard>
      ) : (
        <div className="space-y-3">
          {records.map((r) => (
            <DownloadRow
              key={r.id}
              record={r}
              selected={selectedId === r.id}
              onPreview={() => openPreview(r)}
              onDelete={(purge) => del.mutate({ id: r.id, purge })}
              deleting={del.isPending}
            />
          ))}
        </div>
      )}

      {preview.type !== "none" && (
        <PreviewDrawer state={preview} onClose={closePreview} />
      )}
    </Layout>
  );
}

function DownloadRow({
  record,
  selected,
  onPreview,
  onDelete,
  deleting,
}: {
  record: DownloadRecord;
  selected: boolean;
  onPreview: () => void;
  onDelete: (purge: boolean) => void;
  deleting: boolean;
}) {
  const [downloading, setDownloading] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const token = useToken();
  const canPreview = previewKind(record) !== "unsupported";
  const iconInfo = fileIconInfo(record.fileName);

  async function downloadFile() {
    try {
      setDownloading(true);
      const url = downloadPreviewUrl(record.id, token, false);
      const a = document.createElement("a");
      a.href = url;
      a.download = record.fileName;
      document.body.appendChild(a);
      a.click();
      a.remove();
    } finally {
      setDownloading(false);
    }
  }

  return (
    <PaperCard
      interactive
      className={`p-4 ${selected ? "border-qiushi ring-1 ring-qiushi/40" : ""}`}
    >
      <div className="flex items-center gap-3.5">
        <div className={`shrink-0 text-xl ${iconInfo.color}`}>
          <FontAwesomeIcon icon={iconInfo.icon} />
        </div>
        <div className="min-w-0 flex-1">
          <button
            onClick={onPreview}
            className="block w-full truncate text-left font-serif text-sm font-bold tracking-wide text-ink-deep transition hover:text-qiushi"
            title={record.fileName}
          >
            {record.fileName}
          </button>
          <div className="mt-1 flex flex-wrap items-center gap-2 font-mono text-[11px] text-ink-faint">
            <span>{formatBytes(record.size)}</span>
            <span>·</span>
            <span>{formatDateTime(record.createdAt)}</span>
            {record.source === "classroom" && (
              <InkTag tone="plain" className="!font-sans">智云</InkTag>
            )}
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          {canPreview && (
            <button
              onClick={onPreview}
              className="rounded-paper px-2.5 py-1.5 text-xs font-bold tracking-wide text-qiushi transition hover:bg-qiushi/10"
            >
              预览
            </button>
          )}
          <button
            onClick={() => void downloadFile()}
            disabled={downloading}
            className="inline-flex items-center gap-1.5 rounded-paper border border-ink/20 bg-paper-deep/60 px-2.5 py-1.5 text-xs font-bold tracking-wide text-ink transition hover:border-qiushi hover:text-qiushi disabled:opacity-50"
          >
            <KoboyoIcon name="download-arrow" className="h-3 w-auto" />
            {downloading ? "…" : "下载"}
          </button>
          {confirming ? (
            <span className="flex items-center gap-1">
              <button
                onClick={() => { onDelete(true); setConfirming(false); }}
                disabled={deleting}
                className="rounded-paper bg-seal px-2 py-1.5 text-xs font-bold text-paper-card transition hover:bg-seal-light disabled:opacity-50"
              >
                删文件
              </button>
              <button
                onClick={() => { onDelete(false); setConfirming(false); }}
                disabled={deleting}
                className="rounded-paper border border-ink/20 px-2 py-1.5 text-xs font-bold text-ink transition hover:border-seal hover:text-seal disabled:opacity-50"
              >
                仅删记录
              </button>
              <button
                onClick={() => setConfirming(false)}
                className="rounded-paper px-1.5 py-1.5 text-xs text-ink-faint transition hover:text-ink"
              >
                <FontAwesomeIcon icon={faXmark} />
              </button>
            </span>
          ) : (
            <button
              onClick={() => setConfirming(true)}
              disabled={deleting}
              className="rounded-paper px-2 py-1.5 text-xs tracking-wide text-ink-faint transition hover:text-seal disabled:opacity-50"
            >
              删除
            </button>
          )}
        </div>
      </div>
    </PaperCard>
  );
}

function PreviewDrawer({
  state,
  onClose,
}: {
  state: PreviewState;
  onClose: () => void;
}) {
  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-ink-deep/40" onClick={onClose} />
      <div className="relative flex h-full w-full max-w-3xl flex-col border-l-2 border-double border-gold/40 bg-paper-card shadow-2xl">
        <div className="flex items-center justify-between border-b border-ink/15 bg-paper-deep px-5 py-3.5">
          <h3 className="flex items-center gap-2 font-serif text-base font-black tracking-[2px] text-ink-deep">
            <KoboyoIcon name="scroll" className="h-4 w-auto text-gold" />
            预览
          </h3>
          <button onClick={onClose} className="text-ink-faint transition hover:text-seal">
            <FontAwesomeIcon icon={faXmark} />
          </button>
        </div>
        <div className="flex-1 overflow-auto bg-paper p-4">
          {state.type === "loading" && (
            <div className="flex h-full items-center justify-center text-sm tracking-widest text-ink-faint">
              加载中…
            </div>
          )}
          {state.type === "error" && (
            <div className="rounded-paper border border-seal/40 bg-seal/10 p-4 text-sm text-seal">
              {state.message}
            </div>
          )}
          {state.type === "unsupported" && (
            <div className="flex h-full flex-col items-center justify-center gap-3 text-center">
              <KoboyoIcon name="scroll" className="h-12 w-auto text-ink/25" />
              <div className="font-serif text-sm font-bold text-ink">{state.fileName}</div>
              <div className="max-w-sm text-xs leading-relaxed text-ink-faint">
                此类型文件无法在浏览器内预览{state.mime ? `（${state.mime}）` : ""}，请点击「下载」用本地软件打开。
              </div>
            </div>
          )}
          {state.type === "image" && (
            <img src={state.url} alt="预览" className="mx-auto max-h-full max-w-full object-contain shadow-paper" />
          )}
          {state.type === "pdf" && (
            <iframe src={state.url} title="PDF 预览" className="h-full w-full border-0 bg-white shadow-paper" />
          )}
          {state.type === "text" && (
            <iframe src={state.url} title="文本预览" className="h-full w-full border-0 bg-white p-4 font-mono text-sm shadow-paper" />
          )}
        </div>
      </div>
    </div>
  );
}

function fileIconInfo(name: string): { icon: IconDefinition; color: string } {
  const ext = name.toLowerCase().split(".").pop() ?? "";
  if (["pdf"].includes(ext)) return { icon: faFilePdf, color: "text-seal" };
  if (["doc", "docx"].includes(ext)) return { icon: faFileWord, color: "text-qiushi" };
  if (["ppt", "pptx"].includes(ext)) return { icon: faFilePowerpoint, color: "text-gold" };
  if (["xls", "xlsx"].includes(ext)) return { icon: faFileExcel, color: "text-bamboo" };
  if (["png", "jpg", "jpeg", "gif", "webp", "svg"].includes(ext)) return { icon: faFileImage, color: "text-[#55447a]" };
  if (["mp4", "mov", "avi"].includes(ext)) return { icon: faFileVideo, color: "text-[#2a5a5e]" };
  if (["mp3", "wav"].includes(ext)) return { icon: faFileAudio, color: "text-[#8c3a2e]" };
  if (["zip", "rar", "7z"].includes(ext)) return { icon: faFileZipper, color: "text-[#8a5222]" };
  if (["txt", "md", "json"].includes(ext)) return { icon: faFileLines, color: "text-ink-soft" };
  return { icon: faFile, color: "text-ink-faint" };
}
