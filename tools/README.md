# gen_art — AI 批量生图工具

把 `art_prompts.yaml` 里定义的所有素材，批量调 [CogView-3-Flash](https://docs.bigmodel.cn/cn/guide/models/free/cogview-3-flash)（智谱，免费）生成图片，自动下载并按命名规范入库到 `client/src/assets/`。

> 管线设计见 [`docs/ART_PIPELINE.md`](../docs/ART_PIPELINE.md)：CogView 出草图与批量素材，Seedream 4.5 / GLM-Image 精修一致性敏感素材。

## 安装

无需手动安装依赖。脚本用 [PEP 723](https://peps.python.org/pep-0723/) 内联声明了依赖（`pyyaml`、`zhipuai`），用 `uv run` 直接运行脚本时会自动安装。

> 需要 [uv](https://docs.astral.sh/uv/)：`curl -LsSf https://astral.sh/uv/install.sh | sh`

## 配置 API Key

去 [open.bigmodel.cn](https://open.bigmodel.cn/) 注册 → 控制台生成 API Key，设为环境变量：

```bash
export ZHIPU_API_KEY="你的key"
```

## 用法

> ⚠️ 用 `uv run tools/gen_art.py ...`（直接运行脚本），**不要**写 `uv run python tools/gen_art.py`——后者不会触发 PEP 723 自动装依赖。

```bash
# 1. 预览：不调 API，只看会生成什么
uv run tools/gen_art.py dry-run
uv run tools/gen_art.py dry-run --category bonds

# 2. 生成（默认跳过已存在的文件）
uv run tools/gen_art.py gen                      # 全部
uv run tools/gen_art.py gen --category bonds     # 只生成羁绊卡面
uv run tools/gen_art.py gen --id bond_zhutian_emperor_cauldron  # 只生成一张
uv run tools/gen_art.py gen --force              # 强制覆盖已有

# 3. 精修后替换：用 Seedream/GLM-Image 精修过的图替换 CogView 草图
uv run tools/gen_art.py sync --id bond_zhutian_emperor_cauldron --ref ~/downloads/refined.png
```

## 输出

图片入库到 `client/src/assets/{category}/{filename}`，分类即目录：

```
client/src/assets/
├── bonds/       羁绊卡面（24 张）
├── debuffs/     Boss debuff 图标（17 张）
├── skills/      技能词条图标（15 张）
├── enemies/     敌人 + Boss 立绘（8 张）
├── characters/  英雄立绘（1 张）
├── effects/     特效贴图（8 张）
└── bg/          场景背景（3 张）
```

## 推荐工作流

1. **先跑一张试风格**：`gen --id hero_sword_cultivator`，看画风满不满意
2. **定风格锚图**：满意后，这张就是全项目风格参考
3. **批量出草图**：`gen --category skills`（图标类最适合 CogView 批量）
4. **精修重点素材**：把羁绊卡面/Boss 的草图拿去 Seedream 精修，再用 `sync` 替换回来

## 调整 prompt

编辑 `art_prompts.yaml`，加/改 `items`。每条只需写正文，`style_prefix` 和分类级 `style_suffix` 会自动拼接。

## 限流说明

- CogView-3-Flash 免费但有速率限制，脚本默认每次调用间隔 1 秒（`RATE_LIMIT_SEC`）
- 失败自动重试 3 次，指数退避（4s → 8s → 16s）
- 全部 76 张约需 2-3 分钟跑完
