# zilliz / zz 操作 Zilliz Cloud 最佳实践

本文面向 `zilliz` / `zz` CLI 用户，整理日常操作 Zilliz Cloud 时推荐的使用方式。`zilliz` 与 `zz` 行为完全一致，`zz` 只是更短的别名 —— 下面所有命令都可以替换成 `zz`（例如 `zz cluster list`）。

不带任何参数直接运行 `zilliz` 或 `zz` 会进入交互式 TUI 界面，本文示例统一使用 CLI 形式。

## 1. 首次使用

首次使用建议运行引导流程：

```bash
zilliz quickstart
```

它会引导完成登录、组织选择、集群上下文设置，并输出常用命令。

非交互环境只查看命令提示：

```bash
zilliz quickstart --non-interactive
```

已登录时跳过登录步骤：

```bash
zilliz quickstart --skip-login
```

## 2. 登录和认证

### 本地人工使用

推荐浏览器登录：

```bash
zilliz login
```

无桌面环境（远程/容器）中，禁用自动打开浏览器并使用 stderr 上打印的 URL：

```bash
zilliz login --no-browser
```

退出登录并清除本地凭据：

```bash
zilliz logout
```

### API Key 登录

交互式输入 API key：

```bash
zilliz login --api-key
```

直接传入 API key：

```bash
zilliz login --api-key sk-xxx
```

自动化和 CI 中更推荐使用环境变量，避免 API key 出现在 shell history 中：

```bash
export ZILLIZ_API_KEY=sk-xxx
zilliz cluster list
```

### 中国区 Cloud

中国区只支持 API key 登录，`--cn` 必须配合 `--api-key`：

```bash
zilliz login --cn --api-key
```

或直接传入（不推荐在共享 shell 中使用）：

```bash
zilliz login --cn --api-key sk-xxx
```

`--cn` 会使用 `api.cloud.zilliz.com.cn`，并持久保存 endpoint，后续命令会继续访问中国区，直到执行 `zilliz logout` 或对全球区重新 `zilliz login` 为止。

### 配置文件

CLI 状态保存在 `~/.zilliz/` 下（可用 `ZILLIZ_CONFIG_DIR` 覆盖）：

- `~/.zilliz/credentials` —— `api_key`, `user`, `org`, `plan`（Unix 下权限 `0o600`）
- `~/.zilliz/config` —— `cluster_id`, `endpoint`, `database`

`ZILLIZ_API_KEY` 环境变量优先级高于 `credentials` 文件。CI 中建议把 `ZILLIZ_CONFIG_DIR` 指向临时目录，避免污染 Runner 上的全局配置。

## 3. 确认当前身份和组织

查看当前登录状态：

```bash
zilliz whoami
```

别名：

```bash
zilliz info
```

切换组织：

```bash
zilliz switch
```

指定组织 ID：

```bash
zilliz switch <org-id>
```

生产操作前建议固定执行：

```bash
zilliz whoami
zilliz context current
```

确认当前账号、组织和集群上下文是否正确。

## 4. Cluster Context

Data-plane 操作，例如 collection、vector、index，通常需要先设置 cluster context。

交互式设置：

```bash
zilliz context set
```

指定 cluster ID：

```bash
zilliz context set --cluster-id <cluster-id>
```

查看当前 context：

```bash
zilliz context current
```

清除 context：

```bash
zilliz context clear
```

如果命令提示没有设置 context，执行：

```bash
zilliz context set --cluster-id <cluster-id>
```

多集群用户可以在 shell 中保存常用 cluster ID：

```bash
export DEV_CLUSTER=...
export PROD_CLUSTER=...

zilliz context set --cluster-id "$DEV_CLUSTER"
```

## 5. Control-plane 和 Data-plane

### Control-plane 操作

用于管理云资源，例如：

```bash
zilliz cluster list
zilliz cluster describe
zilliz project list
zilliz backup list
zilliz billing usage
```

这类命令主要访问 Zilliz Cloud 管理 API。

### Data-plane 操作

用于操作 Milvus 数据，覆盖的资源包括：

- `collection`, `alias`, `external-collection`
- `database`, `partition`, `index`
- `vector`（insert, upsert, search, hybrid-search, query, get, delete）
- `user`, `role`（仅 Dedicated 集群）

```bash
zilliz collection list
zilliz collection describe --name <name>
zilliz vector search
zilliz index create
```

这类命令依赖当前 cluster context。

推荐习惯：

- 管理 cluster / project 前，确认当前组织。
- 操作 collection / vector 前，确认当前 context。

## 6. 输出格式

支持的输出格式：

```bash
-o table
-o json
-o yaml
-o csv
-o text
```

默认是 `table`。

人工查看推荐默认表格：

```bash
zilliz cluster list
zilliz collection list
```

脚本和自动化推荐 JSON：

```bash
zilliz cluster list -o json
```

配合 `jq`：

```bash
zilliz cluster list -o json | jq .
```

导出 CSV：

```bash
zilliz cluster list -o csv > clusters.csv
```

不输出表头：

