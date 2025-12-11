# KrillinAI API 接口分析文档

## 概述

本文档详细分析了 KrillinAI 服务端启动后提供的所有 API 接口的核心作用、使用方式，以及与前端的交互流程。

## 接口总览

服务端通过 Gin 框架提供以下 7 个核心接口：

| 接口路径 | 方法 | 功能描述 |
|---------|------|---------|
| `/api/capability/subtitleTask` | POST | 启动视频字幕翻译任务 |
| `/api/capability/subtitleTask` | GET | 查询任务进度和状态 |
| `/api/file` | POST | 上传视频/音频文件 |
| `/api/file/*filepath` | GET | 下载生成的文件 |
| `/api/file/*filepath` | HEAD | 检查文件是否存在 |
| `/api/config` | GET | 获取当前系统配置 |
| `/api/config` | POST | 更新系统配置 |

---

## 1. 字幕任务管理接口

### 1.1 启动字幕任务

**接口**: `POST /api/capability/subtitleTask`

**核心作用**: 
- 接收视频翻译任务请求，创建异步处理任务
- 支持视频 URL 或本地文件路径
- 配置字幕生成、翻译、配音等选项

**请求参数** (`StartVideoSubtitleTaskReq`):

```json
{
  "url": "视频URL或本地文件路径（如：local:./uploads/video.mp4）",
  "origin_lang": "源语言代码（如：zh_cn, en）",
  "target_lang": "目标语言代码（如：en, zh_cn）或 'none'（不翻译）",
  "bilingual": 1,  // 1=启用双语字幕, 2=不启用
  "translation_subtitle_pos": 1,  // 1=翻译在上, 2=翻译在下
  "modal_filter": 1,  // 1=启用语气词过滤, 2=不启用
  "tts": 1,  // 1=启用配音, 2=不启用
  "tts_voice_code": "配音声音代码（可选）",
  "tts_voice_clone_src_file_url": "音色克隆样本文件URL（可选）",
  "embed_subtitle_video_type": "视频合成类型：horizontal/vertical/all/none",
  "vertical_major_title": "竖屏视频主标题（可选）",
  "vertical_minor_title": "竖屏视频副标题（可选）"
}
```

**响应数据**:

```json
{
  "error": 0,
  "msg": "成功",
  "data": {
    "task_id": "任务ID，用于后续查询进度"
  }
}
```

**前端使用方式** (`static/index.html`):

1. 用户在工作台页面填写表单：
   - 选择视频源（URL 或本地文件）
   - 设置源语言和目标语言
   - 配置双语字幕、配音、视频合成等选项

2. 点击"开始翻译"按钮后：
   ```javascript
   // 收集表单参数
   const params = getParams();
   params.url = uploadedVideoUrl || urlInput.value;
   
   // 调用启动任务接口
   const response = await fetch("/api/capability/subtitleTask", {
     method: "POST",
     headers: { "Content-Type": "application/json" },
     body: JSON.stringify(params)
   });
   ```

3. 获取 `task_id` 后开始轮询任务进度

**配置关联** (`config/config-example.toml`):

- `app.segment_duration`: 影响视频分段处理时长
- `app.transcribe_parallel_num`: 影响转录并发数
- `app.translate_parallel_num`: 影响翻译并发数
- `app.max_sentence_length`: 影响字幕句子拆分长度
- `transcribe.provider`: 决定使用的语音识别服务
- `llm.*`: 决定翻译使用的 LLM 服务

---

### 1.2 查询任务状态

**接口**: `GET /api/capability/subtitleTask?taskId={taskId}`

**核心作用**:
- 查询指定任务的实时处理进度
- 返回任务状态、进度百分比、生成的文件下载链接

**请求参数**:
- `taskId` (Query): 任务ID，由启动任务接口返回

**响应数据** (`GetVideoSubtitleTaskResData`):

