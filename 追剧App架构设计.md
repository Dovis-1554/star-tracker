# 追剧记录 App · 架构设计

> 状态：**设计稿，未开工**
> 目标端：Android only
> 同步：坚果云 WebDAV，单文件
> 外部依赖：无（不使用金山文档、不使用 TMDB 以外的元数据服务）

## 1. 范围与约束

### 要解决的问题
自建条目 → 本地记录 → 多设备同步。覆盖红果、抖音、火龙漫剧、泡漫、B 站、七猫、Netflix 等平台，以及 AI 漫剧、短剧这类在 TMDB / Trakt 上查不到的内容。

### 关键外部约束（坚果云免费版）

| 约束 | 数值 | 对架构的影响 |
|---|---|---|
| 上传流量 | 1 GB/月 | 不能频繁全量上传大文件 |
| 下载流量 | 3 GB/月 | 不能每次都无条件下载 |
| 请求频率 | 每 30 分钟 600 次 | 不能"每条记录一个文件" |
| 单文件上限 | 500 MB | 不构成约束 |

接入参数：
- 服务器地址 `https://dav.jianguoyun.com/dav/<英文目录>/`
- HTTP Basic Auth
- 用户名 = 注册邮箱，密码 = **安全选项 → 第三方应用管理生成的应用密码**（不是登录密码）

### 由此确定的两条硬规则
1. **同步单元只能是单个压缩文件**。500 条记录若拆成 500 个文件，一次同步就 500 次请求，直接撞 600 次/30 分钟限额。
2. **封面图不进同步循环**。图片是流量杀手；改为各设备本地程序化生成，结果一致。

## 2. 技术选型

| 层 | 选型 | 理由 |
|---|---|---|
| 框架 | Flutter (Dart) | 一套代码出 Android；后续若要加 Windows/桌面端零成本。你本机是 Windows，Flutter 工具链现成 |
| 本地库 | drift (SQLite) | 类型安全、支持迁移、响应式 stream |
| 压缩 | archive | gzip 编解码 |
| HTTP | dio | WebDAV 的 PUT/GET/PROPFIND/HEAD 与 TMDB 搜索 |
| 凭据存储 | flutter_secure_storage | 坚果云应用密码、TMDB API Key 加密落盘 |
| 后台同步 | workmanager | 仅在特定时机触发，不轮询 |
| 元数据 | TMDB API v3 | 免费；40 次/10 秒；需自备 Key（`language=zh-CN`） |

**关于 WebDAV 库**：pub.dev 上的 `webdav_client` 最新版 1.2.2 且年头已久。我们需要精确控制 ETag 请求头与错误码，自己实现只需 4 个方法，反而更可控。参考项目 Table Habit（Flutter + WebDAV，★1.5k）同样是自己实现的 WebDAV 层。

**未选 Kotlin 原生的取舍**：Kotlin + Room + Compose 包体更小、更原生，但锁定 Android。既然当前只要 Android，二者均可；选 Flutter 主要为后续扩展性。若你确定永远不会出 Android 之外，可改用 Kotlin。

## 3. 分层架构

```
UI 层 · Flutter
  片单列表 · 详情逐集 · 编辑条目 · 统计 · 设置
        ↓
领域层 · Repository
  条目 / 集数 / 历史的读写与统计聚合
        ↓
数据层 · 本地优先
  Drift SQLite 主存 · 封面 PNG 缓存
        ↓
同步层 · 单文件
  gzip 编解码 · WebDAV 客户端 · 逐条合并
        ↓
坚果云 WebDAV
  tracker.json.gz
```

目录结构：

```
lib/
  main.dart
  data/
    db/                 drift 数据库、表定义、DAO、迁移
    models/             Title / Episode / History
    repositories/       title_repo / episode_repo / stats_repo
  sync/
    webdav_client.dart  PUT / GET / PROPFIND / HEAD
    codec.dart          gzip + JSON 编解码
    merge.dart          逐条合并算法
    sync_service.dart   编排 + dirty 标记 + ETag
  features/
    list/  detail/  edit/  stats/  settings/
  ui/
    cover/              程序化封面生成
```

