#!/usr/bin/env python3
"""Запись пароля загрузчика в сектор 65 образа диска (без прав администратора)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

PASSWORD_LBA = 65
SECTOR = 512
PASSWORD_MAX = 16


def write_password(image: Path, password: str) -> None:
    if not password:
        raise SystemExit("Пароль не может быть пустым")
    if len(password) > PASSWORD_MAX:
        raise SystemExit(f"Пароль длиннее {PASSWORD_MAX} символов")
    if any(ord(c) < 32 or ord(c) > 126 for c in password):
        raise SystemExit("Пароль должен содержать только ASCII-символы")

    data = image.read_bytes()
    need = (PASSWORD_LBA + 1) * SECTOR
    if len(data) < need:
        data = data + b"\x00" * (need - len(data))

    sector = password.encode("ascii") + b"\x00" * (SECTOR - len(password))
    offset = PASSWORD_LBA * SECTOR
    out = bytearray(data)
    out[offset : offset + SECTOR] = sector
    image.write_bytes(out)
    print(f"OK: пароль записан в {image} (LBA {PASSWORD_LBA})")


def read_password(image: Path) -> None:
    data = image.read_bytes()
    offset = PASSWORD_LBA * SECTOR
    if len(data) < offset + SECTOR:
        raise SystemExit("Образ слишком короткий — сначала соберите disk.img")
    raw = data[offset : offset + PASSWORD_MAX + 1]
    pwd = raw.split(b"\x00", 1)[0]
    if not pwd or pwd[0] == 0xFF:
        print("(пароль не задан, загрузчик использует default: secret)")
    else:
        print("Текущий пароль:", pwd.decode("ascii", errors="replace"))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Настройка пароля доступа загрузчика"
    )
    parser.add_argument(
        "-i",
        "--image",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "build" / "disk.img",
        help="Путь к disk.img",
    )
    parser.add_argument("-p", "--password", help="Новый пароль (до 16 символов)")
    parser.add_argument(
        "--show",
        action="store_true",
        help="Показать текущий пароль из образа",
    )
    args = parser.parse_args()

    if not args.image.exists() and not args.password:
        raise SystemExit(f"Файл не найден: {args.image}. Сначала запустите build.py")

    if args.show:
        read_password(args.image)
        return

    if not args.password:
        args.password = input("Новый пароль: ").strip()

    write_password(args.image, args.password)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)
