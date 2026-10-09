#!/usr/bin/env bash
set -euo pipefail

HADOOP_DIR="/opt/hadoop-3.4.1"
SSH_KEY="$HOME/.ssh/team_internal"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$ROOT_DIR/backup/hw1-baseline"

RM_HOST="10.22.0.11"

WORKER_HOSTS=(
    "10.22.0.12"
    "10.22.0.13"
)

ALL_REMOTE_HOSTS=(
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

if [ ! -d "$BACKUP_DIR" ]; then
    echo "HW1 baseline backup not found:"
    echo "$BACKUP_DIR"
    exit 1
fi

echo "=== Stopping HW2 services ==="

"$HADOOP_DIR/bin/yarn" --daemon stop nodemanager 2>/dev/null || true
"$HADOOP_DIR/bin/mapred" --daemon stop historyserver 2>/dev/null || true

ssh "${SSH_OPTS[@]}" "team@$RM_HOST" "
    '$HADOOP_DIR/bin/yarn' --daemon stop resourcemanager 2>/dev/null || true
" || true

for host in "${WORKER_HOSTS[@]}"; do
    ssh "${SSH_OPTS[@]}" "team@$host" "
        '$HADOOP_DIR/bin/yarn' --daemon stop nodemanager 2>/dev/null || true
    " || true
done

echo "=== Restoring edge Hadoop configs ==="

for file in \
    core-site.xml \
    hdfs-site.xml \
    workers \
    yarn-site.xml \
    mapred-site.xml
do
    if [ -f "$BACKUP_DIR/edge/$file" ]; then
        sudo cp \
            "$BACKUP_DIR/edge/$file" \
            "$HADOOP_DIR/etc/hadoop/$file"
    fi
done

if [ -f "$BACKUP_DIR/edge/hosts" ]; then
    sudo cp "$BACKUP_DIR/edge/hosts" /etc/hosts
fi

echo "=== Restoring remote hosts ==="

for host in "${ALL_REMOTE_HOSTS[@]}"; do
    echo "--- $host ---"

    for file in \
        core-site.xml \
        hdfs-site.xml \
        workers \
        yarn-site.xml \
        mapred-site.xml
    do
        if [ -f "$BACKUP_DIR/$host/$file" ]; then
            scp "${SSH_OPTS[@]}" \
                "$BACKUP_DIR/$host/$file" \
                "team@$host:/tmp/$file"

            ssh "${SSH_OPTS[@]}" "team@$host" "
                sudo cp /tmp/$file '$HADOOP_DIR/etc/hadoop/$file'
                rm -f /tmp/$file
            "
        fi
    done

    if [ -f "$BACKUP_DIR/$host/hosts" ]; then
        scp "${SSH_OPTS[@]}" \
            "$BACKUP_DIR/$host/hosts" \
            "team@$host:/tmp/hosts.hw1"

        ssh "${SSH_OPTS[@]}" "team@$host" "
            sudo cp /tmp/hosts.hw1 /etc/hosts
            rm -f /tmp/hosts.hw1
        "
    fi
done

echo "=== Removing HW2 nginx config ==="

sudo rm -f /etc/nginx/sites-enabled/yarn-hw2.conf 2>/dev/null || true
sudo rm -f /etc/nginx/sites-available/yarn-hw2.conf 2>/dev/null || true

if command -v nginx >/dev/null 2>&1; then
    sudo nginx -t >/dev/null 2>&1 && sudo systemctl reload nginx || true
fi

echo "=== Verifying HW1 HDFS ==="

"$HADOOP_DIR/bin/hdfs" dfsadmin -report | grep "Live datanodes"

echo
echo "=== Current processes ==="

echo "--- edge ---"
jps

for host in "${ALL_REMOTE_HOSTS[@]}"; do
    echo "--- $host ---"
    ssh "${SSH_OPTS[@]}" "team@$host" 'jps' || true
done

echo
echo "=== HW2 rollback complete ==="