## 4. 数据模型

### titles（条目，一部剧一条）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | TEXT | uuid v4，主键 |
| name | TEXT | 标题 |
| type | TEXT | tv / anime / movie / manga / short_drama / ai_drama / comic |
| platform | TEXT | 红果 / 抖音 / 火龙漫剧 / 泡漫 / B站 / 七猫 / Netflix / 其他 |
| status | TEXT | plan / watching / paused / completed / dropped |
| totalEpisodes | INTEGER? | 总集数，未知留空 |
| coverUrl | TEXT? | 网络封面地址 |
| coverPath | TEXT? | 本地封面文件路径 |
| score | REAL? | 评分 |
| note | TEXT? | 备注 |
| startedAt | INTEGER? | 开看日期 |
| completedAt | INTEGER? | 完结日期 |
| createdAt | INTEGER | UTC 毫秒 |
| updatedAt | INTEGER | UTC 毫秒，单调递增 |
| deleted | INTEGER | 0/1，墓碑标记 |
| source | TEXT | tmdb / manual，区分数据来源 |
| tmdbId | INTEGER? | TMDB 条目 ID |
| tmdbType | TEXT? | tv / movie。TMDB 的剧集与电影 ID 空间各自独立，必须一起存 |
| originalName | TEXT? | 原名 |
| overview | TEXT? | 简介，建议截断至 200 字 |
| posterPath | TEXT? | TMDB 海报路径，如 `/abc123.jpg` |
| releaseDate | TEXT? | 首播 / 上映日期 |

> `platform`（在哪个平台看的）**TMDB 不会提供**，无论走哪条路径都必须手选。

### episodes（集数）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | TEXT | uuid |
| titleId | TEXT | 外键 → titles.id |
| season | INTEGER | 默认 1 |
| no | INTEGER | 集号 |
| watched | INTEGER | 0/1 |
| watchedAt | INTEGER? | 标记时间 |
| updatedAt | INTEGER | UTC 毫秒 |

> 用独立的集数表而非 `currentEpisode` 单字段，是为了支持跳看、重看标记。短剧常见 80+ 集，几千行对 SQLite 无压力，gzip 后增量极小。

### history（操作历史，可选）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | TEXT | uuid |
| titleId | TEXT | 外键 |
| action | TEXT | add / watched / status / completed |
| value | TEXT | 变更值 |
| at | INTEGER | UTC 毫秒 |

用于「本月进度」「看了多少部」之类统计。若觉得冗余，M1 可不做。

### 新建条目：TMDB 搜索优先

```
输入标题
  ↓ 300ms debounce
GET /search/tv + /search/movie    language=zh-CN
  ↓
有结果 → 候选列表（海报 + 标题 + 年份 + 类型）
  ↓ 点选
自动填充：标题 / 原名 / 简介 / 海报 / 总集数 / 日期
  ↓
确认页：补平台、状态、评分 → 保存

无结果 / 未联网 / 主动跳过 → 手动创建（原有表单）
```

要点：
- **只存 `posterPath`，不下载图片**。运行时拼 `https://image.tmdb.org/t/p/w500{path}`。不占坚果云流量
- 海报加载失败或离线 → 降级到程序化生成的占位图，复用已有机制
- 搜索失败不阻塞：超时 3～5 秒即转手动，保证断网可继续录入
- 总集数取 TMDB 的 `number_of_episodes`；连载中的剧该值常不准，允许手动改
- 需要用户自备 TMDB API Key，存 `flutter_secure_storage`，设置页可开关

### 元数据提供者：多源 + 兜底手动

没有单一数据源能覆盖全部场景。抽象出 `MetadataProvider` 接口，实现多个：

```dart
abstract class MetadataProvider {
  String get id;                       // bangumi / douban / tmdb / tvmaze
  Future<List<Candidate>> search(String keyword);
  Future<Metadata?> detail(String externalId);
}
```

