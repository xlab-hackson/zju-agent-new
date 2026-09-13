/**
 * 生成占位图标（无第三方依赖，纯 zlib + 手写 PNG/ICO 编码）。
 *
 * 产物：
 *   build/icon.png        256x256  — electron-builder 的 buildResources 图标（打包用）
 *   build/tray.ico        16/32    — 备用文件形式的托盘图标
 *   src/tray-icon.ts      base64   — **托盘实际使用**（内联，避免运行时依赖被 gitignore 的 build/ 目录）
 *
 * 设计：浙大蓝圆角方块 + 白色日历。后续可用真实设计稿直接覆盖这些文件。
 */
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(__dirname, "../build");

const BLUE = [0x00, 0x3f, 0x88];
const WHITE = [0xff, 0xff, 0xff];

// ---------------- PNG 编码 ----------------

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ -1) >>> 0;
}

function pngChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const typeBuf = Buffer.from(type, "ascii");
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])));
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

/** RGBA 像素数组 → PNG Buffer */
function encodePng(width, height, rgba) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0; // filter: none
    Buffer.from(rgba.buffer, y * stride, stride).copy(raw, y * (stride + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type: RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

// ---------------- 绘制（4 倍超采样抗锯齿） ----------------

const SS = 4;
const DESIGN = 32; // 设计坐标系边长

function renderIcon(size) {
  const W = size * SS;
  const k = W / DESIGN;
  const px = new Uint8ClampedArray(W * W * 4);

  const put = (x, y, color) => {
    if (x < 0 || y < 0 || x >= W || y >= W) return;
    const i = (y * W + x) * 4;
    px[i] = color[0];
    px[i + 1] = color[1];
    px[i + 2] = color[2];
    px[i + 3] = 255;
  };

  /** 圆角矩形（设计坐标） */
  const roundedRect = (x0, y0, x1, y1, radius, color) => {
    const X0 = x0 * k;
    const Y0 = y0 * k;
    const X1 = x1 * k;
    const Y1 = y1 * k;
    const r = radius * k;
    for (let y = Math.floor(Y0); y < Math.ceil(Y1); y++) {
      for (let x = Math.floor(X0); x < Math.ceil(X1); x++) {
        const cx = Math.min(Math.max(x + 0.5, X0 + r), X1 - r);
        const cy = Math.min(Math.max(y + 0.5, Y0 + r), Y1 - r);
        const dx = x + 0.5 - cx;
        const dy = y + 0.5 - cy;
        if (dx * dx + dy * dy <= r * r) put(x, y, color);
      }
    }
  };

  // 蓝色圆角底
  roundedRect(1, 1, 31, 31, 7, BLUE);
  // 日历纸
  roundedRect(6, 9, 26, 27, 2.5, WHITE);
  // 挂环
  roundedRect(9.5, 5, 11.5, 10.5, 1, WHITE);
  roundedRect(20.5, 5, 22.5, 10.5, 1, WHITE);
  // 日期格 3 列 x 2 行
  for (const x of [9.5, 14.5, 19.5]) {
    for (const y of [14, 20]) {
      roundedRect(x, y, x + 3, y + 3, 0.6, BLUE);
    }
  }

  // 盒式降采样
  const out = new Uint8ClampedArray(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const i = ((y * SS + sy) * W + (x * SS + sx)) * 4;
          r += px[i];
          g += px[i + 1];
          b += px[i + 2];
          a += px[i + 3];
        }
      }
      const n = SS * SS;
      const o = (y * size + x) * 4;
      out[o] = r / n;
      out[o + 1] = g / n;
      out[o + 2] = b / n;
      out[o + 3] = a / n;
    }
  }
  return out;
}

// ---------------- ICO 编码（PNG 内嵌） ----------------

function encodeIco(pngs) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(pngs.length, 4);

  const entries = [];
  let offset = 6 + 16 * pngs.length;
  for (const { size, data } of pngs) {
    const e = Buffer.alloc(16);
    e[0] = size >= 256 ? 0 : size;
    e[1] = size >= 256 ? 0 : size;
    e[2] = 0; // palette
    e[3] = 0; // reserved
    e.writeUInt16LE(1, 4); // color planes
    e.writeUInt16LE(32, 6); // bits per pixel
    e.writeUInt32LE(data.length, 8);
    e.writeUInt32LE(offset, 12);
    offset += data.length;
    entries.push(e);
  }
  return Buffer.concat([header, ...entries, ...pngs.map((p) => p.data)]);
}

// ---------------- 输出 ----------------

fs.mkdirSync(outDir, { recursive: true });

const icon256 = encodePng(256, 256, renderIcon(256));
fs.writeFileSync(path.join(outDir, "icon.png"), icon256);

const trayIco = encodeIco([
  { size: 16, data: encodePng(16, 16, renderIcon(16)) },
  { size: 32, data: encodePng(32, 32, renderIcon(32)) },
]);
fs.writeFileSync(path.join(outDir, "tray.ico"), trayIco);

// 托盘图标内联进源码：build/ 被根 .gitignore 忽略，内联可保证新克隆也能显示托盘。
// 注意用 PNG 而非 ICO —— nativeImage.createFromDataURL 不支持 ICO。
const trayPng = encodePng(32, 32, renderIcon(32));
const dataUrl = `data:image/png;base64,${trayPng.toString("base64")}`;
const tsPath = path.resolve(__dirname, "../src/tray-icon.ts");
const tsSource = `/**
 * 自动生成，请勿手改 —— 由 scripts/make-icon.mjs 产出。
 * 托盘图标以 32x32 PNG data URL 内联，避免运行时依赖 apps/desktop/build/（该目录被 .gitignore 忽略）。
 */
export const TRAY_ICON_DATA_URL =
  "${dataUrl}";
`;
fs.writeFileSync(tsPath, tsSource);

console.log(`Icons written to ${outDir}`);
console.log(`  icon.png      ${icon256.length} bytes`);
console.log(`  tray.ico      ${trayIco.length} bytes`);
console.log(`  src/tray-icon.ts  ${dataUrl.length} chars`);
