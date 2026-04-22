#!/usr/bin/env python3
"""
精灵图/头像右边缘帧泄漏清理工具

AI 生成的精灵图（spritesheet）帧与帧之间常有像素泄漏，
导致渲染第 0 帧时右侧出现第 1 帧的残影。本脚本统一清理。

用法:
  # 清理单张精灵图（3帧横排，每帧右侧清15列）
  python3 tools/fix_sprite_bleed.py assets/image/xxx_sprite.png --cols 3 --clear 15

  # 清理单张头像（单帧，右侧清15列）
  python3 tools/fix_sprite_bleed.py assets/image/avatars/avatar_xxx.png --clear 15

  # 深度泄漏（如暗影君主，清31列）
  python3 tools/fix_sprite_bleed.py assets/image/shadow_lord_spritesheet.png --cols 3 --clear 31

  # 角色内容延伸到边缘的（如蝙蝠），不清像素，改为扩展画布加透明边距
  python3 tools/fix_sprite_bleed.py assets/image/avatars/avatar_bat_m.png --pad 10

  # 组合：先清再加边距（如暗影君主头像）
  python3 tools/fix_sprite_bleed.py assets/image/avatars/avatar_leader.png --clear 31 --pad 15

  # 批量处理所有精灵图（默认15列）
  python3 tools/fix_sprite_bleed.py assets/image/*_sprite*.png --cols 3 --clear 15

  # 批量处理所有头像（默认15列）
  python3 tools/fix_sprite_bleed.py assets/image/avatars/avatar_*.png --clear 15

  # 干跑模式（只分析不修改）
  python3 tools/fix_sprite_bleed.py assets/image/xxx_sprite.png --cols 3 --dry-run

选项:
  --cols N      精灵图横排帧数（默认1=单帧头像）
  --clear N     每帧右侧清除的列数（默认15）
  --pad N       右侧扩展透明边距像素数（可与 --clear 组合）
  --dry-run     只分析泄漏情况，不修改文件
  --skip LIST   跳过的文件名关键词，逗号分隔（如 --skip bat_m,emerald）
"""

import argparse
import sys
import os
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("错误: 需要 Pillow 库。请运行: pip install Pillow")
    sys.exit(1)


def analyze_bleed(img, frame_width, frame_idx, max_scan=40):
    """分析某帧右边缘的泄漏情况，返回 {col_offset: non_transparent_count}"""
    w, h = img.size
    results = {}
    for offset in range(1, min(max_scan + 1, frame_width)):
        col = (frame_idx + 1) * frame_width - offset
        if col < 0 or col >= w:
            continue
        count = 0
        for y in range(h):
            _, _, _, a = img.getpixel((col, y))
            if a > 0:
                count += 1
        results[offset] = count
        # 如果连续3列都是0，说明泄漏区域已结束
        if offset >= 3 and all(results.get(offset - i, 0) == 0 for i in range(3)):
            break
    return results


def clear_frame_edges(img, cols, clear_count):
    """清除每帧右侧 clear_count 列像素为透明"""
    w, h = img.size
    frame_width = w // cols
    total_cleared = 0

    for frame in range(cols):
        frame_right = (frame + 1) * frame_width
        for col_offset in range(1, clear_count + 1):
            col = frame_right - col_offset
            if col < 0 or col >= w:
                continue
            for y in range(h):
                _, _, _, a = img.getpixel((col, y))
                if a > 0:
                    img.putpixel((col, y), (0, 0, 0, 0))
                    total_cleared += 1

    return total_cleared


def expand_canvas(img, pad_right):
    """右侧扩展画布，填充透明像素"""
    w, h = img.size
    new_img = Image.new("RGBA", (w + pad_right, h), (0, 0, 0, 0))
    new_img.paste(img, (0, 0))
    return new_img


def process_file(filepath, cols, clear_count, pad, dry_run):
    """处理单个文件"""
    img = Image.open(filepath).convert("RGBA")
    w, h = img.size
    frame_width = w // cols
    filename = os.path.basename(filepath)

    print(f"\n{'='*60}")
    print(f"文件: {filepath}")
    print(f"尺寸: {w}x{h}  帧数: {cols}  帧宽: {frame_width}")

    # 分析泄漏
    for frame in range(cols):
        bleed = analyze_bleed(img, frame_width, frame)
        bleed_cols = sum(1 for v in bleed.values() if v > 0)
        bleed_pixels = sum(bleed.values())
        if bleed_pixels > 0:
            print(f"  帧{frame} 右边缘: {bleed_cols}列有泄漏, 共{bleed_pixels}个像素")
            # 显示详细分布
            details = []
            for offset in sorted(bleed.keys()):
                if bleed[offset] > 0:
                    details.append(f"    col-{offset}: {bleed[offset]}px")
            if len(details) <= 10:
                print("\n".join(details))
            else:
                print("\n".join(details[:5]))
                print(f"    ... 省略 {len(details)-10} 行 ...")
                print("\n".join(details[-5:]))
        else:
            print(f"  帧{frame} 右边缘: 干净")

    if dry_run:
        print(f"  [干跑模式] 不修改文件")
        return

    # 清除像素
    if clear_count > 0:
        cleared = clear_frame_edges(img, cols, clear_count)
        print(f"  已清除: {cleared}个像素 ({cols}帧 x {clear_count}列)")

    # 扩展画布
    if pad > 0:
        img = expand_canvas(img, pad)
        print(f"  已扩展画布: {w}x{h} → {img.size[0]}x{img.size[1]} (+{pad}px右边距)")

    img.save(filepath)
    print(f"  已保存: {filepath}")


def main():
    parser = argparse.ArgumentParser(
        description="精灵图/头像右边缘帧泄漏清理工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("files", nargs="+", help="要处理的PNG文件路径")
    parser.add_argument("--cols", type=int, default=1, help="精灵图横排帧数（默认1=单帧头像）")
    parser.add_argument("--clear", type=int, default=15, help="每帧右侧清除的列数（默认15）")
    parser.add_argument("--pad", type=int, default=0, help="右侧扩展透明边距（默认0）")
    parser.add_argument("--dry-run", action="store_true", help="只分析不修改")
    parser.add_argument("--skip", type=str, default="", help="跳过包含这些关键词的文件（逗号分隔）")

    args = parser.parse_args()
    skip_keywords = [k.strip() for k in args.skip.split(",") if k.strip()]

    processed = 0
    skipped = 0

    for filepath in args.files:
        if not os.path.isfile(filepath):
            print(f"跳过（不存在）: {filepath}")
            skipped += 1
            continue

        filename = os.path.basename(filepath)
        if any(kw in filename for kw in skip_keywords):
            print(f"跳过（匹配skip）: {filepath}")
            skipped += 1
            continue

        try:
            process_file(filepath, args.cols, args.clear, args.pad, args.dry_run)
            processed += 1
        except Exception as e:
            print(f"错误处理 {filepath}: {e}")
            skipped += 1

    print(f"\n{'='*60}")
    action = "分析" if args.dry_run else "处理"
    print(f"完成: {action}了 {processed} 个文件, 跳过 {skipped} 个")


if __name__ == "__main__":
    main()
