import { Layout } from "../components/Layout.js";
import { PaperCard, PaperEmpty } from "../components/ui/Paper.js";

export function ClassroomPage() {
  return (
    <Layout>
      <PaperCard className="mx-auto mt-10 max-w-xl border-dashed">
        <PaperEmpty
          icon="video-lesson-play"
          title="智云课堂"
          description="课堂回放、课件与语音转文字检索将在阶段 7 接入后展示。"
        />
      </PaperCard>
    </Layout>
  );
}