```json
{
  "error": 0,
  "msg": "成功",
  "data": {
    "task_id": "任务ID",
    "process_percent": 75,  // 处理进度 0-100
    "video_info": {
      "title": "视频标题",
      "description": "视频描述",
      "translated_title": "翻译后的标题",
      "translated_description": "翻译后的描述"
    },
    "subtitle_info": [
      {
        "name": "字幕.srt",
        "download_url": "/api/file/tasks/{taskId}/output/subtitle.srt"
      },
      {
        "name": "字幕.ass",
        "download_url": "/api/file/tasks/{taskId}/output/subtitle.ass"
      }
    ],
    "target_language": "en",
    "speech_download_url": "/api/file/tasks/{taskId}/output/speech.mp3"
  }
}
```

**前端使用方式**:

1. 启动任务后，前端每 5 秒轮询一次：
   ```javascript
   async function pollTaskProgress(taskId) {
     while (progress < 100) {
       const response = await fetch(
         `/api/capability/subtitleTask?taskId=${taskId}`
       );
       const data = await response.json();
       
       // 更新进度条
       progressBar.style.width = data.data.process_percent + "%";
       
       // 任务完成时显示下载链接
       if (data.data.process_percent >= 100) {
         displayDownloadLinks(data.data.subtitle_info, ...);
       }
       
       await new Promise(resolve => setTimeout(resolve, 5000));
     }
   }
   ```

2. 进度达到 100% 时，显示所有生成文件的下载链接

---

## 2. 文件管理接口

### 2.1 上传文件

**接口**: `POST /api/file`

**核心作用**:
- 接收用户上传的视频或音频文件
- 保存到本地 `./uploads/` 目录
- 返回文件路径供后续任务使用

**请求格式**: `multipart/form-data`

**请求参数**:
- `file` (FormData): 文件对象，支持多文件上传

**响应数据**:

```json
{
  "error": 0,
  "msg": "文件上传成功",
  "data": {
    "file_path": ["local:./uploads/video.mp4"]  // 数组形式，支持多文件
  }
}
```

**前端使用方式**:

1. **视频文件上传** (工作台页面):
   ```javascript
   fileInput.addEventListener("change", async () => {
     const formData = new FormData();
     for (const file of fileInput.files) {
       formData.append("file", file);
     }
     
     const response = await fetch("/api/file", {
       method: "POST",
       body: formData
     });
     
     const res = await response.json();
     uploadedVideoUrl = res.data.file_path;  // 保存文件路径
   });
   ```

2. **音频文件上传** (音色克隆样本):
   ```javascript
   voiceFileInput.addEventListener("change", async () => {
     const formData = new FormData();
     formData.append("file", voiceFileInput.files[0]);
     
     const response = await fetch("/api/file", {
       method: "POST",
       body: formData
     });
     
     uploadedAudioUrl = res.data.file_path;
   });
   ```

**文件存储位置**:
- 上传的文件保存在 `./uploads/` 目录
- 任务生成的文件保存在 `./tasks/{taskId}/output/` 目录

---

### 2.2 下载文件

**接口**: `GET /api/file/*filepath`

**核心作用**:
- 提供文件下载功能
- 支持下载任务生成的字幕文件、配音文件、合成视频等

**请求参数**:
- `filepath` (Path): 文件相对路径，如 `tasks/{taskId}/output/subtitle.srt`

**响应**: 
- 直接返回文件内容，浏览器自动下载

**前端使用方式**:

1. **直接下载链接**:
   ```html
   <a href="/api/file/tasks/{taskId}/output/subtitle.srt" download>
     字幕.srt
   </a>
   ```

2. **动态生成下载链接**:
   ```javascript
   function displayDownloadLinks(subtitleInfo) {
     subtitleInfo.forEach(({ name, download_url }) => {
       const link = document.createElement("a");
       link.href = download_url;  // 如：/api/file/tasks/xxx/output/subtitle.srt
       link.textContent = name;
       link.download = "";
       downloadLinks.appendChild(link);
     });
   }
   ```

---

### 2.3 检查文件是否存在

**接口**: `HEAD /api/file/*filepath`

**核心作用**:
- 检查文件是否存在，不下载文件内容
- 用于前端判断合成视频是否已生成

**请求参数**:
- `filepath` (Path): 文件相对路径

**响应**:
- `200 OK`: 文件存在
- `404 Not Found`: 文件不存在

**前端使用方式**:

