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
        flock -x 9 2>/dev/null
        rm -f -- "$CURRENT_FILE"
        CURRENT_FILE=
        flock -u 8 2>/dev/null
        exec 8>&-
        flock -u 9 2>/dev/null
    fi

    exit "$result"
}

trap cleanup 0 HUP INT QUIT PIPE TERM

exec 9>"$LOCK_FILE"

echo "Контейнер $CONTAINER_ID запущен и готов к работе."

while :; do
    LOCAL_COUNTER=$((LOCAL_COUNTER + 1))
    RECOVERED_FILE=

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

        # Активный контейнер удерживает блокировку на своём числовом файле.
        # Если блокировка свободна, файл остался после аварийного завершения.
        if exec 7<>"$TARGET_FILE"; then
            if flock -n -x 7; then
                if ! rm -f -- "$TARGET_FILE"; then
                    flock -u 7
                    exec 7>&-
                    flock -u 9
                    echo "Ошибка: не удалось удалить оставшийся файл '$TARGET_FILE'" >&2
                    exit 7
                fi

                RECOVERED_FILE="$FILE_NAME"
                flock -u 7
                exec 7>&-
                CURRENT_FILE="$TARGET_FILE"
                break
            fi

            exec 7>&-
        fi

        candidate=$((candidate + 1))
    done

    # Блокировка дескриптора 8 живёт столько же, сколько числовой файл.
    # При SIGKILL ядро закроет дескриптор и автоматически снимет блокировку.
    if ! exec 8>"$CURRENT_FILE"; then
        flock -u 9
        echo "Ошибка: не удалось создать файл '$CURRENT_FILE'" >&2
        exit 5
    fi

    if ! flock -x 8; then
        exec 8>&-
        rm -f -- "$CURRENT_FILE"
        flock -u 9
        echo "Ошибка: не удалось заблокировать файл '$CURRENT_FILE'" >&2
        exit 8
    fi

    if ! printf 'container_id=%s\nsequence=%s\n' \
        "$CONTAINER_ID" "$LOCAL_COUNTER" >&8; then
        flock -u 8
        exec 8>&-
        rm -f -- "$CURRENT_FILE"
        flock -u 9
        echo "Ошибка: не удалось создать файл '$CURRENT_FILE'" >&2
        exit 5
    fi

    if ! flock -u 9; then
        echo "Ошибка: не удалось снять блокировку" >&2
        exit 6
    fi

    if [ -n "$RECOVERED_FILE" ]; then
        echo "Освобождён номер $RECOVERED_FILE после аварийного завершения контейнера."
    fi

    echo "Создан файл $FILE_NAME: контейнер=$CONTAINER_ID, номер=$LOCAL_COUNTER"
    sleep 1

    if ! flock -x 9; then
        echo "Ошибка: не удалось установить блокировку" >&2
        exit 4
    fi

    if ! rm -f -- "$CURRENT_FILE"; then
        flock -u 9
        echo "Ошибка: не удалось удалить файл '$CURRENT_FILE'" >&2
        exit 7
    fi

    CURRENT_FILE=
    flock -u 8
    exec 8>&-

    if ! flock -u 9; then
        echo "Ошибка: не удалось снять блокировку" >&2
        exit 6
    fi

    echo "Удалён файл $FILE_NAME: контейнер=$CONTAINER_ID, номер=$LOCAL_COUNTER"
    sleep 1
done
