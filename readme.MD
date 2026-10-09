# Hadoop YARN

## Архитектура

HW2 разворачивается поверх HDFS-кластера из HW1.

Используются 4 виртуальные машины:

| Host | IP | Роль |
|---|---|---|
| `team-22-en` | `10.22.0.10` | Edge, DataNode, SecondaryNameNode, NodeManager, JobHistoryServer, nginx |
| `team-22-nn` | `10.22.0.11` | NameNode, ResourceManager |
| `team-22-00` | `10.22.0.12` | DataNode, NodeManager |
| `team-22-01` | `10.22.0.13` | DataNode, NodeManager |

Схема:

```text
                         10.22.0.11
                 NameNode + ResourceManager
                           |
              +------------+------------+
              |            |            |
              v            v            v
         10.22.0.10   10.22.0.12   10.22.0.13
          DataNode      DataNode      DataNode
        NodeManager   NodeManager   NodeManager
            |
            +-- SecondaryNameNode
            +-- JobHistoryServer
            +-- nginx
```

## Конфигурация

`config/yarn-site.xml`:

- ResourceManager: `10.22.0.11`
- ResourceManager и NodeManager слушают `0.0.0.0`
- для MapReduce используется `mapreduce_shuffle`

`config/mapred-site.xml`:

- MapReduce запускается через YARN
- `HADOOP_MAPRED_HOME=/opt/hadoop-3.4.1`
- JobHistoryServer: `10.22.0.10:10020`
- JobHistory Web UI: `0.0.0.0:19888`

nginx на edge проксирует веб-интерфейсы:

| Порт | Сервис |
|---|---|
| `19070` | NameNode |
| `18088` | ResourceManager |
| `18089` | JobHistoryServer |
| `18042` | NodeManager `10.22.0.10` |
| `18043` | NodeManager `10.22.0.12` |
| `18044` | NodeManager `10.22.0.13` |

## Запуск

Перед запуском должен быть развернут HW1.

```bash
cd ~/yarn-hw2
./deploy.sh
```

`deploy.sh`:

1. Проверяет Hadoop и наличие трех работающих DataNode.
2. Создает backup HW1.
3. Исправляет `/etc/hosts`.
4. Копирует YARN и MapReduce конфиги на все машины.
5. Запускает ResourceManager.
6. Запускает три NodeManager.
7. Запускает JobHistoryServer.
8. Устанавливает и настраивает nginx.
9. Проверяет процессы, YARN nodes и веб-интерфейсы.

Backup сохраняется в:

```text
backup/hw1-baseline
```

Если backup уже существует, он не перезаписывается.

## Откат

Для возврата к состоянию HW1:

```bash
./scripts/rollback.sh
```

`rollback.sh`:

- останавливает ResourceManager, NodeManager и JobHistoryServer;
- восстанавливает Hadoop-конфиги;
- восстанавливает `/etc/hosts`;
- удаляет nginx-конфигурацию HW2;
- проверяет наличие трех DataNode.

После rollback остаются процессы HW1:

```text
10.22.0.10:
DataNode
SecondaryNameNode

10.22.0.11:
NameNode

10.22.0.12:
DataNode

10.22.0.13:
DataNode
```

## Проверка YARN

```bash
/opt/hadoop-3.4.1/bin/yarn node -list
```

Результат:

```text
Total Nodes:3

team-22-00   RUNNING
team-22-en   RUNNING
team-22-01   RUNNING
```

## Проверка MapReduce

Тестовый WordCount:

```bash
echo "cat dog cat hadoop yarn mapreduce cat" > /tmp/mr-input.txt

/opt/hadoop-3.4.1/bin/hdfs dfs -mkdir -p /hw2/input
/opt/hadoop-3.4.1/bin/hdfs dfs -put -f /tmp/mr-input.txt /hw2/input/
/opt/hadoop-3.4.1/bin/hdfs dfs -rm -r -f /hw2/output

/opt/hadoop-3.4.1/bin/hadoop jar \
  /opt/hadoop-3.4.1/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.4.1.jar \
  wordcount \
  /hw2/input \
  /hw2/output

/opt/hadoop-3.4.1/bin/hdfs dfs -cat /hw2/output/part-r-00000
```

Результат:

```text
cat        3
dog        1
hadoop     1
mapreduce  1
yarn       1
```

В ResourceManager задача имеет состояние:

```text
FINISHED
SUCCEEDED
```

## Web UI

Внешние порты edge закрыты инфраструктурным firewall, поэтому для проверки используется SSH port forwarding:

```powershell
ssh -i ~/.ssh/lhr_ed25519 `
  -L 19070:127.0.0.1:19070 `
  -L 18088:127.0.0.1:18088 `
  -L 18089:127.0.0.1:18089 `
  -L 18042:127.0.0.1:18042 `
  -L 18043:127.0.0.1:18043 `
  -L 18044:127.0.0.1:18044 `
  team@2.59.80.29
```

После подключения доступны:

```text
http://127.0.0.1:19070
http://127.0.0.1:18088
http://127.0.0.1:18089
http://127.0.0.1:18042
http://127.0.0.1:18043
http://127.0.0.1:18044
```

## Результат

### NameNode

- Live Nodes: `3`
- Dead Nodes: `0`

![NameNode](1.png)

### ResourceManager

- Active Nodes: `3`
- WordCount: `FINISHED`
- Final Status: `SUCCEEDED`

![ResourceManager](2.png)

### JobHistoryServer

WordCount отображается в истории выполненных MapReduce jobs.

![JobHistoryServer](3.png)

### NodeManager `10.22.0.10`

- NodeHealthStatus: `true`
- Hadoop Version: `3.4.1`

![NodeManager 10.22.0.10](4.png)

### NodeManager `10.22.0.12`

- NodeHealthStatus: `true`
- Hadoop Version: `3.4.1`

![NodeManager 10.22.0.12](5.png)

### NodeManager `10.22.0.13`

- NodeHealthStatus: `true`
- Hadoop Version: `3.4.1`

![NodeManager 10.22.0.13](6.png)

### YARN Nodes

Все три NodeManager зарегистрированы в ResourceManager и имеют состояние `RUNNING`.

![YARN Nodes](7.png)
