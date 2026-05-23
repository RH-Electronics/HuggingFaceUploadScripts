#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Hugging Face model / GGUF uploader
# Лёша, редактируй только этот верхний блок.
# ============================================================

HF_REPO_ID="HamsterTheRipper/eva-0805-c4ai-command-r-08-2024"

# Можно указать папку модели:
LOCAL_PATH="/home/local/path"

# Или один GGUF-файл, например:
# LOCAL_PATH="/home/your.gguf"

REPO_TYPE="model"
PRIVATE_REPO="true"     # true / false
NUM_WORKERS="8"

# Для одиночного файла: куда положить его в репозитории.
# "." = в корень. Обычно так и надо.
PATH_IN_REPO="."

# ============================================================
# Дальше обычно ничего менять не надо.
# ============================================================

log() {
  printf "\n\033[1;35m%s\033[0m\n" "$*"
}

die() {
  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Не найдена команда '$1'. Установи её и запусти снова."
}

private_flag=()
if [[ "$PRIVATE_REPO" == "true" ]]; then
  private_flag=(--private)
fi

[[ -n "${HF_TOKEN:-}" ]] || die "HF_TOKEN не задан. Сначала выполни:
export HF_TOKEN='hf_твой_токен_сюда'

Лучше не вписывать токен прямо в скрипт, чтобы случайно не запушить его в repo."

[[ -e "$LOCAL_PATH" ]] || die "LOCAL_PATH не существует: $LOCAL_PATH"

need_cmd hf

log "Проверяю Hugging Face CLI..."
hf --help >/dev/null || die "Команда hf есть, но не запускается нормально."

log "Создаю repo, если его ещё нет: $HF_REPO_ID"
hf repos create "$HF_REPO_ID" \
  --repo-type "$REPO_TYPE" \
  --exist-ok \
  --token "$HF_TOKEN" \
  "${private_flag[@]}"

if [[ -d "$LOCAL_PATH" ]]; then
  log "Найдена папка модели. Загружаю через resumable large-folder upload..."
  log "Источник: $LOCAL_PATH"

  hf upload-large-folder "$HF_REPO_ID" "$LOCAL_PATH" \
    --repo-type "$REPO_TYPE" \
    --num-workers "$NUM_WORKERS" \
    --token "$HF_TOKEN" \
    "${private_flag[@]}"

elif [[ -f "$LOCAL_PATH" ]]; then
  log "Найден одиночный файл. Загружаю через hf upload..."
  log "Источник: $LOCAL_PATH"

  filename="$(basename "$LOCAL_PATH")"

  if [[ "$PATH_IN_REPO" == "." || -z "$PATH_IN_REPO" ]]; then
    remote_path="$filename"
  else
    remote_path="${PATH_IN_REPO%/}/$filename"
  fi

  hf upload "$HF_REPO_ID" "$LOCAL_PATH" "$remote_path" \
    --repo-type "$REPO_TYPE" \
    --token "$HF_TOKEN"

else
  die "LOCAL_PATH не является ни файлом, ни папкой: $LOCAL_PATH"
fi

log "Готово ❤️"
log "Repo: https://huggingface.co/$HF_REPO_ID"
