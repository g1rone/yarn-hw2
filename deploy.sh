#!/usr/bin/env bash
set -euo pipefail

HADOOP_DIR="/opt/hadoop-3.4.1"
SSH_KEY="$HOME/.ssh/team_internal"

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

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
NGINX_CONFIG="$ROOT_DIR/nginx/yarn-hw2.conf"

SSH_OPTS=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o IdentitiesOnly=yes
    -i "$SSH_KEY"
)

echo "=== Checking HW1 baseline ==="

if [ ! -x "$HADOOP_DIR/bin/hdfs" ]; then
    echo "Hadoop not found: $HADOOP_DIR"
    exit 1
fi

if ! "$HADOOP_DIR/bin/hdfs" dfsadmin -report | grep -q "Live datanodes (3)"; then
    echo "Expected 3 live DataNodes"
    exit 1
fi

echo "=== HW1 baseline OK ==="

echo "=== Creating HW1 baseline backup if needed ==="

"$ROOT_DIR/scripts/backup-hw1.sh"

echo "=== Checking HW2 files ==="

for file in yarn-site.xml mapred-site.xml; do
    if [ ! -f "$CONFIG_DIR/$file" ]; then
        echo "Missing config: $CONFIG_DIR/$file"
        exit 1
    fi
done

if [ ! -f "$NGINX_CONFIG" ]; then
    echo "Missing nginx config: $NGINX_CONFIG"
    exit 1
fi

echo "=== Fixing hostname resolution ==="

sudo sed -i '/127\.0\.1\.1.*team-22-en/d' /etc/hosts

if ! grep -q '^10\.22\.0\.10 .*team-22-en\.hse\.c\.mws' /etc/hosts; then
    echo '10.22.0.10 team-22-en.hse.c.mws team-22-en' \
        | sudo tee -a /etc/hosts >/dev/null
fi

ssh "${SSH_OPTS[@]}" team@10.22.0.11 "
    sudo sed -i '/127\.0\.1\.1.*team-22-nn/d' /etc/hosts

    if ! grep -q '^10\.22\.0\.11 .*team-22-nn\.hse\.c\.mws' /etc/hosts; then
        echo '10.22.0.11 team-22-nn.hse.c.mws team-22-nn' \
            | sudo tee -a /etc/hosts >/dev/null
    fi
"

ssh "${SSH_OPTS[@]}" team@10.22.0.12 "
    sudo sed -i '/127\.0\.1\.1.*team-22-00/d' /etc/hosts

    if ! grep -q '^10\.22\.0\.12 .*team-22-00\.hse\.c\.mws' /etc/hosts; then
        echo '10.22.0.12 team-22-00.hse.c.mws team-22-00' \
            | sudo tee -a /etc/hosts >/dev/null
    fi
"

ssh "${SSH_OPTS[@]}" team@10.22.0.13 "
    sudo sed -i '/127\.0\.1\.1.*team-22-01/d' /etc/hosts

    if ! grep -q '^10\.22\.0\.13 .*team-22-01\.hse\.c\.mws' /etc/hosts; then
        echo '10.22.0.13 team-22-01.hse.c.mws team-22-01' \
            | sudo tee -a /etc/hosts >/dev/null
    fi
"

echo "=== Installing Hadoop configs on edge ==="

sudo cp \
    "$CONFIG_DIR/yarn-site.xml" \
    "$HADOOP_DIR/etc/hadoop/yarn-site.xml"

sudo cp \
    "$CONFIG_DIR/mapred-site.xml" \
    "$HADOOP_DIR/etc/hadoop/mapred-site.xml"

echo "=== Installing Hadoop configs on remote hosts ==="

for host in "${ALL_REMOTE_HOSTS[@]}"; do
    echo "--- $host ---"

    scp "${SSH_OPTS[@]}" \
        "$CONFIG_DIR/yarn-site.xml" \
        "$CONFIG_DIR/mapred-site.xml" \
        "team@$host:/tmp/"

    ssh "${SSH_OPTS[@]}" "team@$host" "
        sudo cp /tmp/yarn-site.xml \
            '$HADOOP_DIR/etc/hadoop/yarn-site.xml'

        sudo cp /tmp/mapred-site.xml \
            '$HADOOP_DIR/etc/hadoop/mapred-site.xml'

        rm -f \
            /tmp/yarn-site.xml \
            /tmp/mapred-site.xml
    "
done

echo "=== Starting ResourceManager ==="

ssh "${SSH_OPTS[@]}" "team@$RM_HOST" "
    if ! jps | awk '{print \$2}' | grep -qx ResourceManager; then
        '$HADOOP_DIR/bin/yarn' --daemon start resourcemanager
    else
        echo 'ResourceManager already running'
    fi
"

echo "=== Starting NodeManager on edge ==="

if ! jps | awk '{print $2}' | grep -qx NodeManager; then
    "$HADOOP_DIR/bin/yarn" --daemon start nodemanager
else
    echo "NodeManager already running on edge"
fi

echo "=== Starting NodeManagers on workers ==="

for host in "${WORKER_HOSTS[@]}"; do
    ssh "${SSH_OPTS[@]}" "team@$host" "
        if ! jps | awk '{print \$2}' | grep -qx NodeManager; then
            '$HADOOP_DIR/bin/yarn' --daemon start nodemanager
        else
            echo 'NodeManager already running'
        fi
    "
done

echo "=== Starting JobHistoryServer ==="

if ! jps | awk '{print $2}' | grep -qx JobHistoryServer; then
    "$HADOOP_DIR/bin/mapred" --daemon start historyserver
else
    echo "JobHistoryServer already running"
fi

echo "=== Installing nginx if needed ==="

if ! command -v nginx >/dev/null 2>&1; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
fi

echo "=== Configuring nginx ==="

sudo mkdir -p \
    /etc/nginx/sites-available \
    /etc/nginx/sites-enabled

sudo cp \
    "$NGINX_CONFIG" \
    /etc/nginx/sites-available/yarn-hw2.conf

sudo ln -sf \
    /etc/nginx/sites-available/yarn-hw2.conf \
    /etc/nginx/sites-enabled/yarn-hw2.conf

sudo nginx -t

sudo systemctl enable nginx
sudo systemctl restart nginx

echo "=== Waiting for services ==="

sleep 5

echo "=== Checking processes ==="

echo "--- edge ---"
jps

echo "--- ResourceManager ---"
ssh "${SSH_OPTS[@]}" "team@$RM_HOST" 'jps'

for host in "${WORKER_HOSTS[@]}"; do
    echo "--- $host ---"
    ssh "${SSH_OPTS[@]}" "team@$host" 'jps'
done

echo "=== Checking hostname resolution ==="

getent hosts team-22-en.hse.c.mws

ssh "${SSH_OPTS[@]}" team@10.22.0.12 \
    'getent hosts team-22-00.hse.c.mws'

ssh "${SSH_OPTS[@]}" team@10.22.0.13 \
    'getent hosts team-22-01.hse.c.mws'

echo "=== Checking YARN nodes ==="

"$HADOOP_DIR/bin/yarn" node -list

echo "=== Checking nginx endpoints ==="

for port in \
    19070 \
    18088 \
    18089 \
    18042 \
    18043 \
    18044
do
    echo "--- localhost:$port ---"
    curl -sS -o /dev/null \
        -w "HTTP %{http_code}\n" \
        "http://127.0.0.1:$port/" || true
done

echo
echo "=== HW2 deployment completed ==="
