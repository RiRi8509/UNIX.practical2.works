#!/bin/sh

SHARED_DIR=${SHARED_DIR:-/shared}
LOCK_FILE="$SHARED_DIR/.lock"
CURRENT_FILE=
LOCAL_COUNTER=0

if ! mkdir -p "$SHARED_DIR"; then
    echo "Ошибка: не удалось подготовить общий каталог '$SHARED_DIR'" >&2
    exit 1
fi

if [ ! -d "$SHARED_DIR" ]; then
    echo "Ошибка: общий каталог '$SHARED_DIR' недоступен" >&2
    exit 2
fi

CONTAINER_ID=$(cat /proc/sys/kernel/random/uuid)

if [ -z "$CONTAINER_ID" ]; then
    echo "Ошибка: не удалось создать идентификатор контейнера" >&2
    exit 3
fi

cleanup() {
    result=$?
    trap - 0 HUP INT QUIT PIPE TERM

    if [ -n "$CURRENT_FILE" ]; then
        rm -f -- "$CURRENT_FILE"
    fi

    exit "$result"
}

trap cleanup 0 HUP INT QUIT PIPE TERM

exec 9>"$LOCK_FILE"

echo "Контейнер $CONTAINER_ID запущен и готов к работе."

while :; do
    LOCAL_COUNTER=$((LOCAL_COUNTER + 1))

    if ! flock -x 9; then
        echo "Ошибка: не удалось установить блокировку" >&2
        exit 4
    fi

    candidate=1

    while :; do
        FILE_NAME=$(printf '%03d' "$candidate")
        TARGET_FILE="$SHARED_DIR/$FILE_NAME"

        if [ ! -e "$TARGET_FILE" ]; then
            CURRENT_FILE="$TARGET_FILE"
            break
        fi

        candidate=$((candidate + 1))
    done

    if ! printf 'container_id=%s\nsequence=%s\n' \
        "$CONTAINER_ID" "$LOCAL_COUNTER" >"$CURRENT_FILE"; then
        flock -u 9
        echo "Ошибка: не удалось создать файл '$CURRENT_FILE'" >&2
        exit 5
    fi

    if ! flock -u 9; then
        echo "Ошибка: не удалось снять блокировку" >&2
        exit 6
    fi

    echo "Создан файл $FILE_NAME: контейнер=$CONTAINER_ID, номер=$LOCAL_COUNTER"
    sleep 1

    if ! rm -f -- "$CURRENT_FILE"; then
        echo "Ошибка: не удалось удалить файл '$CURRENT_FILE'" >&2
        exit 7
    fi

    echo "Удалён файл $FILE_NAME: контейнер=$CONTAINER_ID, номер=$LOCAL_COUNTER"
    CURRENT_FILE=

    sleep 1
done
