# Инструкция: сборка и тест загрузчика в VirtualBox

Загрузчик: **Space Invaders (1 мин) → пароль → меню ОС → загрузка выбранной ОС**.

На **хосте** (учебная машина) админ не нужен: сборка и смена пароля идут из пользовательской папки.  
Права администратора есть **внутри виртуалки** — ими можно пользоваться для доп. экспериментов (см. §5), но для сдачи сценария достаточно подключить готовый `disk.vdi` и загрузиться с него.

---

## Что получится

| Этап | Поведение |
|------|-----------|
| 1 | Игра Space Invaders ~60 секунд (A/D или ←/→, пробел — выстрел) |
| 2 | Запрос пароля (по умолчанию `secret`) |
| 3 | Меню: Demo OS Alpha / Beta / Gamma |
| 4 | Chainload выбранной «ОС» (заглушка с баннером) |

Пароль меняется утилитой `tools/setpass.py` **на хосте**, без админа.

---

## 0. Что нужно на хосте

- **Python 3** (уже есть на большинстве учебных ПК)
- **VirtualBox** (пользовательская установка)
- Интернет один раз — скрипт сам скачает portable **NASM** в `tools/nasm` (без установки в систему)

---

## 1. Сборка образа

В PowerShell из папки проекта:

```powershell
cd c:\stud\5kurs\1semestr\shirokih\loader
python scripts\build.py
```

Скрипт:

1. при необходимости скачает NASM;
2. соберёт `stage1`, `stage2`, три демо-ОС;
3. соберёт `build\disk.img`;
4. если найден `VBoxManage` — конвертирует в `build\disk.vdi`.

### Смена пароля (на хосте)

```powershell
python tools\setpass.py -p mypass
python tools\setpass.py --show
```

Пароль пишется в **сектор LBA 65** образа. После смены пароля заново конвертируйте VDI (или правьте уже подключённый raw — проще пересобрать VDI):

```powershell
python scripts\build.py
python tools\setpass.py -p mypass
# если VDI не обновился автоматически:
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" convertfromraw build\disk.img build\disk.vdi --format VDI
```

Если файл `disk.vdi` уже существует и занят ВМ — выключите ВМ и удалите старый VDI перед конвертацией (скрипт сборки удаляет его сам).

---

## 2. Создание виртуальной машины в VirtualBox

1. **Создать** → имя, например `CustomLoader`.
2. Тип: **Other**, версия: **Other/Unknown (64-bit)** или **32-bit** — не важно, BIOS будет грузить наш MBR.
3. Память: **64–128 МБ** достаточно.
4. Жёсткий диск: **«Использовать существующий виртуальный жёсткий диск»** → укажите  
   `c:\stud\5kurs\1semestr\shirokih\loader\build\disk.vdi`  
   (если VDI нет — см. шаг конвертации выше).

### Важно: только BIOS (не EFI)

**Настройки ВМ → System → Motherboard:**

- снять галку **Enable EFI** (если есть);
- Chipset: PIIX3 / ICH9 — любой;
- Boot Order: **Hard Disk** первым.

### Рекомендуется

- **Display → Graphics Controller:** VBoxVGA или VMSVGA  
- Отключить Floppy в Boot Order, чтобы не ждать лишнего.

---

## 3. Запуск и проверка сценария

1. Запустите ВМ.
2. Должно появиться сообщение Stage1 `Loader: reading stage2...`, затем игра.
3. Играйте **~1 минуту** (таймер сверху). Управление:
   - `A` / `D` или стрелки — влево/вправо;
   - `Пробел` — выстрел.
4. После таймера — экран пароля. Введите пароль (по умолчанию `secret`), Enter.
5. Выберите `1`, `2` или `3` — должна загрузиться соответствующая Demo OS с баннером.

Если после пароля меню есть, а баннер ОС появился — **лабораторная по сценарию выполнена**.

---

## 4. Если нет VDI (только disk.img)

На хосте в PowerShell (путь к VBoxManage поправьте при необходимости):

```powershell
cd c:\stud\5kurs\1semestr\shirokih\loader
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" convertfromraw `
  "$PWD\build\disk.img" "$PWD\build\disk.vdi" --format VDI
