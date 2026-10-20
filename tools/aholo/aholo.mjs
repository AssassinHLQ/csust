#!/usr/bin/env node
/**
 * Aholo 3DGS 命令行 —— 《长沙理工：2067》专用的小封装。
 *
 * 官方接口（2026-10 核对过 SDK 源码）：
 *   基址  CN: https://api.aholo3d.cn     路径前缀 /world/v1
 *         COM: https://api.aholo.ai       路径前缀 /global/world/v1
 *   鉴权  HTTP 头 `Authorization: <API Key>`（不是 Bearer）
 *   上传  GET /asset/v1/token → OUS 单块/分块上传 → 轮询 /ous/api/v2/upload/status
 *   重建  POST /world/v1/reconstructions   {name, resources:[{url,type}], taskQuality, scene}
 *   生成  POST /world/v1/generations       {prompt?, resources?[≤1 image]}
 *   查询  GET  /world/v1/{worldId}         → status / assets.splats.urls.{plyPath,spzPath}
 *   列表  POST /world/v1/list
 *
 * 用法（密钥只走环境变量，绝不写进仓库）：
 *   PowerShell:  $env:AHOLO_API_KEY="..." ; $env:AHOLO_REGION="cn"
 *   bash:        export AHOLO_API_KEY=...   AHOLO_REGION=cn
 *
 *   node tools/aholo/aholo.mjs whoami
 *   node tools/aholo/aholo.mjs list
 *   node tools/aholo/aholo.mjs space  D:\photos\room609 --name 画室609 --quality high --wait
 *   node tools/aholo/aholo.mjs object D:\photos\handicraft --name 手办 --wait
 *   node tools/aholo/aholo.mjs generate --prompt "夜晚的赛博朋克教室" --wait
 *   node tools/aholo/aholo.mjs get    <worldId>
 *   node tools/aholo/aholo.mjs wait   <worldId>
 *   node tools/aholo/aholo.mjs download <worldId> --out out/room609 --convert
 *
 * `--convert` 会用 `npx @playcanvas/splat-transform` 把 PLY 转成 `.sog`，
 * 再改名成 `.sogdata` —— 本工程的 `SogRuntime` 只认这个后缀。
 */
import { createAssetClient } from '@manycore/aholo-sdk-asset';
import { createWorldClient } from '@manycore/aholo-sdk-world';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const REGION = String(process.env.AHOLO_REGION || 'cn').toLowerCase();
const API_KEY = process.env.AHOLO_API_KEY || '';
const IMAGE_EXT = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const VIDEO_EXT = new Set(['.mp4', '.mov']);
const FAIL_STATUS = new Set(['FAILED', 'CANCELED', 'TIMEOUT', 'REJECTED']);

function die(msg) {
  console.error(`\n✗ ${msg}\n`);
  process.exit(1);
}

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith('--')) {
        out[key] = next;
        i++;
      } else {
        out[key] = true;
      }
    } else {
      out._.push(a);
    }
  }
  return out;
}

/** 按扩展名判素材类型（Aholo 只认 image / video / insv 三种） */
function resourceType(file) {
  const ext = path.extname(file).toLowerCase();
  if (IMAGE_EXT.has(ext)) return 'image';
  if (VIDEO_EXT.has(ext)) return 'video';
  if (ext === '.insv') return 'insv';
  die(`不认得的素材：${file}（图片 .jpg/.jpeg/.png/.webp；视频 .mp4/.mov；全景 .insv）`);
}

/** 目录 → 里面的素材文件（按名字排序，保证可复现） */
function expandInputs(inputs) {
  const files = [];
  for (const p of inputs) {
    if (!fs.existsSync(p)) die(`找不到：${p}`);
    const st = fs.statSync(p);
    if (st.isDirectory()) {
      for (const name of fs.readdirSync(p).sort()) {
        const f = path.join(p, name);
        if (fs.statSync(f).isFile() && (IMAGE_EXT.has(path.extname(f).toLowerCase())
            || VIDEO_EXT.has(path.extname(f).toLowerCase())
            || path.extname(f).toLowerCase() === '.insv')) {
          files.push(f);
        }
      }
    } else {
      files.push(p);
    }
  }
  if (!files.length) die('一个素材都没找到');
  return files;
}

async function uploadAll(files) {
  const assets = createAssetClient({ apiKey: API_KEY, region: REGION });
  const resources = [];
  for (let i = 0; i < files.length; i++) {
    const f = files[i];
    const mb = (fs.statSync(f).size / 1048576).toFixed(2);
    process.stdout.write(`  [${i + 1}/${files.length}] 上传 ${path.basename(f)}（${mb} MB）… `);
    const t0 = Date.now();
    const r = await assets.uploadFile(f);
    console.log(`ok（${((Date.now() - t0) / 1000).toFixed(1)} s）`);
    resources.push({ url: r.url, type: resourceType(f) });
  }
  return resources;
}

