# kdtools

K8S Network Debug Tools — 一個用於 Kubernetes 網路與資源測試的容器化工具。內建 HTTP server，可透過 API 觸發 CPU、記憶體、lock contention 等負載模擬。

## 快速開始

```bash
# Build image
docker build -t kdtools .

# 啟動（預設 port 80）
docker run -p 8080:80 kdtools

# 自訂 port
docker run -e PORT=8888 -p 8888:8888 kdtools

# 進入 shell 除錯
docker run -it kdtools bash
```

## HTTP Endpoints

所有 endpoint 回傳 `text/plain`，response body 包含 path、時間、hostname、server/client socket 資訊。

| Endpoint | 說明 | 預設值 |
|----------|------|--------|
| `GET /help` | 列出所有 endpoint 說明 | — |
| `GET /cpu` | 燒 CPU（busy loop）5 秒，消耗約一個 core | 5s |
| `GET /cpu/<sec>` | 燒 CPU 指定秒數 | — |
| `GET /cpulock` | 搶全局鎖後燒 CPU，所有同時請求會序列化執行 | 10s |
| `GET /cpulock/<sec>` | 同上，指定秒數 | — |
| `GET /mem` | 分配 200MB anonymous memory | 200MB |
| `GET /mem/<mb>` | 分配指定 MB | — |
| `GET /memfree` | 釋放所有已分配的記憶體 | — |

### 範例

```bash
# 燒 CPU 10 秒
curl http://localhost:8080/cpu/10

# 分配 500MB 記憶體
curl http://localhost:8080/mem/500

# 釋放記憶體
curl http://localhost:8080/memfree

# 模擬 lock contention（多個 terminal 同時執行）
curl http://localhost:8080/cpulock/5 &
curl http://localhost:8080/cpulock/5 &
```

## 注意事項

**CPU 測試**：`/cpu` 每個請求消耗約一個 core。要製造多核壓力，需同時發送多個並發請求。

**記憶體測試**：`/mem` 使用 anonymous memory，直接計入 cgroup `working_set`，可被 metrics-server 偵測並觸發 HPA memory scaling。記憶體會持續佔用直到呼叫 `/memfree` 或容器重啟。

**Lock contention**：`/cpulock` 使用 process-level 全局鎖，所有並發請求會被序列化，可模擬資源競爭情境。

## 預裝工具

容器基於 Ubuntu 24.04，預裝以下工具：

- **網路除錯**：`curl`, `wget`, `dnsutils`, `net-tools`, `iproute2`, `netcat`, `tcpdump`, `iftop`, `lsof`
- **資料庫 client**：`mysql-client`, `postgresql-client`
- **雲端**：`aws-cli v2`
- **其他**：`git`, `jq`, `vim`, `tmux`, `python3`, `htop`
