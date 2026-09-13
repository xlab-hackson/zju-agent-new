# 知识库来源与使用说明

本目录内容摘自 **CC98 论坛《浙江大学本科新生指引》（2026 版）**：

- 网页版：https://zjuers.com/welcome/
- 源码仓库：https://github.com/kaixuanwang2003/zju-welcome/

指引由指引编委会编撰、修订并享有著作权。**内容非浙江大学官方发布，仅供参考**；如与学校
官方信息不一致，请以官方最新通知为准。本目录仅作为本地 AI 问答的检索语料使用，不作任何
商业用途；对外使用与传播请遵守指引的版权声明与授权声明（见原站点首页）。

## 更新方式

用上游新版 markdown 覆盖本目录同名文件即可，服务启动后按需重建检索索引，无需改代码。

未收录的站点元信息：`index.md`、`preface.md`、`postscript.md`、`stylesheets/`；
本说明文件（`ATTRIBUTION.md`）同样不会进入检索索引（见 `../src/knowledge/index.ts` 的 `SKIP_DOCS`）。

## 关于附件（图片 / PDF）

指引原文的地图、截图、照片与 PDF 附件**有意未收录**：

- 知识库检索工具是纯文本的，AI 读不了图片，收录图片不提升回答质量，却会让仓库和桌面安装包各多出约 27 MB；
- 引用图片的约 60 处段落，正文本身自洽（图片只是截图/示意图/照片），缺图不影响问答；
- `basics/school_calendar.md`、`basics/school_map.md`、`haining/basics/campus_map.md`、`haining/basics/school_calendar.md` 是纯图片文件，没有文字，会被索引自动跳过；
- 校历日期由后端校历服务（`packages/core/src/domain/schedule.ts`）提供，不依赖附件。

如需补充海宁（ZJUI）奖助细则、双学位课程清单等 PDF 正文，先用 `pdftotext -enc UTF-8` 抽成
markdown 再放进本目录（注意 `2026-2027.pdf` 和 `ZJE本科生奖学金.pdf` 是扫描件，抽不出文字；
`评奖评优细则（2023年修订版）.pdf` 是 2023 年版本，收录时需在标题里标明年份）。

## 目录结构

```
knowledge/
├── ATTRIBUTION.md          本文件（不参与检索）
├── callout.md              重要提示（防骗 / 资助 / 新生选拔）
├── network_detailed.md     校园网激活详解
├── basics/                 常用信息（校区、校史、校歌、网站、软件、校历、黑话）
├── registration/           报到（流程、物品、交通、缴费、始业教育、防骗）
├── military_training/      军训
├── learning/               学习（培养方案、课程考核、专业确认、转专业、辅修、竺院、竞赛）
├── course_sys/             选课（规则、操作、技巧、通知）
├── awards&grants/          奖助（评价、奖学金、荣誉称号、资助）
├── life/                   生活（饮食、宿舍、图书馆、就医、网络、交通、快递、社团）
├── dorms/                  园区（各学园介绍）
├── cc98/                   CC98 论坛攻略与精华帖
├── haining/                海宁国际校区专题
└── HK_Macao_Taiwan/        港澳台生专题
```