async function waitFor(worldId, intervalMs = 5000, timeoutMs = 3600000) {
  const world = createWorldClient({ apiKey: API_KEY, region: REGION });
  const t0 = Date.now();
  let last = '';
  for (;;) {
    const d = await world.retrieve(worldId);
    const secs = ((Date.now() - t0) / 1000).toFixed(0);
    if (d.status !== last) {
      console.log(`  ${secs}s  ${d.status}`);
      last = d.status;
    }
    if (d.status === 'SUCCEEDED') return d;
    if (FAIL_STATUS.has(d.status)) die(`任务失败：${d.status}（worldId=${worldId}）`);
    if (Date.now() - t0 > timeoutMs) die(`等了 ${timeoutMs / 1000}s 还没完成（worldId=${worldId}）`);
    await new Promise((r) => setTimeout(r, intervalMs));
  }
}

function printDetail(d) {
  const urls = d.assets?.splats?.urls ?? {};
  console.log(`\nworldId : ${d.worldId}`);
  console.log(`name    : ${d.name ?? '—'}`);
  console.log(`scene   : ${d.scene ?? '—'}     status: ${d.status}`);
  if (urls.plyPath) console.log(`PLY     : ${urls.plyPath}`);
  if (urls.spzPath) console.log(`SPZ     : ${urls.spzPath}`);
  if (urls.lodMetaPath) console.log(`LOD meta: ${urls.lodMetaPath}`);
  if (d.assets?.imagery?.panoUrl) console.log(`全景图  : ${d.assets.imagery.panoUrl}`);
  if (!urls.plyPath && !urls.spzPath && !d.assets?.imagery?.panoUrl) {
    console.log('（还没有产物）');
  }
}

async function createReconstruction(kind, files, opts) {
  const world = createWorldClient({ apiKey: API_KEY, region: REGION });
  const types = new Set(files.map(resourceType));
  if (types.size > 1) die('图片和视频不能混着传（分两次任务）');
  const type = [...types][0];
  const name = String(opts.name || path.basename(opts._[0] || 'aholo'));
  if (type === 'image' && files.length < 20) {
    console.warn(`  ⚠️ 只给了 ${files.length} 张图 —— 官方要求 ≥ 20 张，可能会被拒或重建得很糊`);
  }
  console.log(`\n场景 ${kind}｜素材 ${files.length} 个（${type}）｜画质 ${opts.quality || 'normal'}`);
  const resources = await uploadAll(files);
  const res = await world.reconstructions.create({
    name,
    resources,
    taskQuality: String(opts.quality || 'normal'),
    scene: kind,
  });
  const worldId = res.worldId || res.world_id || res.id;
  console.log(`\n✓ 任务已创建：worldId = ${worldId}`);
  if (opts.wait) {
    const d = await waitFor(worldId);
    printDetail(d);
  } else {
    console.log(`  查进度：node tools/aholo/aholo.mjs wait ${worldId}`);
  }
  return worldId;
}

async function cmdGenerate(opts) {
  const world = createWorldClient({ apiKey: API_KEY, region: REGION });
  const prompt = typeof opts.prompt === 'string' ? opts.prompt : '';
  const image = typeof opts.image === 'string' ? opts.image : '';
  if (!prompt && !image) die('至少给一个：--prompt "..." 或 --image <本地图片>');
  const resources = [];
  if (image) {
    if (!fs.existsSync(image)) die(`找不到参考图：${image}`);
    console.log(`\n上传参考图 ${path.basename(image)}…`);
    const assets = createAssetClient({ apiKey: API_KEY, region: REGION });
    const r = await assets.uploadFile(image);
    resources.push({ url: r.url, type: 'image' });
  }
  console.log(`生成：${prompt || '(无提示词，只给参考图)'}`);
  const res = await world.generations.create({
    prompt: prompt || undefined,
    resources: resources.length ? resources : undefined,
    taskQuality: String(opts.quality || 'normal'),
  });
  const worldId = res.worldId || res.world_id || res.id;
  console.log(`\n✓ 任务已创建：worldId = ${worldId}`);
  if (opts.wait) printDetail(await waitFor(worldId));
  else console.log(`  查进度：node tools/aholo/aholo.mjs wait ${worldId}`);
}

/** PLY/SPZ → .sog → 改名 .sogdata（本工程 SogRuntime 只认 .sogdata） */
function convertToSogdata(input, outSogdata) {
  const sog = outSogdata.replace(/\.sogdata$/i, '.sog');
  console.log(`\n转换：${path.basename(input)} → ${path.basename(sog)}（npx @playcanvas/splat-transform）`);
  const r = spawnSync('npx', ['-y', '@playcanvas/splat-transform', input, sog],
    { stdio: 'inherit', shell: true });
  if (r.status !== 0) die('splat-transform 转换失败');
  fs.renameSync(sog, outSogdata);
  const mb = (fs.statSync(outSogdata).size / 1048576).toFixed(1);
  console.log(`✓ ${outSogdata}（${mb} MB）—— 拷进 splatdata/，把场景里的 sog_path 指过去`);
}