```javascript
// 检查横屏/竖屏视频是否已生成
async function checkAndAddVideoLink(fileName, displayName) {
  const response = await fetch(
    `/api/file/tasks/${taskId}/output/${fileName}`,
    { method: "HEAD" }
  );
  
  if (response.ok) {
    // 文件存在，添加下载链接
    const link = document.createElement("a");
    link.href = `/api/file/tasks/${taskId}/output/${fileName}`;
    link.textContent = displayName;
    downloadLinks.appendChild(link);
  } else {
    // 文件不存在，显示提示信息
    showErrorTip(`${displayName}：生成的视频文件不存在`);
  }
}
```

---

## 3. 配置管理接口

### 3.1 获取配置

**接口**: `GET /api/config`

**核心作用**:
- 获取当前系统的所有配置项
- 用于前端配置页面初始化表单

**响应数据** (`ConfigRequest`):

```json
{
  "error": 0,
  "msg": "获取配置成功",
  "data": {
    "app": {
      "segmentDuration": 5,
      "transcribeParallelNum": 1,
      "translateParallelNum": 3,
      "transcribeMaxAttempts": 3,
      "translateMaxAttempts": 5,
      "maxSentenceLength": 70,
      "proxy": ""
    },
    "server": {
      "host": "127.0.0.1",
      "port": 8888
    },
    "llm": {
      "baseUrl": "https://api.openai.com/v1",
      "apiKey": "sk-...",
      "model": "gpt-4o-mini"
    },
    "transcribe": {
      "provider": "openai",
      "enableGpuAcceleration": false,
      "openai": { ... },
      "fasterwhisper": { ... },
      "aliyun": { ... }
    },
    "tts": {
      "provider": "aliyun",
      "openai": { ... },
      "aliyun": { ... }
    }
  }
}
```

**前端使用方式**:

1. **进入配置页面时自动加载**:
   ```javascript
   async function loadConfig() {
     const response = await fetch("/api/config", {
       method: "GET",
       headers: { "Content-Type": "application/json" }
     });
     
     const result = await response.json();
     if (result.error === 0 && result.data) {
       populateConfigForm(result.data);  // 填充表单
     }
   }
   ```

2. **表单字段映射**:
   - `segmentDuration` → `#segment-duration`
   - `transcribeParallelNum` → `#transcribe-parallel`
   - `llm.baseUrl` → `#llm-base-url`
   - 等等...

---

### 3.2 更新配置

**接口**: `POST /api/config`

**核心作用**:
- 更新系统配置并保存到 `config/config.toml`
- 验证配置有效性
- 标记配置已更新，下次启动任务时重新初始化服务

**请求参数** (`ConfigRequest`):

```json
{
  "app": { ... },
  "server": { ... },
  "llm": { ... },
  "transcribe": { ... },
  "tts": { ... }
}
```

**响应数据**:

```json
{
  "error": 0,
  "msg": "配置更新成功",
  "data": null
}
```

**配置验证规则**:

1. **转录服务配置验证**:
   - `openai`: 必须配置 `apiKey`
   - `fasterwhisper`: 模型必须是 `tiny/medium/large-v2`
   - `whisperkit`: 仅支持 macOS，模型必须是 `large-v2`
   - `whispercpp`: 仅支持 Windows，模型必须是 `large-v2`
   - `aliyun`: 必须配置完整的 OSS 和 Speech 密钥

2. **代理配置验证**:
   - 如果设置了 `proxy`，必须是可以解析的 URL

3. **配置更新流程**:
   - 更新内存中的配置
   - 验证配置有效性
   - 如果验证失败，恢复原配置
   - 如果验证成功，保存到文件并标记需要重新初始化

**前端使用方式**:

1. **手动保存配置** (点击"保存配置"按钮):
   ```javascript
   function saveConfig() {
     const configData = collectConfigData();  // 收集表单数据
     
     return fetch("/api/config", {
       method: "POST",
       headers: { "Content-Type": "application/json" },
       body: JSON.stringify(configData)
     })
     .then(response => response.json())
     .then(data => {
       if (data.error === 0) {
         alert("配置已成功保存！");
       } else {
         alert("保存配置失败: " + data.msg);
       }
     });
   }
   ```

