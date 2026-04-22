#!/usr/bin/env python3
"""
crop_avatars.py - 从 spritesheet 自动裁切第一帧生成英雄头像

用法:
    python3 tools/crop_avatars.py          # 只处理缺失的头像
    python3 tools/crop_avatars.py --force  # 强制重新生成所有头像

流程:
    1. 解析 scripts/Game/Renderer_Utils.lua 中的 SpriteSheet.Register 调用
    2. 对每个英雄, 从 spritesheet 裁切第一帧 (frame 0)
    3. 保存为 assets/image/avatars/avatar_{icon}.png

规范:
    - spritesheet 是横排等宽帧, 帧宽 = 图片总宽 / cols
    - 第一帧 (idle) 位于最左侧, 裁切区域 = (0, 0, frameW, height)
    - 输出为正方形 PNG, 保留透明通道
"""

import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: 需要 Pillow 库, 请运行: pip install Pillow")
    sys.exit(1)

# 路径配置
WORKSPACE = Path(__file__).resolve().parent.parent
RENDERER_UTILS = WORKSPACE / "scripts" / "Game" / "Renderer_Utils.lua"
ASSETS_DIR = WORKSPACE / "assets"
AVATARS_DIR = ASSETS_DIR / "image" / "avatars"

# 不需要生成头像的 spritesheet (BOSS 等非英雄)
SKIP_ICONS = {"world_boss", "emerald_boss"}


def parse_spritesheets(lua_path: Path) -> list[dict]:
    """解析 Renderer_Utils.lua 中的 SpriteSheet.Register 调用"""
    text = lua_path.read_text(encoding="utf-8")

    # 匹配: SpriteSheet.Register("name", { path = "...", cols = N ... })
    pattern = re.compile(
        r'SpriteSheet\.Register\(\s*"(\w+)"\s*,\s*\{[^}]*'
        r'path\s*=\s*"([^"]+)"[^}]*'
        r'cols\s*=\s*(\d+)',
        re.DOTALL,
    )

    results = []
    for m in pattern.finditer(text):
        icon = m.group(1)
        path = m.group(2)
        cols = int(m.group(3))
        if icon not in SKIP_ICONS:
            results.append({"icon": icon, "path": path, "cols": cols})

    return results


def crop_first_frame(sprite_path: Path, cols: int) -> Image.Image:
    """从 spritesheet 裁切第一帧并返回正方形图片"""
    img = Image.open(sprite_path)
    frame_w = img.width // cols
    frame_h = img.height

    # 裁切第一帧
    frame = img.crop((0, 0, frame_w, frame_h))
    return frame


def main():
    force = "--force" in sys.argv

    if not RENDERER_UTILS.exists():
        print(f"ERROR: 找不到 {RENDERER_UTILS}")
        sys.exit(1)

    AVATARS_DIR.mkdir(parents=True, exist_ok=True)

    sheets = parse_spritesheets(RENDERER_UTILS)
    print(f"解析到 {len(sheets)} 个英雄 spritesheet")

    created = 0
    skipped = 0
    errors = 0

    for s in sheets:
        icon = s["icon"]
        avatar_path = AVATARS_DIR / f"avatar_{icon}.png"

        if avatar_path.exists() and not force:
            skipped += 1
            continue

        sprite_path = ASSETS_DIR / s["path"]
        if not sprite_path.exists():
            print(f"  WARN: spritesheet 不存在, 跳过 {icon}: {sprite_path}")
            errors += 1
            continue

        try:
            frame = crop_first_frame(sprite_path, s["cols"])
            frame.save(avatar_path, "PNG")
            action = "覆盖" if avatar_path.exists() else "生成"
            print(f"  OK: {action} avatar_{icon}.png ({frame.width}x{frame.height})")
            created += 1
        except Exception as e:
            print(f"  ERROR: {icon} - {e}")
            errors += 1

    print(f"\n完成: 生成 {created}, 跳过 {skipped}, 错误 {errors}")


if __name__ == "__main__":
    main()