async function cmdDownload(worldId, opts) {
  const world = createWorldClient({ apiKey: API_KEY, region: REGION });
  const d = await world.retrieve(worldId);
  if (d.status !== 'SUCCEEDED') die(`任务还没成功：${d.status}（先 wait ${worldId}）`);
  const urls = d.assets?.splats?.urls ?? {};
  const want = [['ply', urls.plyPath], ['spz', urls.spzPath]].filter(([, u]) => u);
  if (!want.length) die('这个任务没有 splat 产物（生成任务可能只有全景图）');
  const outDir = String(opts.out || path.join('out', worldId));
  fs.mkdirSync(outDir, { recursive: true });
  let first = '';
  for (const [ext, url] of want) {
    const file = path.join(outDir, `${worldId}.${ext}`);
    process.stdout.write(`  下载 ${ext.toUpperCase()} … `);
    const res = await fetch(url);
    if (!res.ok) die(`下载失败：HTTP ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(file, buf);
    console.log(`${(buf.length / 1048576).toFixed(1)} MB → ${file}`);
    if (!first) first = file;
  }
  if (opts.convert && first) {
    convertToSogdata(first, path.join(outDir, `${worldId}.sogdata`));
  }
}

function usage() {
  console.log(`Aholo 3DGS CLI（区域 ${REGION}）

  whoami                     只读：调一次 /world/v1/list，确认密钥能用
  list [--page 0] [--size 10] 列最近的 3D 任务
  get <worldId>              查详情（状态 + 产物 URL）
  wait <worldId>             轮询到成功/失败
  space  <目录|文件…> [--name 名字] [--quality low|normal|high] [--wait]
  object <目录|文件…> [--name 名字] [--quality …] [--wait]
  generate [--prompt 文案] [--image 本地图] [--quality …] [--wait]
  download <worldId> [--out 目录] [--convert]
  convert <in.ply|in.spz> <out.sogdata>

环境变量：
  AHOLO_API_KEY   必填（labs.aholo3d.cn/api-keys 或 labs.aholo.ai/api-keys）
  AHOLO_REGION    cn（默认）/ com
`);
}

async function main() {
  const argv = parseArgs(process.argv.slice(2));
  const cmd = argv._.shift() || 'help';
  if (cmd === 'help' || cmd === '-h' || cmd === '--help') return usage();
  if (!API_KEY) die('没有 AHOLO_API_KEY —— 先 export/set 环境变量再跑（不要写进任何文件）');
  const world = createWorldClient({ apiKey: API_KEY, region: REGION });

  switch (cmd) {
    case 'whoami': {
      const r = await world.list({ pageNum: 0, pageSize: 1 });
      console.log(`✓ 密钥可用（区域 ${REGION}）｜账号下共 ${r.totalCount} 个 3D 任务`);
      break;
    }
    case 'list': {
      const r = await world.list({ pageNum: Number(argv.page || 0), pageSize: Number(argv.size || 10) });
      console.log(`共 ${r.totalCount} 个任务（本页 ${r.count}）`);
      for (const w of r.result || []) {
        console.log(`  ${w.worldId}  ${String(w.status).padEnd(12)}  ${w.name ?? ''}  ${w.createdAt ?? ''}`);
      }
      break;
    }
    case 'get': {
      if (!argv._[0]) die('用法：get <worldId>');
      printDetail(await world.retrieve(argv._[0]));
      break;
    }
    case 'wait': {
      if (!argv._[0]) die('用法：wait <worldId>');
      printDetail(await waitFor(argv._[0], Number(argv.interval || 5) * 1000));
      break;
    }
    case 'space':
    case 'object': {
      if (!argv._.length) die(`用法：${cmd} <目录|文件…> [--name …]`);
      const files = expandInputs(argv._);
      await createReconstruction(cmd, files, argv);
      break;
    }
    case 'generate':
      await cmdGenerate(argv);
      break;
    case 'download': {
      if (!argv._[0]) die('用法：download <worldId> --out 目录');
      await cmdDownload(argv._[0], argv);
      break;
    }
    case 'convert': {
      if (argv._.length < 2) die('用法：convert <in.ply|in.spz> <out.sogdata>');
      convertToSogdata(argv._[0], argv._[1]);
      break;
    }
    default:
      die(`不认识的命令：${cmd}（跑 help 看用法）`);
  }
}

main().catch((e) => die(e?.stack || String(e)));