```bash
zilliz cluster list -o csv --no-header
```

## 7. 使用 JMESPath 过滤输出

`--query` 支持 JMESPath，用于在 CLI 内部筛选输出。

示例：

```bash
zilliz cluster list -o json --query "clusters[*].{id:clusterId,name:clusterName}"
```

只取 cluster ID：

```bash
zilliz cluster list -o json --query "clusters[*].clusterId"
```

建议：

- 人工查看用 `table`。
- 脚本处理用 `json`。
- 复杂字段筛选用 `--query`。
- 需要进一步处理时配合 `jq`。

## 8. 高风险操作

删除、释放、暂停、恢复、清理等高风险操作会要求确认。

例如：

```bash
zilliz collection drop --name <name>
```

脚本中可以显式跳过确认：

```bash
zilliz collection drop --name <name> --yes
```

最佳实践：

- 人工操作生产资源时不要随意加 `--yes`。
- 脚本中必须显式加 `--yes`，避免阻塞。
- 删除或恢复前先 describe 确认目标资源。

生产删除前建议：

```bash
zilliz whoami
zilliz context current
zilliz collection describe --name <name>
zilliz collection drop --name <name>
```

## 9. 异步任务

部分 control-plane 操作是异步任务，例如创建集群、恢复备份等。推荐使用 `--wait` 等待任务完成：

```bash
zilliz cluster create --wait
```

建议：

- 人工创建、恢复、变更资源时使用 `--wait`。
- CI 中后续步骤依赖资源完成时使用 `--wait`。
- 不使用 `--wait` 时，命令可能只返回 jobId，需要后续单独查询状态：

```bash
zilliz job describe --job-id <job-id>
```

## 10. 分页和完整导出

列表类接口如果支持分页，可以使用 `--all` 拉取完整结果：

```bash
zilliz cluster list --all
```

导出完整 JSON：

```bash
zilliz cluster list --all -o json > clusters.json
```

导出完整 CSV：

```bash
zilliz cluster list --all -o csv > clusters.csv
```

建议：

- 人工查看少量数据时不加 `--all`。
- 脚本导出完整数据时加 `--all`。

## 11. 复杂请求体

创建 collection、index 等复杂对象时，推荐把 JSON 请求体放入文件，使用 `--body file://...`：

```bash
zilliz collection create --body file://schema.json
```

建议：

- 复杂 schema 放到 JSON 文件中。
- schema 文件纳入版本管理。
- 生产资源变更通过 code review。
- 避免在 shell 中拼接很长的 JSON。

## 12. Collection 操作建议

常见流程：

```bash
zilliz context set --cluster-id <cluster-id>
zilliz collection list
zilliz collection describe --name <name>
```

创建 collection：

```bash
zilliz collection create --body file://schema.json
```

删除 collection 前先确认：

```bash
zilliz context current
zilliz collection describe --name <name>
zilliz collection drop --name <name>
```

脚本中删除：

```bash
zilliz collection drop --name <name> --yes
```

## 13. 本地 Milvus standalone

本地开发场景下可以直接通过 CLI 管理一个 Milvus standalone Docker 实例（封装上游 `standalone_embed.sh`）：

```bash
zilliz milvus standalone install    # 下载脚本到 ./milvus-standalone
zilliz milvus standalone start      # 启动容器
zilliz milvus standalone stop
zilliz milvus standalone restart
zilliz milvus standalone delete --yes   # 高风险：会清除数据卷
zilliz milvus standalone upgrade --yes  # 高风险：拉取最新脚本
```

常用参数：`--dir <path>` 指定安装目录，`--dry-run` 仅预览不执行。

需要 bash 和可用的 Docker。`start` 后默认端口：Milvus `localhost:19530`、WebUI `http://localhost:9091`、内置 etcd `localhost:2379`。

## 14. Backup

常见命令：

```bash
zilliz backup list --cluster-id <cluster-id>
zilliz backup describe --cluster-id <cluster-id> --backup-id <id>
```

`backup describe` 必须同时传 `--cluster-id`（源集群）和 `--backup-id`。

恢复分两种粒度：

```bash
# 整个备份恢复到一个全新集群
zilliz backup restore-cluster \
  --cluster-id <source-cluster-id> \
  --backup-id <backup-id> \
  --project-id <target-project-id> \
  --name <new-cluster-name> \
  --cu-size <n> \
  --collection-status LOADED \
  --wait

# 选定 collection 恢复到已有集群
zilliz backup restore-collection \
  --cluster-id <source-cluster-id> \
  --backup-id <backup-id> \
  --dest-cluster-id <target-cluster-id> \
  --body file://restore.json
```

建议：

- 恢复前用 `backup describe` 确认 backup 所属 cluster、project 和 region。
- `restore-cluster` 完成后用 `cluster list` / `cluster describe` 验证；`restore-collection` 完成后用 `collection list` 验证。
- 恢复和删除属于高风险操作，生产环境谨慎使用 `--yes`。

## 15. On-demand Cluster / VectorLake

查看 on-demand cluster：

