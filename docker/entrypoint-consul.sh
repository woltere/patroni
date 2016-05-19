#!/bin/bash

function usage()
{
    cat <<__EOF__
Usage: $0

Options:

    --consul    CONSUL  Provide an external consul to connect to
    --name      NAME    Give the cluster a specific name

Examples:

    $0 --consul=127.17.0.84:8301
    $0
    $0 --name=true_scotsman
__EOF__
}

DOCKER_IP=$(hostname --ip-address)
PATRONI_SCOPE=${PATRONI_SCOPE:-batman}

optspec=":vh-:"
while getopts "$optspec" optchar; do
    case "${optchar}" in
        -)
            case "${OPTARG}" in
                cheat)
                    CHEAT=1
                    ;;
                name)
                    PATRONI_SCOPE="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                name=*)
                    PATRONI_SCOPE=${OPTARG#*=}
                    ;;
                consul)
                    CONSUL="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                consul=*)
                    CONSUL=${OPTARG#*=}
                    ;;
                help)
                    usage
                    exit 0
                    ;;
                *)
                    if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                        echo "Unknown option --${OPTARG}" >&2
                    fi
                    ;;
            esac;;
        *)
            if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                echo "Non-option argument: '-${OPTARG}'" >&2
                usage
                exit 1
            fi
            ;;
    esac
done

mkdir -p ~postgres/.config/patroni
cat > ~postgres/.config/patroni/patronictl.yaml <<__EOF__
{dcs_api: 'consul://${CONSUL}', namespace: /service/}
__EOF__

cat > /patroni/postgres.yaml <<__EOF__

ttl: &ttl 30
loop_wait: &loop_wait 10
scope: &scope '${PATRONI_SCOPE}'
namespace: 'patroni'
restapi:
  listen: 0.0.0.0:8008
  connect_address: ${DOCKER_IP}:8008
consul:
  scope: *scope
  ttl: *ttl
  host: ${CONSUL}
postgresql:
  name: ${HOSTNAME}
  scope: *scope
  listen: 0.0.0.0:5432
  connect_address: ${DOCKER_IP}:5432
  data_dir: data/postgresql0
  maximum_lag_on_failover: 1048576 # 1 megabyte in bytes
  pg_hba:
  - host all all 0.0.0.0/0 md5
#  - hostssl all all 0.0.0.0/0 md5
  - host replication replicator ${DOCKER_IP}/16    md5
  replication:
    username: replicator
    password: rep-pass
    network:  127.0.0.1/32
  superuser:
    password: zalando
  restore: patroni/scripts/restore.py
  admin:
    username: admin
    password: admin
  parameters:
    archive_mode: "on"
    wal_level: hot_standby
    archive_command: 'true'
    max_wal_senders: 20
    listen_addresses: 0.0.0.0
    max_wal_size: 1GB
    min_wal_size: 128MB
    wal_keep_segments: 64
    archive_timeout: 1800s
    max_replication_slots: 20
    hot_standby: "on"
__EOF__

cat /patroni/postgres.yaml

if [ ! -z $CHEAT ]
then
    while :
    do
        sleep 60
    done
else
    exec python /patroni.py /patroni/postgres.yaml
fi
