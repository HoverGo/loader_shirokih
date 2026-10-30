#!/usr/bin/env python3
"""Сборка загрузчика и образа disk.img без прав администратора."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
BUILD = ROOT / "build"
TOOLS = ROOT / "tools"
NASM_DIR = TOOLS / "nasm"

# Раскладка диска (LBA)
STAGE2_LBA = 1
PASSWORD_LBA = 65
OS1_LBA = 100
OS2_LBA = 200
OS3_LBA = 300
DISK_SECTORS = 512  # ~256 КБ — достаточно для демо
SECTOR = 512

NASM_ZIP_URL = (
    "https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/win64/nasm-2.16.03-win64.zip"
)


def find_nasm() -> Path:
    which = shutil.which("nasm")
    if which:
        return Path(which)

    for candidate in NASM_DIR.rglob("nasm.exe"):
        return candidate

    print("NASM не найден — скачиваю portable-сборку в tools/nasm ...")
    NASM_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = TOOLS / "nasm.zip"
    try:
        urllib.request.urlretrieve(NASM_ZIP_URL, zip_path)
    except Exception as exc:
        raise SystemExit(
            "Не удалось скачать NASM автоматически.\n"
            f"Скачайте вручную: {NASM_ZIP_URL}\n"
            f"Распакуйте nasm.exe в {NASM_DIR}\n"
            f"Ошибка: {exc}"
        ) from exc

    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(NASM_DIR)
    zip_path.unlink(missing_ok=True)

    for candidate in NASM_DIR.rglob("nasm.exe"):
        return candidate

    raise SystemExit("nasm.exe не найден после распаковки")


def run_nasm(nasm: Path, source: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    cmd = [str(nasm), "-f", "bin", "-o", str(output), str(source)]
    print(">", " ".join(cmd))
    subprocess.check_call(cmd)


def put_file(img: bytearray, lba: int, path: Path) -> None:
    data = path.read_bytes()
    offset = lba * SECTOR
    end = offset + len(data)
    if end > len(img):
        raise SystemExit(f"{path.name} не помещается в образ (LBA {lba})")
    img[offset:end] = data


def write_default_password(img: bytearray, password: str = "secret") -> None:
    raw = password.encode("ascii") + b"\x00" * (SECTOR - len(password))
    offset = PASSWORD_LBA * SECTOR
    img[offset : offset + SECTOR] = raw


def build_image() -> Path:
    BUILD.mkdir(parents=True, exist_ok=True)
    nasm = find_nasm()
    print(f"NASM: {nasm}")

    artifacts = {
        "stage1.bin": SRC / "stage1.asm",
        "stage2.bin": SRC / "stage2.asm",
        "os_alpha.bin": SRC / "os_alpha.asm",
        "os_beta.bin": SRC / "os_beta.asm",
        "os_gamma.bin": SRC / "os_gamma.asm",
    }
    bins = {}
    for name, src in artifacts.items():
        out = BUILD / name
        run_nasm(nasm, src, out)
        bins[name] = out
        print(f"  {name}: {out.stat().st_size} bytes")

    stage1 = bins["stage1.bin"].read_bytes()
    if len(stage1) != 512 or stage1[-2:] != b"\x55\xaa":
        raise SystemExit("stage1.bin должен быть ровно 512 байт с сигнатурой AA55")

    stage2 = bins["stage2.bin"].read_bytes()
    if len(stage2) != 32768:
        raise SystemExit(f"stage2.bin должен быть 32768 байт, сейчас {len(stage2)}")

    img = bytearray(DISK_SECTORS * SECTOR)
    put_file(img, 0, bins["stage1.bin"])
    put_file(img, STAGE2_LBA, bins["stage2.bin"])
    put_file(img, OS1_LBA, bins["os_alpha.bin"])
    put_file(img, OS2_LBA, bins["os_beta.bin"])
    put_file(img, OS3_LBA, bins["os_gamma.bin"])
    write_default_password(img, "secret")

    # Минимальная MBR partition table не обязательна для нашего LBA-загрузчика,
    # но VirtualBox иногда спокойнее с валидной сигнатурой (уже есть AA55).

    out_img = BUILD / "disk.img"
    out_img.write_bytes(img)
    print(f"\nОбраз готов: {out_img} ({len(img)} байт)")
    return out_img


def try_convert_vdi(img: Path) -> None:
    vbox = shutil.which("VBoxManage")
    if not vbox:
        # типичные пути без добавления в PATH
        candidates = [
            Path(os.environ.get("PROGRAMFILES", r"C:\Program Files"))
            / "Oracle"
            / "VirtualBox"
            / "VBoxManage.exe",
            Path(os.environ.get("PROGRAMFILES(X86)", r"C:\Program Files (x86)"))
            / "Oracle"
            / "VirtualBox"
            / "VBoxManage.exe",
        ]
        for c in candidates:
            if c.exists():
                vbox = str(c)
                break
    if not vbox:
        print("VBoxManage не найден — пропуск конвертации в VDI (см. инструкцию).")
        return

    vdi = BUILD / "disk.vdi"
    if vdi.exists():
        vdi.unlink()
    cmd = [
        vbox,
        "convertfromraw",
        str(img),
        str(vdi),
        "--format",
        "VDI",
    ]
    print(">", " ".join(cmd))
    subprocess.check_call(cmd)
    print(f"VDI готов: {vdi}")


def main() -> None:
    img = build_image()
    try_convert_vdi(img)
    print("\nПароль по умолчанию: secret")
    print("Смена пароля:  python tools/setpass.py -p mypass")
    print("Дальше: см. INSTRUCTION.md")


if __name__ == "__main__":
    main()