2. **自动保存配置** (从配置页切换到工作台时):
   ```javascript
   // 页面切换时自动保存
   if (previousPage === "config" && newPage === "workbench") {
     await saveConfig(false, true);  // 不显示成功提示
   }
   ```

**配置影响**:

- 配置更新后，下次启动任务时会自动重新初始化服务
- 某些配置（如 `server.host/port`）需要重启服务才能生效
- 转录、翻译、TTS 相关配置会立即影响新任务

---

## 4. 前端页面交互流程

### 4.1 工作台页面流程

```
用户操作流程：
1. 选择视频源（URL 或本地文件）
   ↓
2. 如果选择本地文件 → 调用 POST /api/file 上传
   ↓
3. 配置字幕、翻译、配音选项
   ↓
4. 点击"开始翻译" → 调用 POST /api/capability/subtitleTask
   ↓
5. 获取 task_id，开始轮询 → 每 5 秒调用 GET /api/capability/subtitleTask?taskId=xxx
   ↓
6. 更新进度条显示
   ↓
7. 任务完成（progress_percent = 100）→ 显示下载链接
   ↓
8. 用户点击下载链接 → 调用 GET /api/file/*filepath 下载文件
```

### 4.2 配置页面流程

```
用户操作流程：
1. 进入配置页面 → 自动调用 GET /api/config 加载配置
   ↓
2. 填充表单字段
   ↓
3. 用户修改配置项
   ↓
4. 点击"保存配置" → 调用 POST /api/config
   ↓
5. 显示保存结果
   ↓
6. 切换到工作台页面 → 自动保存配置（如果未手动保存）
```

### 4.3 LLM 配置页面流程

```
用户操作流程：
1. 进入 LLM 配置页面 → 调用 GET /api/config 加载配置
   ↓
2. 点击供应商卡片（如：通义千问、OpenAI、DeepSeek）→ 自动填充 Base URL 和模型列表
   ↓
3. 选择或手动输入模型名称
   ↓
4. 配置 API Key
   ↓
5. 切换到工作台或配置页面 → 自动保存配置
```

---

## 5. 配置项详细说明

### 5.1 应用配置 (`app`)

| 配置项 | 说明 | 默认值 | 影响范围 |
|--------|------|--------|----------|
| `segment_duration` | 音频切分处理间隔（分钟） | 5 | 视频分段处理时长，建议 5-10 分钟 |
| `transcribe_parallel_num` | 转录并发数 | 1 | 同时进行转录的任务数，本地模型建议为 1 |
| `translate_parallel_num` | 翻译并发数 | 3 | 同时进行翻译的任务数，建议为转录的 3 倍 |
| `transcribe_max_attempts` | 转录最大尝试次数 | 3 | 转录失败时的重试次数 |
| `translate_max_attempts` | 翻译最大尝试次数 | 5 | 翻译失败时的重试次数 |
| `max_sentence_length` | 每句最大字符数 | 70 | 超过此长度的句子会被拆分 |
| `proxy` | 网络代理地址 | "" | 格式如 `http://127.0.0.1:7890` |

### 5.2 服务器配置 (`server`)

| 配置项 | 说明 | 默认值 | 影响范围 |
|--------|------|--------|----------|
| `host` | 服务器监听地址 | "127.0.0.1" | 服务启动的 IP 地址 |
| `port` | 服务器端口 | 8888 | 服务启动的端口号 |

### 5.3 LLM 配置 (`llm`)

| 配置项 | 说明 | 默认值 | 影响范围 |
|--------|------|--------|----------|
| `base_url` | API Base URL | "" | 留空为 OpenAI 官方 API |
| `api_key` | API 密钥 | "" | 必须配置 |
| `model` | 模型名称 | "gpt-4o-mini" | 指定使用的模型 |

**常用 Base URL**:
- OpenAI: `https://api.openai.com/v1`
- 阿里云百炼: `https://dashscope.aliyuncs.com/compatible-mode/v1`
- DeepSeek: `https://api.deepseek.com/v1`

### 5.4 转录配置 (`transcribe`)

