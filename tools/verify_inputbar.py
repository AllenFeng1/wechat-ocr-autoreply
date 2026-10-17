# -*- coding: utf-8 -*-
"""验证"输入栏通栏白条检测"算法：微信输入栏是贯穿全宽的白条，
气泡左右有壁纸间隙（不贴边），键盘按键行有深色缝隙。
算法：扫 y 70%-98% 每行，近白像素占比 > 80% 且首尾 5px 贴白 → 输入栏顶。
对 3 张真实聊天图（有/无键盘）跑一遍，看检出的 y 是否合理。
"""
from pathlib import Path
import numpy as np
from PIL import Image

D = Path(r"C:\Users\Administrator\Desktop\新建文件夹 (5)")

for name in ["21928ee7789713152c9041f898c9cced.jpg",  # 闲愁·键盘弹出
             "69622151eab6101280ddd5999fe870ea.jpg",  # 闲愁·无键盘
             "6aef46f562a358483b94a6303ca573e6.jpg"]: # Jks·无键盘
    im = Image.open(D / name).convert("RGB")
    a = np.asarray(im).astype(np.int32)
    h, w, _ = a.shape
    near_white = (a[..., 0] > 235) & (a[..., 1] > 235) & (a[..., 2] > 235)
    print(f"\n== {name} ==")
    hits = []
    for i in range(70, 99):
        y0 = int(h * i / 100)
        row = near_white[y0]
        ratio = row.mean()
        edge = row[:6].mean() > 0.8 and row[-6:].mean() > 0.8
        mark = " ← 输入栏顶!" if (ratio > 0.8 and edge) else ""
        if ratio > 0.5 or mark:
            print(f"  y {i}%  近白占比 {ratio*100:5.1f}%  贴边={'是' if edge else '否'}{mark}")
        if ratio > 0.8 and edge and not hits:
            hits.append(i)
    print(f"  → 检测结果：输入栏顶 y ≈ {hits[0]/100 if hits else '未检出'}")