搜索时按用户配置的优先级依次尝试，**第一个有结果的就用，全部失败转手动**。

| 源 | 定位 | 接入方式 | 2026-09-12 广州实测 |
|---|---|---|---|
| **豆瓣** ✅ | 国产剧 / 国漫 / 番剧，中文覆盖最好 | 非官方接口 `movie.douban.com/j/subject_suggest`，需带 `Referer` | **可用，0.3～0.8s**。返回字段齐全：`title` `year` **`episode`（集数）** `img`（封面）`id` |
| Bangumi ❌ | 动漫 / 国漫 | 官方 API `api.bgm.tv/v0` | **不可用：DNS 被污染**，`bgm.tv` / `bangumi.tv` 解析到 Facebook IP 段（31.13.x / 66.220.x），主站与 API 均无法访问 |
| TMDB ❌ | 欧美剧 / 电影 | 官方 API，需 Key | API 域名不可达；图片 CDN 可达 |
| AniList ⚠️ | 动漫 | GraphQL | 可达但持续 429 限流 |
| TVmaze ⚠️ | 欧美剧 | 官方 API，无需 Key | 可达（约 3.7s），中文内容极少 |

**推荐优先级：豆瓣 → TVmaze → 手动。** 设置页可开关、可排序。

### 豆瓣接入要点

请求：

```
GET https://movie.douban.com/j/subject_suggest?q={关键词}
Headers: Referer: https://movie.douban.com/
         User-Agent: <正常浏览器 UA>
```

实测覆盖（2026-09-12）：

| 关键词 | 结果 |
|---|---|
| 仙逆 | 5 条，集数准确（第一季 24 / 年番2 52 / 年番3 52） |
| 盗墓笔记 | 5 条 |
| 漫长的季节 | 12 集 |
| 龙王、逆天邪神 | **0 条** |

**图片必须带 Referer**：`doubanio.com` 对无 Referer 请求返回 **HTTP 418**。Flutter 侧用 `CachedNetworkImage` 的 `httpHeaders` 带上即可；加载失败降级到程序化生成的封面。

三条限制，必须接受：
1. 非官方接口，随时可能变更或加限
2. **不返回简介**，详情页抓取会被反爬拦截（返回 2.9KB 验证页），故 `overview` 只能留空
3. 短剧 / AI 漫剧 / 七猫这类**基本搜不到**，与预期一致

**参考项目的做法**——都不是单源：

| 项目 | 策略 |
|---|---|
| MoviePilot ★11.7k | 多源并存模块：`douban`（同时有 `apiv2.py` 和 `scraper.py` 两条路）、`bangumi`、`anilist`、`tmdb`、`imdb`，可配置优先级与开关 |
| Yamtrack ★3.5k | 按媒体类型分源：TMDB 影视、MAL/AniList 动漫、MangaUpdates 漫画、IGDB 游戏、Hardcover 图书；**并保留自定义条目作为兜底** |
| animeko ★20k | 用 Bangumi 做追番云收藏同步 |
| Auto_Bangumi ★8.2k | Bangumi 追番 |

**这正是 Yamtrack 一开始就设计"自定义条目"的原因**——任何元数据方案都必须有手动兜底。

> 注意：豆瓣 `subject_suggest` 是非官方内部接口，随时可能变更或加限制。自用风险可控，但不能作为唯一依赖。

### 仅本地、不参与同步的表
- `sync_state`：`lastSyncedEtag` / `lastSyncedAt` / `deviceId`
- 封面缓存索引：各设备本地生成，不上传
- 各源的 API Key：存 `flutter_secure_storage`，不进同步文件

### 同步文件格式

```json
{
  "schema": 1,
  "deviceId": "uuid",
  "exportedAt": 1757000000000,
  "titles":   [ ... ],
  "episodes": [ ... ],
  "history":  [ ... ]
}
```

序列化 → gzip → `tracker.json.gz`。几百条记录原始几百 KB，压缩后通常 30 KB 量级。