| 配置项 | 说明 | 可选值 | 影响范围 |
|--------|------|--------|----------|
| `provider` | 转录服务提供商 | openai, fasterwhisper, whisperkit, whisper.cpp, aliyun | 决定使用的语音识别服务 |
| `enable_gpu_acceleration` | GPU 加速（仅 FasterWhisper） | true/false | 50 系显卡必须开启 |

**各 Provider 配置要求**:

- **openai**: 需要配置 `openai.base_url`, `openai.api_key`, `openai.model`
- **fasterwhisper**: 需要配置 `fasterwhisper.model` (tiny/medium/large-v2)
- **whisperkit**: 仅支持 macOS M 芯片，需要配置 `whisperkit.model` (large-v2)
- **whispercpp**: 仅支持 Windows，需要配置 `whispercpp.model` (large-v2)
- **aliyun**: 需要配置完整的 `aliyun.oss.*` 和 `aliyun.speech.*`

### 5.5 TTS 配置 (`tts`)

| 配置项 | 说明 | 可选值 | 影响范围 |
|--------|------|--------|----------|
| `provider` | TTS 服务提供商 | openai, aliyun, edge-tts | 决定使用的文本转语音服务 |

**各 Provider 配置要求**:

- **openai**: 需要配置 `openai.base_url`, `openai.api_key`, `openai.model`
- **aliyun**: 需要配置完整的 `aliyun.oss.*` 和 `aliyun.speech.*`
- **edge-tts**: 无需额外配置

---

## 6. 错误处理

### 6.1 统一响应格式

所有接口都遵循统一的响应格式：

```json
{
  "error": 0,      // 0=成功, -1=失败
  "msg": "成功",   // 错误信息或成功提示
  "data": {}       // 响应数据，失败时为 null
}
```

### 6.2 常见错误场景

1. **参数错误**:
   - `error: -1, msg: "参数错误"`
   - 通常由 JSON 解析失败或必填参数缺失引起

2. **配置验证失败**:
   - `error: -1, msg: "配置验证失败: {具体原因}"`
   - 配置项不符合要求时返回

3. **文件不存在**:
   - `error: -1, msg: "文件不存在"`
   - 下载或检查文件时，文件路径不存在

4. **任务不存在**:
   - `error: -1, msg: "任务不存在"`
   - 查询任务状态时，taskId 无效

5. **任务失败**:
   - `error: -1, msg: "任务失败，原因：{失败原因}"`
   - 任务处理过程中出错

---

## 7. 最佳实践

### 7.1 任务处理

1. **文件上传**:
   - 大文件上传时，前端应显示上传进度
   - 上传完成后保存 `file_path`，用于后续任务

2. **任务轮询**:
   - 建议轮询间隔为 5 秒，避免过于频繁
   - 任务完成后停止轮询
   - 处理网络错误和超时情况

3. **下载文件**:
   - 使用 `<a>` 标签的 `download` 属性实现下载
   - 对于大文件，考虑使用流式下载

### 7.2 配置管理

1. **配置验证**:
   - 前端应在提交前进行基本验证
   - 后端会进行完整验证，前端应处理验证失败的情况

2. **配置保存**:
   - 建议在切换页面时自动保存配置
   - 保存失败时应提示用户并保留原配置

3. **配置初始化**:
   - 配置更新后，下次启动任务时会自动重新初始化服务
   - 某些配置（如服务器地址）需要重启服务才能生效

### 7.3 错误处理

1. **网络错误**:
   - 使用 try-catch 捕获网络异常
   - 提供友好的错误提示

2. **业务错误**:
   - 检查响应中的 `error` 字段
   - 显示后端返回的 `msg` 信息

3. **超时处理**:
   - 为长时间运行的任务设置合理的超时时间
   - 提供取消任务的机制（如需要）

---

## 8. 总结

KrillinAI 的 API 接口设计简洁明了，主要分为三大类：

1. **任务管理**: 启动任务、查询进度
2. **文件管理**: 上传、下载、检查文件
3. **配置管理**: 获取、更新系统配置

前端通过简单的 HTTP 请求即可完成所有操作，后端提供统一的响应格式和错误处理机制。配置系统灵活，支持多种服务提供商，用户可以根据需求选择合适的服务。

---

**文档版本**: v1.0  
**最后更新**: 2024-12-19  
**维护者**: AI Assistant