```bash
zilliz on-demand-cluster list
zilliz on-demand-cluster describe
```

设置 VectorLake on-demand cluster context 时使用：

```bash
zilliz context set --cluster-id <cluster-id> --on-demand
```

建议：

- on-demand cluster 设置 context 时使用 `--on-demand`。
- 确认当前 project、region 和 cluster 是否匹配。
- 注意 on-demand cluster 参数可能与普通 Dedicated cluster 不同。

## 16. Shell Completion

安装补全：

```bash
zilliz completion install
```

查看状态：

```bash
zilliz completion status
```

卸载补全：

```bash
zilliz completion uninstall
```

打印补全脚本：

```bash
zilliz completion show bash
zilliz completion show zsh
zilliz completion show fish
```

建议日常频繁使用 CLI 的用户安装 completion。

## 17. 命令历史

查看历史：

```bash
zilliz history list
```

搜索历史：

```bash
zilliz history search --keyword cluster
```

清除历史：

```bash
zilliz history clear
```

建议：

- 用 history 找回复杂命令。
- 敏感参数会被脱敏，但仍不建议在命令行直接传 API key。
- 共享机器或跳板机上定期清理 history。

## 18. 升级

检查新版本：

```bash
zilliz upgrade --check
```

升级：

```bash
zilliz upgrade
```

跳过确认：

```bash
zilliz upgrade --yes
```

强制重装（升级器中途失败时有用）：

```bash
zilliz upgrade --force
```

别名：

```bash
zilliz update
```

建议：

- 遇到兼容性问题时先检查版本。
- 团队成员尽量使用接近版本，避免行为差异。
- CI 中建议固定版本，不建议每次自动升级。

## 19. CI / 自动化

CI 中推荐使用独立配置目录和环境变量 API key：

```bash
export ZILLIZ_API_KEY="$ZILLIZ_API_KEY"
export ZILLIZ_CONFIG_DIR="$RUNNER_TEMP/.zilliz"

zilliz cluster list -o json
```

如果需要 data-plane 操作：

```bash
export ZILLIZ_API_KEY="$ZILLIZ_API_KEY"
export ZILLIZ_CONFIG_DIR="$RUNNER_TEMP/.zilliz"

zilliz context set --cluster-id "$CLUSTER_ID"
zilliz collection list -o json
```

建议：

- 使用 `ZILLIZ_API_KEY`，不要在脚本中硬编码 API key。
- 使用独立 `ZILLIZ_CONFIG_DIR`，避免污染机器全局配置。
- 输出统一使用 `-o json`。
- 高风险操作显式加 `--yes`。
- 异步操作使用 `--wait`。
- 完整列表导出使用 `--all`。
- 所有必填参数显式传入，不依赖交互式 prompt。

## 20. 常用模板

查看当前状态：

```bash
zilliz whoami
zilliz context current
```

登录并设置 cluster：

```bash
zilliz login
zilliz switch
zilliz context set
```

列出 clusters：

```bash
zilliz cluster list -o json
```

获取 cluster ID：

```bash
zilliz cluster list -o json --query "clusters[*].clusterId"
```

设置 data-plane context：

```bash
zilliz context set --cluster-id <cluster-id>
```

查看 collections：

```bash
zilliz collection list
```

创建 collection：

```bash
zilliz collection create --body file://schema.json
```

删除 collection：

```bash
zilliz collection describe --name <name>
zilliz collection drop --name <name>
```

脚本删除 collection：

```bash
zilliz collection drop --name <name> --yes
```

创建资源并等待完成：

```bash
zilliz cluster create --wait
```

导出列表：

```bash
zilliz cluster list --all -o csv > clusters.csv
```

## 21. 常见问题

### 忘记设置 context

现象：

```text
No cluster context set
```

解决：

```bash
zilliz context set --cluster-id <cluster-id>
```

### 操作错组织

先确认身份并切换组织：

```bash
zilliz whoami
zilliz switch
```

### 操作错 cluster

先确认 context：

```bash
zilliz context current
zilliz context set --cluster-id <cluster-id>
```

### API key 泄露到 shell history

不推荐：

```bash
zilliz login --api-key sk-xxx
```

推荐：

```bash
export ZILLIZ_API_KEY=sk-xxx
zilliz cluster list
```

或交互输入：

```bash
zilliz login --api-key
```

## 22. 简要清单

1. 首次使用运行 `zilliz quickstart`。
2. 本地人工登录使用 `zilliz login`。
3. CI 使用 `ZILLIZ_API_KEY`。
4. Data-plane 操作前设置 `zilliz context set --cluster-id <id>`。
5. 生产操作前确认 `zilliz whoami` 和 `zilliz context current`。
6. 脚本输出使用 `-o json`。
7. 复杂过滤使用 `--query`。
8. 完整分页数据使用 `--all`。
9. 异步任务使用 `--wait`。
10. 删除类脚本显式使用 `--yes`。
11. 复杂请求体使用 `--body file://xxx.json`。
12. 定期检查版本 `zilliz upgrade --check`。