## 5. 同步协议

### 判定流程

```
开始同步
  ↓
PROPFIND 读取远端 ETag                       ← 1 次请求
  ↓
ETag 与本地记录一致？
  ├─ 远端无文件（404）→ 直接 PUT → 记录 ETag
  ├─ 一致           → 本地有 dirty 才 PUT
  └─ 不一致         → GET 下载 → 逐条合并 → PUT → 记录新 ETag
```

一次完整同步 **1～3 次请求**。每天同步十次也不足 50 次，远低于 600 次/30 分钟。

### 合并算法

```dart
for (final id in {...local.ids, ...remote.ids}) {
  final l = local[id], r = remote[id];
  merged[id] =
      l == null ? r
    : r == null ? l
    : (l.updatedAt >= r.updatedAt ? l : r);
}
```

三条规则：
1. 按 `uuid` 对齐，取 `updatedAt` 大者（last-write-wins）
2. **删除用墓碑**：`deleted=1` 本质是一次 `updatedAt` 更大的更新。若真删，A 设备删掉的记录会被 B 设备上传时"复活"
3. 设备时钟可能不准 → `updatedAt = max(now, 已知最大 updatedAt + 1)`，保证单调，避免时间回拨导致旧数据覆盖新数据

### 触发时机
- App 恢复前台（debounce 5 秒）
- 数据变更后 30 秒 debounce
- 设置页手动「立即同步」

**不做定时轮询**——白白消耗请求配额。

## 6. 封面生成

无封面时程序化生成占位图：

1. 配色：`hue = (name.hashCode & 0xFFFF) % 360`，S=0.42，L=0.46。同一标题永远得到同一颜色
2. 尺寸 300×450（2:3 海报比例）
3. 绘制：`CustomPainter` → `PictureRecorder` → `toImage()` → PNG bytes
4. 落盘：`getApplicationDocumentsDirectory()/covers/{id}.png`
5. 重绘条件：标题文本变化

有真实封面时优先用 `coverUrl`（网络）或 `coverPath`（本地），加载失败降级到生成的占位图。

因为算法是确定性的，各设备生成的图完全一致，所以不需要同步——省流量。

## 7. Android 工程要点

- `minSdk` 26（Android 8.0）足够
- 存储用 app 私有目录，**不需要申请任何存储权限**
- WebDAV 凭据存 `flutter_secure_storage`
- 网络请求放前台，同步期间显示状态；失败保留 dirty 标记下次重试
- 首屏列表用 drift 的 stream，数据变化自动刷新

## 8. 里程碑

| 阶段 | 内容 | 产出 |
|---|---|---|
| M1 | 数据层 + 条目 CRUD + 自建条目表单 + 封面生成 | 纯本地可用的记录 App |
| M2 | TMDB 搜索接入（搜索态 + 候选列表 + 降级手动） | 录入可自动填充 |
| M3 | WebDAV 配置页 + 上传/下载 + 合并 | 两台手机可互相同步 |
| M4 | 逐集打勾 + 统计页 | 完整功能 |
| M5 | 冲突场景打磨 + 断网/弱网验证 | 可日常使用 |

M1 不碰网络，先把数据模型和 UI 跑通。M3 是技术风险最高的部分，单独一个阶段验证。M2 依赖 TMDB 连通性，若实测不通则整体降级为纯手动，不影响其余阶段。

## 9. 已知风险

