export function ErrorState({
  message,
  hint,
}: {
  message: string;
  hint?: string;
}) {
  return (
    <div className="rounded-paper border border-seal/40 bg-seal/10 p-4 shadow-seal">
      <div className="font-serif text-sm font-black tracking-[2px] text-seal">加载失败</div>
      <div className="mt-1 text-xs leading-relaxed text-ink-soft">{message}</div>
      {hint && <div className="mt-2 text-xs tracking-wide text-ink-faint">{hint}</div>}
    </div>
  );
}
