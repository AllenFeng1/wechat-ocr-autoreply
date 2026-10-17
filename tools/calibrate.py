# -*- coding: utf-8 -*-
"""用真实微信截图校准 OCRPipeline.swift 的颜色分类阈值。

对应代码：ios/WeChatOCRAutoReply/Shared/OCRPipeline.swift
  classify():  绿底 → me（g > r+40 && g > b+40）
              非绿且对比度 >= 150 → her
              否则 gray
  sampleBox(): 框内量化直方图（32级/通道）取众数桶当底色，
              maxContrast = 各桶均值亮度与众桶亮度的最大差
用法：python tools/calibrate.py <截图目录>
"""
import sys, re
from pathlib import Path
import numpy as np
from PIL import Image

def lum(rgb):
    return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]

def analyze(path: Path):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.int32)
    h, w, _ = a.shape
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    L = 0.299 * r + 0.587 * g + 0.114 * b

    # --- 1. 微信绿（me 阈值：g > r+40 && g > b+40）---
    green = (g > r + 40) & (g > b + 40)
    # --- 2. 白/浅气泡（her 的底色，排除状态栏纯白）---
    white = (r > 225) & (g > 225) & (b > 225)
    # --- 3. 深色壁纸 ---
    dark = L < 80

    print(f"\n===== {path.name}  {w}x{h} =====")
    if green.sum() > 200:
        ys = np.where(green.any(axis=1))[0]
        gr = a[green].mean(axis=0)
        print(f"[绿=me]  像素 {green.sum():>8}  RGB均值({gr[0]:.0f},{gr[1]:.0f},{gr[2]:.0f})"
              f"  g-r={gr[1]-gr[0]:.0f} g-b={gr[1]-gr[2]:.0f}"
              f"  y范围 {ys.min()/h:.2f}-{ys.max()/h:.2f}")
    else:
        print(f"[绿=me]  像素 {green.sum():>8}  (无绿气泡)")

    if white.sum() > 200:
        # 分区域统计：消息区 / 输入栏 / 键盘区（白像素在各区的占比完全不同）
        for label, y0f, y1f in [("消息区", 0.05, 0.82), ("输入栏", 0.82, 0.875), ("键盘区", 0.875, 1.0)]:
            y0, y1 = int(h * y0f), int(h * y1f)
            wm = white[y0:y1]
            if wm.sum() > 200:
                wr = a[y0:y1][wm].mean(axis=0)
                mean_l = lum((a[y0:y1] * wm[..., None]).sum(axis=(0, 1)) / wm.sum())
                dark_text = wm & (L[y0:y1] < mean_l - 60)
                extra = ""
                if dark_text.sum() > 50:
                    tr = a[y0:y1][dark_text].mean(axis=0)
                    c = abs(lum(wr) - lum(tr))
                    extra = (f"  暗字RGB({tr[0]:.0f},{tr[1]:.0f},{tr[2]:.0f})"
                             f" 对比度≈{c:.0f}→{'her ✓' if c >= 150 else 'gray ✗'}")
                print(f"[白{label}] 像素 {wm.sum():>7}  底色RGB({wr[0]:.0f},{wr[1]:.0f},{wr[2]:.0f}){extra}")
    else:
        print(f"[白=her底色] 像素 {white.sum():>8}  (无白气泡)")

    if dark.sum() > (h * w * 0.2):
        dr = a[dark].mean(axis=0)
        print(f"[深色壁纸] 占比 {dark.sum()/(h*w)*100:.0f}%  均值RGB({dr[0]:.0f},{dr[1]:.0f},{dr[2]:.0f})"
              f"  亮度 {lum(dr):.0f}")
        # 壁纸上的浅色字（系统提示灰字）：亮度介于壁纸和纯白之间
        pale_on_dark = (~dark) & (~white) & (L > 90) & (L < 210)
        if pale_on_dark.sum() > 50:
            sr = a[pale_on_dark].mean(axis=0)
            c = abs(lum(sr) - lum(dr))
            print(f"        壁纸上浅色字(系统提示?) RGB({sr[0]:.0f},{sr[1]:.0f},{sr[2]:.0f})"
                  f"  对比度≈{c:.0f}  (阈值150 → {'会被判 her ⚠' if c >= 150 else 'gray ✓'})")

    # --- 4. 逐行带：白区里的暗字对比度（气泡文字 vs 键盘字母 vs 输入栏文字）---
    print("[行带] y%  白px   暗字px  暗字RGB          对比度(阈值150)")
    for i in range(4, 100, 4):
        y0, y1 = int(h * i / 100), int(h * (i + 4) / 100)
        wm = white[y0:y1]
        if wm.sum() < 800:
            continue
        wr = a[y0:y1][wm].mean(axis=0)
        band_l = 0.299 * a[y0:y1, :, 0] + 0.587 * a[y0:y1, :, 1] + 0.114 * a[y0:y1, :, 2]
        dark_text = (band_l < lum(wr) - 60) & (band_l > 20)
        n = int(dark_text.sum())
        if n > 100:
            tr = a[y0:y1][dark_text].mean(axis=0)
            c = abs(lum(wr) - lum(tr))
            print(f"       {i:>3}% {wm.sum():>7} {n:>8}  ({tr[0]:.0f},{tr[1]:.0f},{tr[2]:.0f})"
                  f"      ≈{c:.0f} → {'her' if c >= 150 else 'gray'}")

def main():
    d = Path(sys.argv[1])
    files = sorted(d.glob("*.jpg"))
    # 只跑聊天页/列表页；红包详情页等非聊天界面跳过
    for f in files:
        analyze(f)

if __name__ == "__main__":
    main()
