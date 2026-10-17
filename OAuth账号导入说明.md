# ChatGPT / Codex OAuth 账号导入

当前 New API v1.0.0-rc.44 支持渠道类型 57：ChatGPT Subscription (Codex)。此接口导入已有 OAuth 凭据，不负责自动登录 OpenAI、注册账号或获取 OAuth 授权。其他项目必须按本说明转换请求格式，不能把 Sub2API 的专有 API 地址直接替换为本接口。

## API 与密钥

- API：`POST http://<服务器局域网IP>:18327/api/channel/`
- 同机调用：`POST http://127.0.0.1:18327/api/channel/`
- 密钥与完整请求头：项目内 `config/oauth-import-api.json`。
- 请求头：`Authorization: Bearer <api_key>`、`New-Api-User: <文件中的用户ID>`、`Content-Type: application/json`。

该密钥是管理 API 访问令牌，不是模型推理令牌。使用官方安全验证和令牌创建 API 生成，无到期时间；可在管理员个人设置的访问令牌管理中撤销“OAuth账号导入专用”。权限为渠道读取、编辑和敏感写入，后者也允许创建/删除渠道和修改渠道密钥；没有授予完整密钥查看、用户管理或系统配置权限。

## 请求格式

参考以下两个 JSON 文件，替换 OAuth 凭据和模型名称后提交：

- `config/oauth-import-proxy.example.json`：该账号走 `http://127.0.0.1:7890`。
- `config/oauth-import-direct.example.json`：该账号直连。

外层结构是 `{"mode":"single","channel":{...}}`。`channel.key` 必须是 **JSON 字符串**，内部至少包含 `access_token` 和 `account_id`；可附带 `refresh_token`、`id_token`、`email`、`expired`、`last_refresh`。`channel.setting` 也必须是 JSON 字符串，代理字段为 `proxy`。账号导出文件若为嵌套 tokens 格式，需先提取并扁平化相应字段。

一个账号创建一个独立渠道。空代理表示直连；指定 `http://127.0.0.1:7890` 表示代理。这里的 127.0.0.1 指运行中转站的电脑，不是调用 API 的其他电脑。全局代理已关闭，因此未指定代理的渠道不会自动走 7890。

接口通常返回 `success` 判断操作结果，不能仅凭 HTTP 200 判断导入成功。真实模型可用性、OAuth 刷新与推理调用仍需合法有效凭据测试。当前没有导入真实账号。

## 已验证

专用令牌可以读取渠道列表，且重启后仍可使用。用空 OAuth 对象提交导入请求时，接口返回缺少 access_token 的校验错误，验证鉴权与导入处理链路；没有创建测试渠道。

初始示例文件不含真实 OAuth 凭据。填入真实凭据后不要提交到 Git 或公开分享；也不要将管理 API 密钥填入普通模型客户端。
