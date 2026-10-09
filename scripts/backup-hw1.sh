#!/usr/bin/env bash
set -euo pipefail

HADOOP_DIR="/opt/hadoop-3.4.1"
SSH_KEY="$HOME/.ssh/team_internal"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$ROOT_DIR/backup/hw1-baseline"

REMOTE_HOSTS=(
    "10.22.0.11"
    "10.22.0.12"
    "10.22.0.13"
)

SSH_OPTS=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o IdentitiesOnly=yes
    -i "$SSH_KEY"
)

echo "=== Creating HW1 baseline backup ==="

if [ -d "$BACKUP_DIR" ]; then
    echo "Backup already exists:"
    echo "$BACKUP_DIR"
    echo "Nothing changed."
    exit 0
fi

mkdir -p "$BACKUP_DIR/edge"

echo "=== Backing up edge ==="

for file in \
    core-site.xml \
    hdfs-site.xml \
    workers \
    yarn-site.xml \
    mapred-site.xml
do
    if [ -f "$HADOOP_DIR/etc/hadoop/$file" ]; then
        cp -a \
            "$HADOOP_DIR/etc/hadoop/$file" \
            "$BACKUP_DIR/edge/"
    fi
done

sudo cp -a /etc/hosts "$BACKUP_DIR/edge/hosts"

jps > "$BACKUP_DIR/edge/jps.txt" || true

"$HADOOP_DIR/bin/hdfs" dfsadmin -report \
    > "$BACKUP_DIR/edge/dfsadmin-report.txt" || true

for host in "${REMOTE_HOSTS[@]}"; do
    echo "=== Backing up $host ==="

    mkdir -p "$BACKUP_DIR/$host"

    for file in \
        core-site.xml \
        hdfs-site.xml \
        workers \
        yarn-site.xml \
        mapred-site.xml
    do
        scp "${SSH_OPTS[@]}" \
            "team@$host:$HADOOP_DIR/etc/hadoop/$file" \
            "$BACKUP_DIR/$host/" \
            2>/dev/null || true
    done

    ssh "${SSH_OPTS[@]}" \
        "team@$host" \
        'sudo cat /etc/hosts' \
        > "$BACKUP_DIR/$host/hosts"

    ssh "${SSH_OPTS[@]}" \
        "team@$host" \
        'jps' \
        > "$BACKUP_DIR/$host/jps.txt" || true
done

echo "=== HW1 baseline backup complete ==="
echo "Saved to:"
echo "$BACKUP_DIR"
