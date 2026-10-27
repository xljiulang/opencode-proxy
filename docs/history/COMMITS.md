# Relevant codex-ui commits

Generated from codex-ui commit `99730d4f4b46c8e633149eda128b2040f40f6256`.

| Commit | Date | Subject |
|---|---|---|
| `99730d4f4b46c8e633149eda128b2040f40f6256` | 2026-10-27 | 新增: 模拟 OpenCode 2.1.4 TLS 指纹与客户端身份 |
| `2cf58729a46c7cbd039dc795d3ed4491af262c9a` | 2026-10-15 | fix(compat_proxy): 直通时剥掉「无 encrypted_content 的 reasoning item」的 id |
| `7f2dead6759c9645bb6c70d8cd56661ce3fdbbf5` | 2026-10-15 | fix(compat_proxy): Responses 直通支持 codex 的 custom 工具（apply_patch 双向转换） |
| `5d3da4b2447d46255baa614d649ce2d3b1df5a2a` | 2026-10-15 | feat(compat_proxy): 自动识别模型协议（Responses 原生模型直通，不加开关） |
| `c5dfad0ec578d615e6297654c36a6d6eb284b420` | 2026-10-15 | fix(compat_proxy): 修复 Zen 免费层 403（端点换 /inference/v1 + 假工具带真实参数） |
| `8192f264295bc347379463921b36a5999c770743` | 2026-09-24 | chore(format): 引入统一格式化配置并全量格式化 src 与 Rust 源码 |
| `9b8d623d564f8b8a09e53ae44bfdb57fa98ffb7a` | 2026-09-22 | refactor(compat_proxy): Zen 代理重命名为「兼容代理」（全栈改名 + 设置键迁移） |
| `9bbbe8cf335c6997a4fba6e0bf49674bc575224a` | 2026-09-22 | refactor(zen_proxy): 开关一改名「回合收尾约束和助推」；OpenCode 身份去掉 host 判断 |
| `8d0bfcfc6a967a4af947841889fdf330e285ae7a` | 2026-09-22 | feat(zen_proxy): 新增「回合收尾强制约束」「OpenCode 客户端身份」两个行为开关 |
| `71aaa13f83aa8cc181cc114df7994af41357a599` | 2026-09-21 | fix(zen_proxy): 上游 host 判定放宽为含 opencode 即按 Zen 免费层补形状 |
| `f9e5948fe473cc953083b4010981247d0804698a` | 2026-09-20 | fix(zen_proxy): 弃用工具教学改写入 system 消息，不再写顶层 instructions |
| `290d9e2521090eb609bf89787a4095a49d5a9489` | 2026-09-18 | refactor(zen_proxy): 拆分 zen_proxy.rs 为模块目录，测试模块独立成文件 |
| `5e300f5239411da4223ca25b5ff649f884356d10` | 2026-09-18 | feat(zen): 动态生成弃用工具教学注入 instructions |
| `9490a95a9059c826ed98ff522945ca57bac7a4dd` | 2026-09-18 | fix(zen_proxy): 催办提醒按附件重写（两条路径 + 收尾只回标签），四个教学面不变量对齐 |
| `159af3fe0de211e8237b1019bab12c62d0017742` | 2026-09-18 | fix(zen_proxy): max_tokens 补丁值改为 32000，并明确两项补丁仅对 opencode.ai 生效 |
| `392e486a5ae8195857e8d0a93738c7645b9275b1` | 2026-09-18 | feat(zen_proxy): 补 OpenCode 请求体形状（max_tokens + 内置工具名）绕过免费层 403 |
| `5079275d97a7f5340f8a8b20ba3f12331aebd8ef` | 2026-09-18 | feat(zen_proxy): 按结构剥离三个自研标签 + 标签载荷改固定短词表 |
| `7f8623e72d82ac0e771552bb56b7f0a56a80f213` | 2026-09-18 | feat(zen_proxy): nudge 家族日志中文化 + 单请求最多注入 4 次取代会话级 streak |
| `2b0fb37551e058fbadf51c1c06f6faa65906b02c` | 2026-09-18 | feat(zen_proxy): 三个自研标签加 zen_ 前缀 + 两种模式都做首轮教学 |
| `69ab1e3d077a995bd80eb14838a641f08a70cfd5` | 2026-09-18 | fix(zen_proxy): 默认模式改「注入提醒 + <task_completed> 标签判据」，删除独立 AI 看门狗 |
| `9245b095b141eb7dc2adff2f4ad8acc6bc7ea2cd` | 2026-09-18 | fix(zen_proxy): 计划模式提示词改为排除式三选一，新增 <unachievable_plan> 标签 |
| `da8cc982e9a78cc19a05d6e5976284118098a317` | 2026-09-18 | fix(zen_proxy): 看门狗判定请求改为流式（stream: true），绕开 OpenCode 免费档对非流式的拒绝 |
| `731c1afff47e6b2a495fc65083ff31e276ea9c59` | 2026-09-17 | fix(zen_proxy): 计划模式新增 <cancelled_plan> 放弃标记，不再被逼重给已放弃的方案 |
| `628d69d4bed3f0e1732b314d5ec71b921371f180` | 2026-09-17 | fix(zen_proxy): 看门狗判定口径改为任务类型中立（修「git 提交并推送」被判未完成） |
| `74a828f85f26d72111cb12c2366e9c78271c8acf` | 2026-09-17 | fix(zen_proxy): 识别头改为合法 opencode ID 形状（修复免费层 403）+ 会话双向映射 |
| `a4742b4e92ee2665283403054bf5b14fdba26ad7` | 2026-09-17 | fix(zen_proxy): 协作模式改走协议登记表 + 计划提醒带 <proposed_plan> 骨架 + 判定超时 60s |
| `17ddb67f7096e24b18e6cdad69c8a76e1c47c241` | 2026-09-16 | fix(zen_proxy): 计划模式识别改用协作模式块标题行（0.154 文案已变，旧标记永不命中） |
| `99aad3d112fffd415e0d00bdd045c01cac245d42` | 2026-09-16 | fix(zen_proxy): 看门狗分流——计划模式代码判据、AI 判定只服务默认模式、标题请求放行 |
| `913e762915d891e93f1300279c17ef811c948abd` | 2026-09-16 | fix(zen_proxy): 计划模式下跳过口嗨检测（修复把计划当口嗨并注入「必须动手」） |
| `5857bbf1e8d171300476288ca5d2f26a6e7af754` | 2026-09-16 | chore(zen_proxy): 口嗨判定超时从 15s 调整为 25s |
| `8ad4bf56d1b8b47550f32e32f615f23aaf590783` | 2026-09-16 | feat(zen_proxy): 口嗨检测与自动续跑 |
| `d4689baa938c16f3ccdde8e65066072873e5e1cc` | 2026-09-15 | fix(zen): 补齐 apply_patch 语法说明与失败纠错回灌，修模型改文件打转 |
| `0ddba863dbb784dee5ab9f455e9ef2cb709f31ca` | 2026-09-14 | fix(zen-proxy): 自由格式工具 apply_patch 的声明、回译与历史回放 |
| `ec582a2b77fd1ac7e75a179d38ed846dbd1c6200` | 2026-09-14 | fix(zen-proxy): 命名空间工具展开与回译，修复 codexui 工具调不到 |
| `ba87ede2f9dbf27cad4d3d997461144d822f0b48` | 2026-09-14 | feat(zen-proxy): 新增请求/响应内容诊断日志，定位偶发提前收尾 |
| `9da1bcf2e0edeb75e41179fd7e0d1dc61ca003cb` | 2026-09-12 | fix(zen-proxy): rc 回传补全到 content 消息 + 尝试级诊断 |
| `a833f84356f11d34eea0f1f9be482f0f0c94d9b2` | 2026-09-12 | fix(zen-proxy): 思考模式历史回传 reasoning_content（修 DeepSeek 400） |
| `e914466d2d980a11ad688d8864ef592b70f76de8` | 2026-09-12 | fix(zen-proxy): Responses 的 developer 角色降级为 system |
| `4e5081d1004fdb06e312f2ea49e745e6efdd506c` | 2026-09-12 | fix(zen-proxy, settings): 翻译路由按 base_url 路径 + 透传零路径转换 + 参数即时生效 |
| `e9018ca84a096d1fb1393708bdae1e284b810e9b` | 2026-09-11 | fix(model-catalog, zen-proxy): 推理档位不再被空数组清零 + 记录实际发出的推理强度 |
| `b2c11e3e715a416da7770a46177daa735c296734` | 2026-09-11 | fix(zen-proxy): 修正 usage 分片丢失 + 推理形态补全 + 流内诊断 |
| `98a1e8ef9fc10efc11a6749e48146e0d4588ac72` | 2026-09-11 | feat(zen-proxy): 用量明细 + 可选字段降级 + 图片透传 + 思考过程 + 截断语义 |
| `6270b9155534b1c17b4d1908441f08deb6a44c2e` | 2026-09-11 | feat(zen-proxy, model-catalog): 强化流式健壮性与提示词瘦身 |
| `fbbcaa01bd934edf2a311544ad088fb8136e0877` | 2026-09-11 | feat(zen-proxy): x-opencode-session 优先取请求头 session-id |
| `2488f2199b531a62bc508e83d85c6c31518a9ed6` | 2026-09-09 | feat(zen-proxy): 支持其它路径通用透传 |
| `b654289355605680a34d719f90f4a9d58a9c5946` | 2026-09-09 | feat(zen-proxy): 支持可配置 API 请求地址并统一设置区保存按钮 |
| `da3570339846b815362c998c74516fc457e5c7c7` | 2026-09-09 | feat(zen-proxy): 新增 Zen 本地代理并补充诊断日志 |