- **同名条目**：两设备分别新建同名剧会产生两条独立记录（不同 uuid）。个人使用概率低，可接受；若介意，可在新建时提示已存在同名条目
- **并发编辑同一条**：LWW 会丢一方的修改。个人多设备场景极少发生
- **坚果云限制变动**：官方文档对请求频率有 600 次与 1200 次两种说法，实测为准。付费版为 1500 次/30 分钟
- **文件名编码**：坚果云路径含中文需 URL 编码，建议目录与文件名**全部用英文**
- **TMDB 国内连通性（2026-09-12 实测，广州网络）**：`api.themoviedb.org` **完全不可达**（6 次请求全部超时）；`image.tmdb.org` **可达**（HTTP 正常响应）。即：搜索拿不到，图片能显示。应对措施：
  - 设置页 TMDB 基地址可配置，默认官方地址，可改为自建反代
  - TMDB 功能可整体开关，关闭后 App 完整可用（搜索失败即降级手动，已保证）
  - 可选进阶：Cloudflare Worker 反代 TMDB API（免费额度 10 万请求/天，绑定自有域名后国内较稳；`workers.dev` 域名本身在国内不稳定）
- **TMDB 无中文短剧数据**：预期的核心场景——红果、抖音短剧、AI 漫剧、七猫——大概率搜不到，仍走手动路径。TMDB 主要提升海外剧与部分国产剧的录入效率
- **TMDB 署名要求**：其条款要求展示数据时注明来源。自用不上架风险很低，但设置页建议保留一行署名

## 10. UI 设计

六个页面，深色主题，主色青绿。

### 页面清单

| 页面 | 内容 |
|---|---|
| 片单 · 封面墙 | 2 列海报网格，状态筛选 chips，海报下方标题 + 进度 |
| 片单 · 列表视图 | 单列，小封面 + 标题 + 平台·进度 + 状态标签 |
| 详情 | 大封面 + 元信息 + 进度条 + 集数网格（5 列） |
| 新建条目 | 标题 / 类型 / 平台 / 总集数 / 状态，类型平台状态用 chips |
| 统计 | 三张指标卡 + 类型占比条 + 本月进度条 |
| 设置 · 同步 | 坚果云：服务器地址 / 账号 / 应用密码 / 远程文件 + 立即同步。TMDB：API Key / 基地址 / 功能开关 |

### 设计规格

| 项 | 值 |
|---|---|
| 主题 | 深色 |
| 背景 | `#222220` |
| 卡片 / 输入框 | `#444441`，圆角 6–8 |
| 边框 | `#5F5E5A`，0.5px |
| 主文字 / 次文字 / 弱文字 | `#D3D1C7` / `#B4B2A9` / `#888780` |
| 主色（按钮、选中态、已完成） | `#1D9E75`，其上文字 `#E1F5EE` |
| 辅色（封面占位） | `#0F6E56` `#085041` `#185FA5` `#0C447C` |
| 正文字号 | 11px 起，标题 17px，指标数字 18px |
| 封面比例 | 2:3，封面墙 77×104，详情页 80×120，列表 40×54 |

### 关键交互

- **集数网格**：已看填充主色，未看灰底描边。底部常驻「标记下一集已看」，短剧集数多时避免反复点
- **筛选**：状态为主筛选（全部 / 在看 / 想看 / 完结 / 弃），平台筛选放二级，避免首屏过挤
- **已看/未看**：仅靠颜色区分不够，未看格保留集号数字 + 描边，弱视条件下也可辨
- **封面生成**：色相由标题 hash 决定，白字居中，2:3。同一标题在任何设备上得到同一张图，因此不需要同步

### 待定

- 封面墙是否需要长按多选（批量改状态 / 批量删除）
- 是否需要搜索框（条目超过 100 条后有必要）
- 底部导航栏是否要放（当前稿用顶栏，页面只有四个）

## 11. 参考项目

| 项目 | 星数 | 可借鉴点 |
|---|---|---|
| [Table Habit](https://github.com/FriesI23/mhabit) | 1.5k | Flutter + sqflite + archive 自实现 WebDAV；有完整同步设计文档 `docs/wiki/Design:-WebDAV-Sync.md`。注意其"每条一个文件"的方案在坚果云限额下不可照搬 |
| [BeeCount](https://github.com/TNT-Likely/BeeCount) | 2.3k | local-first + WebDAV/S3/iCloud 同步架构 |
| [remotely-save](https://github.com/remotely-save/remotely-save) | 8k | WebDAV 冲突处理经典实现（已停更，仅看思路） |