```

Права администратора **на хосте не нужны**.

Альтернатива: в мастере создания ВМ выбрать «не подключать диск», потом  
**Настройки → Storage → Controller: SATA → Add Hard Disk → Choose existing disk → disk.vdi**.

---

## 5. Тест на уже существующей Ubuntu-ВМ (рекомендуется)

Ubuntu **не затираем**. Подключаем второй диск с загрузчиком и один раз грузимся с него.

### 5.1. На Windows-хосте

```powershell
cd c:\stud\5kurs\1semestr\shirokih\loader
python scripts\build.py
python tools\setpass.py -p secret
```

Конвертация в VDI (если `build\disk.vdi` ещё нет):

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" convertfromraw `
  "$PWD\build\disk.img" "$PWD\build\disk.vdi" --format VDI
```

### 5.2. Подключить диск к Ubuntu-ВМ

1. **Полностью выключите** Ubuntu (не Sleep / не Save State).
2. VirtualBox → ваша Ubuntu → **Настройки → Носители (Storage)**.
3. Контроллер SATA (или IDE) → иконка **«Добавить жёсткий диск»**.
4. **Выбрать существующий** → `...\loader\build\disk.vdi`.
5. **Система → Материнская плата**:
   - снять **Enable EFI** (наш загрузчик — BIOS/MBR);
   - в Boot Order можно оставить Hard Disk первым.

### 5.3. Загрузиться с диска загрузчика

**Вариант A (проще):** при старте ВМ нажимайте **F12** (Boot Menu) → выберите **второй** жёсткий диск (часто `SATA-1` / `HDD 1`).

**Вариант B:** Настройки → System → Hard Disk order / поменять порядок контроллеров так, чтобы `disk.vdi` был первым; после теста верните диск Ubuntu первым.

Дальше: игра → пароль `secret` → меню `1/2/3` → баннер Demo OS.

Чтобы снова попасть в Ubuntu: выключить ВМ и грузиться с **первого** (старого) диска.

### 5.4. Альтернатива: записать образ из Ubuntu через `dd`

Если преподаватель хочет увидеть установку «изнутри» с sudo:

1. Сделайте шаги 5.1–5.2, но вторым диском добавьте **новый пустой** VDI на 64–128 МБ (не диск Ubuntu!).
2. Передайте в гостя файл `disk.img` (Shared Folder / Drag&Drop / `scp`).
3. В Ubuntu:

```bash
lsblk                          # найдите ВТОРОЙ диск, например /dev/sdb
# Убедитесь, что это НЕ диск с Ubuntu (/dev/sda обычно система)!
sudo dd if=~/disk.img of=/dev/sdb bs=512 conv=fsync status=progress
```

4. Перезагрузка → F12 → загрузиться с `/dev/sdb`.

**Никогда** не делайте `dd` на диск, где стоит Ubuntu (`/dev/sda`), иначе система пропадёт.

---

## 6. Раскладка диска (для отчёта)

| LBA | Содержимое |
|-----|------------|
| 0 | Stage 1 (MBR, 512 байт) |
| 1–64 | Stage 2 (игра, пароль, меню), 32 КБ |
| 65 | Сектор пароля |
| 100 | Demo OS Alpha |
| 200 | Demo OS Beta |
| 300 | Demo OS Gamma |

---

## 7. Типичные проблемы

| Симптом | Что сделать |
|---------|-------------|
| Чёрный экран | Выключить EFI; Boot Order → Hard Disk |
| `Disk read error` | Пересобрать образ; проверить, что подключён именно наш VDI |
| Неверный пароль | `python tools\setpass.py --show`; помнить: регистр важен |
| VDI «уже существует» | Выключить ВМ, удалить `build\disk.vdi`, снова `python scripts\build.py` |
| NASM не скачался | Скачать zip вручную с nasm.us, положить `nasm.exe` в `tools\nasm\` |

---

## 8. Файлы проекта

```
loader/
  src/stage1.asm      — MBR
  src/stage2.asm      — игра + пароль + меню
  src/os_*.asm        — демо-ОС
  scripts/build.py    — сборка
  tools/setpass.py    — смена пароля
  build/disk.img      — сырой образ
  build/disk.vdi      — для VirtualBox
  INSTRUCTION.md      — эта инструкция
```
