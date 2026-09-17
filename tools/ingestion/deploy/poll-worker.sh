#!/bin/sh
# One bounded invocation at a time. Exit status is logged by the worker;
# transient failures retry on the next check. Docker forwards stop signals.
trap 'exit 0' TERM INT
while true; do
    python3 -m ingestion.worker &
    wait "$!"
    sleep 60 &
    wait "$!"
done
