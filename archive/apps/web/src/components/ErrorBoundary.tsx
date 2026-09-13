import { Component, type ErrorInfo, type ReactNode } from "react";

type Props = { children: ReactNode };
type State = { hasError: boolean; error: Error | null; info: ErrorInfo | null };

/**
 * 全局错误边界。
 * 任何子组件渲染期抛错都会被捕获，避免整树卸载导致白屏，
 * 并把错误信息显示出来便于诊断。
 */
export class ErrorBoundary extends Component<Props, State> {
  override state: State = { hasError: false, error: null, info: null };

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true, error };
  }

  override componentDidCatch(error: Error, info: ErrorInfo) {
    this.setState({ info });
    // 控制台留痕，便于在 DevTools 查看
    console.error("[ErrorBoundary] 渲染异常:", error, info);
  }

  override render() {
    if (this.state.hasError) {
      const err = this.state.error;
      return (
        <div className="m-4 rounded-paper border border-[#b03a2e]/40 bg-[#b03a2e]/10 p-4 text-sm">
          <div className="mb-2 flex items-center gap-1.5 font-serif font-black tracking-[2px] text-[#b03a2e]">
            页面渲染出错
          </div>
          <div className="mb-2 text-[#22304e]">{err?.message ?? String(err)}</div>
          {err?.stack && (
            <pre className="max-h-60 overflow-auto rounded-paper bg-[#fdfaf2]/80 p-2 font-mono text-[11px] text-[#5b6884]">
              {err.stack}
            </pre>
          )}
          {this.state.info?.componentStack && (
            <pre className="mt-2 max-h-40 overflow-auto rounded-paper bg-[#fdfaf2]/80 p-2 font-mono text-[11px] text-[#8b93a7]">
              {this.state.info.componentStack}
            </pre>
          )}
          <button
            onClick={() => this.setState({ hasError: false, error: null, info: null })}
            className="mt-3 rounded-paper bg-[#003f88] px-3 py-1.5 text-xs font-bold tracking-wider text-[#fdfaf2] transition hover:bg-[#12233f]"
          >
            重试
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
