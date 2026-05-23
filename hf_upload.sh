#!/bin/bash
# ============================================================
#  HuggingFace Model Uploader — автоматический пуш моделей
#  Использование: отредактируй переменные ниже и запусти
# ============================================================

# ─── НАСТРОЙКИ (отредактируй под себя) ───────────────────────
HF_USER="USERNAME"                   # ← вставь свой USERNAME
HF_TOKEN=""                          # ← вставь свой HF token (Settings → Access Tokens)
REPO_NAME="your-model"  # ← имя репо на HuggingFace
MODEL_PATH="/home/local/path"  # ← откуда копировать файлы
COMMIT_MSG="Upload full model"       # ← сообщение коммита
WORK_DIR="$HOME/Desktop"             # ← куда клонировать репо
SIZE_LIMIT_MB=10                     # ← порог для LFS (HF не пускает >10MB)
# ──────────────────────────────────────────────────────────────

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ─── Проверка токена ─────────────────────────────────────────
if [[ -z "$HF_TOKEN" ]]; then
    echo -e "${YELLOW}HF_TOKEN не задан в скрипте.${NC}"
    read -sp "Введи HuggingFace token: " HF_TOKEN
    echo
fi
[[ -z "$HF_TOKEN" ]] && error "Токен не может быть пустым"

# ─── URL с токеном (без ввода логина/пароля) ─────────────────
REPO_URL="https://${HF_USER}:${HF_TOKEN}@huggingface.co/${HF_USER}/${REPO_NAME}"

# ─── Проверка исходных файлов ────────────────────────────────
[[ ! -d "$MODEL_PATH" ]] && error "Путь к модели не найден: $MODEL_PATH"

cd "$WORK_DIR"

# ─── Клонирование (или использование существующего) ──────────
if [[ -d "$REPO_NAME" ]]; then
    warn "Папка $REPO_NAME уже существует — используем её"
    cd "$REPO_NAME"
    git remote set-url origin "$REPO_URL"
    git pull --rebase origin main || true
else
    info "Клонирую репозиторий..."
    git clone "$REPO_URL"
    cd "$REPO_NAME"
fi

# ─── Git LFS ─────────────────────────────────────────────────
git lfs install
info "Git LFS инициализирован"

# ─── Копирование файлов модели ───────────────────────────────
info "Копирую файлы из $MODEL_PATH ..."
cp -rv "$MODEL_PATH"/* .

# ─── Автоматический LFS tracking для больших файлов ──────────
info "Ищу файлы > ${SIZE_LIMIT_MB}MB для LFS tracking..."
TRACKED=0
while IFS= read -r -d '' bigfile; do
    relpath="${bigfile#./}"
    ext="${relpath##*.}"

    # Проверяем, не трекается ли уже этот паттерн
    if git lfs track | grep -qF "*.${ext}"; then
        : # уже трекается по расширению
    else
        # Трекаем конкретный файл
        git lfs track "$relpath"
        info "  LFS tracking: $relpath"
        ((TRACKED++))
    fi
done < <(find . -maxdepth 1 -type f -size +${SIZE_LIMIT_MB}M -not -path './.git/*' -print0)

# Всегда трекаем safetensors и bin на всякий случай
for pattern in "*.safetensors" "*.bin" "*.gguf"; do
    if ! git lfs track | grep -qF "$pattern"; then
        git lfs track "$pattern"
        info "  LFS tracking (паттерн): $pattern"
    fi
done

if [[ $TRACKED -gt 0 ]]; then
    info "Добавлено $TRACKED файлов в LFS tracking"
fi

# ─── Включение largefiles ────────────────────────────────────
huggingface-cli lfs-enable-largefiles . 2>/dev/null || \
    hf lfs-enable-largefiles . 2>/dev/null || \
    warn "lfs-enable-largefiles не найден (может быть не критично)"

# ─── Коммит и пуш ───────────────────────────────────────────
git add .
git commit -m "$COMMIT_MSG" || warn "Нечего коммитить (файлы не изменились?)"

info "Пушу в HuggingFace... (это может занять время)"
git push --force

info "Готово! 🎉"
echo -e "${GREEN}Модель загружена:${NC} https://huggingface.co/${HF_USER}/${REPO_NAME}"
