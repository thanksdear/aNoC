#!/usr/bin/env python3
"""
从 axi_lite_slave 模板生成新模块的 UVM 验证框架。

用法：
    python gen_tb.py <新模块名>
    python gen_tb.py apb_slave
    python gen_tb.py --from axi_lite_slave --to apb_slave
"""
import argparse
import os
import shutil

TEMPLATE = "axi_lite_slave"

def replace_in_file(path, src, dst):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        new_content = content.replace(src, dst)
        if new_content != content:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new_content)
    except UnicodeDecodeError:
        pass  # 跳过二进制文件

def rename_tree(root, src, dst):
    """自底向上重命名文件和目录。"""
    for dirpath, dirnames, filenames in os.walk(root, topdown=False):
        for name in filenames:
            old = os.path.join(dirpath, name)
            new = os.path.join(dirpath, name.replace(src, dst))
            if old != new:
                os.rename(old, new)
        # 重命名目录（跳过根目录本身）
        if dirpath != root:
            new_dir = dirpath.replace(src, dst)
            if dirpath != new_dir:
                os.rename(dirpath, new_dir)

def main():
    parser = argparse.ArgumentParser(description="生成 UVM TB 模板")
    parser.add_argument("name", nargs="?", help="新模块名，如 apb_slave")
    parser.add_argument("--from", dest="src", default=TEMPLATE, help="模板名（默认 axi_lite_slave）")
    parser.add_argument("--to",   dest="dst", help="新模块名")
    args = parser.parse_args()

    dst = args.dst or args.name
    if not dst:
        parser.print_help()
        return

    src      = args.src
    base_dir = os.path.dirname(os.path.abspath(__file__))
    src_dir  = os.path.join(base_dir, src)
    dst_dir  = os.path.join(base_dir, dst)

    if not os.path.isdir(src_dir):
        print(f"[错误] 模板目录不存在: {src_dir}")
        return
    if os.path.exists(dst_dir):
        print(f"[错误] 目标目录已存在: {dst_dir}")
        return

    # 1. 复制整个目录树
    shutil.copytree(src_dir, dst_dir)
    print(f"复制: {src_dir} → {dst_dir}")

    # 2. 替换所有文件内容
    for dirpath, _, filenames in os.walk(dst_dir):
        for name in filenames:
            replace_in_file(os.path.join(dirpath, name), src, dst)

    # 3. 重命名文件和目录
    rename_tree(dst_dir, src, dst)

    print(f"完成！'{src}' → '{dst}' 替换完毕")
    print(f"新目录: {dst_dir}")
    print()
    print("接下来只需要修改：")
    print(f"  {dst}/rtl/          ← 换上新的 DUT")
    print(f"  {dst}/tb/env/*_txn.sv    ← 改信号定义")
    print(f"  {dst}/tb/env/*_driver.sv ← 改驱动时序")
    print(f"  {dst}/tb/env/*_monitor.sv← 改采样逻辑")
    print(f"  {dst}/tb/env/*_scoreboard.sv ← 改参考模型")

if __name__ == "__main__":
    main()
