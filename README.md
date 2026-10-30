# Собственный загрузчик ОС (лабораторная)

Многоступенчатый BIOS/MBR-загрузчик:

1. **Space Invaders** ~1 минута  
2. **Пароль** (настраивается `tools/setpass.py`)  
3. **Меню ОС** → chainload выбранной системы  

Подробный запуск в VirtualBox: **[INSTRUCTION.md](INSTRUCTION.md)**.

```powershell
python scripts\build.py
python tools\setpass.py -p secret
```

Пароль по умолчанию: `secret`.
